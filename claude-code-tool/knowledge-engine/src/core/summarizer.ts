import { existsSync, readFileSync, writeFileSync, renameSync, mkdirSync } from 'node:fs'
import { join } from 'node:path'
import { spawnSync } from 'node:child_process'
import type { SummarizeResult, TempKnowledgeMeta, StateFile } from './types.js'
import { projectPathToSlug, findProjectRoot } from './slug.js'
import { ensureKnowledgeDir } from './config.js'
import { callQwen, isQwenAvailable } from './ai.js'

// 单次执行最多处理的 commit 数量，防止 Stop hook 超时
const MAX_COMMITS_PER_RUN = 5

// diff 大小阈值，超过此值只传 stat 摘要给 AI
const DIFF_SIZE_LIMIT = 10000

// 传给 AI 的 diff 最大字符数
const DIFF_SUMMARY_MAX_LENGTH = 2000

// git 空树的 hash，用于初始 commit 的 diff
const EMPTY_TREE_HASH = '4b825dc642cb6eb9a060e54bf899d15363d7aa91'

/**
 * 总结层主入口：批量处理未总结的 git commit，生成临时知识文件
 *
 * 触发方式：Stop hook 或 crontab 通过 cli.ts 的 process 命令调用
 * 并发安全：state.json 使用原子 rename 写入，多会话同时 Stop 时自动跳过已处理的 commit
 */
export async function summarize(projectRoot: string): Promise<void> {
  // 非 git 项目静默退出，不报错（可能是在非项目目录误触）
  const gitRoot = findProjectRoot(projectRoot)
  if (!gitRoot) return

  const slug = projectPathToSlug(gitRoot)
  const knowledgeDir = ensureKnowledgeDir(slug)
  const state = loadState(knowledgeDir)
  const lastCommit = state.lastSummarizedCommit ?? getInitialCommit(gitRoot)

  // 获取未总结的 commit 列表
  const commits = getUnprocessedCommits(gitRoot, lastCommit)
  if (commits.length === 0) return

  // 限制单次处理数量，剩余 commit 留给下次执行
  const commitsToProcess = commits.slice(0, MAX_COMMITS_PER_RUN)

  const qwenAvailable = isQwenAvailable()

  for (const { hash, message, timestamp } of commitsToProcess) {
    const diff = getCommitDiff(gitRoot, hash, lastCommit)
    const changelogEntries = getChangelogEntries(knowledgeDir, state.lastSummarizedTimestamp, timestamp)
    const filesList = getDiffStat(gitRoot, hash, lastCommit)

    if (qwenAvailable) {
      await processWithAI(gitRoot, knowledgeDir, { hash, message, timestamp, diff, changelogEntries, filesList })
    } else {
      processAsRaw(gitRoot, knowledgeDir, { hash, message, timestamp, diff: filesList })
    }

    // 每处理一个 commit 就更新 state，防止中途失败导致重复处理
    updateState(knowledgeDir, { lastSummarizedCommit: hash, lastSummarizedTimestamp: timestamp })
  }
}

// ======================== State 管理 ========================

// 读取 state.json，不存在时返回空状态
function loadState(knowledgeDir: string): StateFile {
  const statePath = join(knowledgeDir, 'state.json')
  if (!existsSync(statePath)) {
    return { lastSummarizedCommit: '', lastSummarizedTimestamp: '' }
  }

  try {
    return JSON.parse(readFileSync(statePath, 'utf-8')) as StateFile
  } catch {
    // state.json 损坏时返回空状态，重新从头开始处理
    return { lastSummarizedCommit: '', lastSummarizedTimestamp: '' }
  }
}

// 原子写入 state.json：先写 .tmp 再 rename，保证并发安全
function updateState(knowledgeDir: string, state: StateFile): void {
  const statePath = join(knowledgeDir, 'state.json')
  const tmpPath = statePath + '.tmp'

  writeFileSync(tmpPath, JSON.stringify(state, null, 2), 'utf-8')
  renameSync(tmpPath, statePath)
}

// 获取仓库的初始 commit hash
function getInitialCommit(gitRoot: string): string {
  const result = spawnSync('git', ['rev-list', '--max-parents=0', 'HEAD'], {
    cwd: gitRoot,
    encoding: 'utf-8',
    timeout: 10000,
  })

  if (result.status !== 0 || !result.stdout.trim()) {
    // 极端情况：空仓库没有 commit，返回空字符串让 summarize 静默退出
    return ''
  }

  return result.stdout.trim()
}

// ======================== Git 操作 ========================

// 获取未总结的 commit 列表（从 lastCommit 之后到 HEAD）
function getUnprocessedCommits(gitRoot: string, lastCommit: string): Array<{ hash: string; message: string; timestamp: string }> {
  // lastCommit 为空时获取所有 commit
  const range = lastCommit ? `${lastCommit}..HEAD` : 'HEAD'

  // %x00 用 null byte 分隔，避免 subject 中的空格干扰解析
  const result = spawnSync(
    'git',
    ['log', range, '--format=%H%x00%s%x00%ct'],
    {
      cwd: gitRoot,
      encoding: 'utf-8',
      timeout: 10000,
    },
  )

  if (result.status !== 0 || !result.stdout.trim()) return []

  return result.stdout
    .trim()
    .split('\n')
    .map((line) => {
      const parts = line.split('\0')
      if (parts.length !== 3) return null
      const [hash, message, timestamp] = parts
      return { hash, message, timestamp }
    })
    .filter((c): c is NonNullable<typeof c> => c !== null)
}

// 获取 commit 的 diff 内容，根据大小决定返回完整 diff 还是仅 stat
function getCommitDiff(gitRoot: string, hash: string, lastSummarizedCommit: string): string {
  // 初始 commit 需要和空树对比
  const parent = lastSummarizedCommit ? `${hash}~1` : EMPTY_TREE_HASH

  // 先获取完整 diff 判断大小
  const fullResult = spawnSync(
    'git',
    ['diff', parent, hash],
    {
      cwd: gitRoot,
      encoding: 'utf-8',
      timeout: 15000,
      maxBuffer: 1024 * 1024, // 1MB 缓冲区
    },
  )

  const fullDiff = fullResult.stdout || ''

  // 超过阈值时只返回 stat，避免 AI 上下文过长
  if (fullDiff.length > DIFF_SIZE_LIMIT) {
    return getDiffStat(gitRoot, hash, lastSummarizedCommit)
  }

  // 截取前 2000 字符给 AI
  return fullDiff.slice(0, DIFF_SUMMARY_MAX_LENGTH)
}

// 获取 diff stat（文件变更统计）
function getDiffStat(gitRoot: string, hash: string, lastSummarizedCommit: string): string {
  const parent = lastSummarizedCommit ? `${hash}~1` : EMPTY_TREE_HASH

  const result = spawnSync(
    'git',
    ['diff', '--stat', parent, hash],
    {
      cwd: gitRoot,
      encoding: 'utf-8',
      timeout: 10000,
    },
  )

  return result.stdout?.trim() || '无法获取 diff stat'
}

// ======================== Changelog 读取 ========================

// 从 changelog.log 中读取时间范围内的条目
function getChangelogEntries(knowledgeDir: string, sinceTimestamp: string, untilTimestamp: string): string {
  const changelogPath = join(knowledgeDir, 'changelog.log')
  if (!existsSync(changelogPath)) return ''

  try {
    const content = readFileSync(changelogPath, 'utf-8')
    const lines = content.trim().split('\n')
    const since = sinceTimestamp ? new Date(sinceTimestamp).getTime() : 0
    const until = new Date(untilTimestamp).getTime() || Date.now()

    // 筛选时间范围内的条目（changelog 格式：timestamp|tool_name|file_path|preview）
    const filtered = lines.filter((line) => {
      const pipeIndex = line.indexOf('|')
      if (pipeIndex === -1) return false
      const entryTs = new Date(line.slice(0, pipeIndex)).getTime()
      if (isNaN(entryTs)) return false
      return entryTs > since && entryTs <= until
    })

    // 最多返回 20 条，防止 prompt 过长
    return filtered.slice(0, 20).join('\n')
  } catch {
    return ''
  }
}

// ======================== AI 处理 ========================

interface CommitInfo {
  hash: string
  message: string
  timestamp: string
  diff: string
  changelogEntries: string
  filesList: string
}

// 用 AI 分析 commit 并生成临时知识文件
async function processWithAI(
  _gitRoot: string,
  knowledgeDir: string,
  info: CommitInfo,
): Promise<void> {
  const prompt = buildSummarizePrompt(info)

  try {
    const rawOutput = await callQwen(prompt)
    const result = parseAIResponse(rawOutput)

    if (result && result.should_summarize) {
      writeTempKnowledge(knowledgeDir, info.hash, {
        name: info.message,
        description: result.summary,
        tags: extractTags(info.filesList, result.topics),
        commit: info.hash,
        timestamp: info.timestamp,
        topics: result.topics,
        status: 'summarized',
      }, buildKnowledgeBody(result))
    }
    // should_summarize=false 时静默跳过，不需要记录无价值的变更
  } catch {
    // AI 不可用或返回无效时走降级路径
    processAsRaw(_gitRoot, knowledgeDir, info)
  }
}

// 构建给 AI 的 prompt
function buildSummarizePrompt(info: CommitInfo): string {
  return `你是一个代码变更知识提取器。分析以下代码变更，提取有价值的业务或技术知识。

## 操作序列
${info.changelogEntries || '无操作记录'}

## Commit 信息
Message: ${info.message}
Files changed: ${info.filesList}

## Diff 摘要（前 2000 字）
${info.diff}

## 输出要求
返回 JSON：
{
  "should_summarize": true/false,
  "topics": ["topic1"],
  "summary": "2-3 句话总结",
  "key_decisions": ["决策及原因"],
  "patterns": ["发现的模式"]
}

should_summarize 判断：涉及架构决策、新功能、重要 bug 修复为 true；格式化、依赖更新、typo 为 false。`
}

// 解析 AI 返回的 JSON，处理各种异常格式
function parseAIResponse(raw: string): SummarizeResult | null {
  // AI 有时会在 JSON 外包裹 markdown 代码块，需要提取
  const jsonMatch = raw.match(/```(?:json)?\s*([\s\S]*?)```/) || [null, raw]
  const jsonStr = (jsonMatch[1] || raw).trim()

  try {
    const parsed = JSON.parse(jsonStr)
    // 基本结构校验
    if (typeof parsed.should_summarize === 'boolean') {
      return {
        should_summarize: parsed.should_summarize,
        topics: Array.isArray(parsed.topics) ? parsed.topics : [],
        summary: typeof parsed.summary === 'string' ? parsed.summary : '',
        key_decisions: Array.isArray(parsed.key_decisions) ? parsed.key_decisions : [],
        patterns: Array.isArray(parsed.patterns) ? parsed.patterns : [],
      }
    }
    return null
  } catch {
    return null
  }
}

// 构建临时知识的 body 内容（markdown 格式）
function buildKnowledgeBody(result: SummarizeResult): string {
  const sections: string[] = []

  if (result.summary) {
    sections.push(`## 摘要\n\n${result.summary}`)
  }

  if (result.key_decisions.length > 0) {
    sections.push(`## 关键决策\n\n${result.key_decisions.map((d) => `- ${d}`).join('\n')}`)
  }

  if (result.patterns.length > 0) {
    sections.push(`## 发现的模式\n\n${result.patterns.map((p) => `- ${p}`).join('\n')}`)
  }

  return sections.join('\n\n')
}

// ======================== 降级处理 ========================

// 无 AI 时用原始 commit 信息生成临时知识文件
function processAsRaw(
  _gitRoot: string,
  knowledgeDir: string,
  info: { hash: string; message: string; timestamp: string; diff: string },
): void {
  const tags = extractTagsFromPaths(info.diff)

  writeTempKnowledge(knowledgeDir, info.hash, {
    name: info.message,
    description: info.message,
    tags,
    commit: info.hash,
    timestamp: info.timestamp,
    topics: [],
    status: 'raw',
  }, `## Commit\n\n${info.message}\n\n## 变更统计\n\n${info.diff}`)
}

// ======================== 文件写入 ========================

// 从文件路径列表中提取标签（取关键目录名）
function extractTags(filesList: string, topics: string[]): string[] {
  const tags = new Set<string>(topics)

  // 从 diff stat 的文件路径中提取关键目录名
  const pathMatches = filesList.match(/[\w/.-]+\.\w+/g) || []
  for (const path of pathMatches) {
    const parts = path.split('/')
    // 取 src 下的第一级子目录作为 tag（如 src/core -> core）
    const srcIndex = parts.indexOf('src')
    if (srcIndex !== -1 && srcIndex + 1 < parts.length) {
      tags.add(parts[srcIndex + 1])
    }
  }

  return [...tags].slice(0, 5)
}

// 从 diff stat 中提取目录标签（降级路径使用）
function extractTagsFromPaths(stat: string): string[] {
  const tags = new Set<string>()
  const pathMatches = stat.match(/[\w/.-]+\.\w+/g) || []

  for (const path of pathMatches) {
    const parts = path.split('/')
    const srcIndex = parts.indexOf('src')
    if (srcIndex !== -1 && srcIndex + 1 < parts.length) {
      tags.add(parts[srcIndex + 1])
    }
  }

  return [...tags].slice(0, 5)
}

// 确保 temp 目录存在
function ensureTempDir(knowledgeDir: string): string {
  const tempDir = join(knowledgeDir, 'temp')
  if (!existsSync(tempDir)) {
    mkdirSync(tempDir, { recursive: true })
  }
  return tempDir
}

// 写入临时知识文件（frontmatter + body 格式）
function writeTempKnowledge(
  knowledgeDir: string,
  commitHash: string,
  meta: TempKnowledgeMeta,
  body: string,
): void {
  const tempDir = ensureTempDir(knowledgeDir)
  const filePath = join(tempDir, `${commitHash}.md`)

  // frontmatter 使用 YAML 格式，方便后续 consolidator 解析
  const frontmatter = Object.entries(meta)
    .map(([key, value]) => {
      if (Array.isArray(value)) {
        return `${key}: [${value.map((v) => `"${v}"`).join(', ')}]`
      }
      return `${key}: "${String(value).replace(/"/g, '\\"')}"`
    })
    .join('\n')

  const content = `---\n${frontmatter}\n---\n\n${body}\n`

  writeFileSync(filePath, content, 'utf-8')
}
