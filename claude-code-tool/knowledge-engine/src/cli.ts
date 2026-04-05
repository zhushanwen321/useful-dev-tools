#!/usr/bin/env bun
/**
 * Knowledge Engine CLI 入口
 *
 * 通过子命令分发到核心模块，设计为被 Claude Code hook 或 cron 调用。
 * 所有子命令都静默退出（exit 0），内部错误不阻止退出，
 * 因为 hook 脚本不应干扰用户的正常开发流程。
 *
 * 用法：
 *   bun run src/cli.ts record       # 从 stdin 读取 hook JSON，记录文件变更
 *   bun run src/cli.ts process      # 从 stdin 读取信号，执行总结 + 沉淀
 *   bun run src/cli.ts inject-index # 从 stdin 读取信号，输出知识库索引 JSON
 *   bun run src/cli.ts cleanup      # 清理已沉淀的 changelog 条目
 */

import { readFileSync, existsSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { spawnSync } from 'node:child_process'
import { record } from './core/recorder.js'
import { summarize } from './core/summarizer.js'
import { consolidate } from './core/consolidator.js'
import { projectPathToSlug, findProjectRoot } from './core/slug.js'
import { getKnowledgeDir } from './core/config.js'
import { parseHookInput } from './adapters/claude-code.js'
import type { StateFile } from './core/types.js'

/**
 * 从环境变量或 cwd 获取项目根路径
 * 优先级：CLAUDE_PROJECT_DIR 环境变量 > findProjectRoot(cwd) > cwd
 */
function getProjectRoot(fallback?: string): string {
  // Claude Code hook 会设置 CLAUDE_PROJECT_DIR
  const envRoot = process.env.CLAUDE_PROJECT_DIR
  if (envRoot) return envRoot

  // 尝试从 cwd 向上查找 .git
  const gitRoot = findProjectRoot(process.cwd())
  if (gitRoot) return gitRoot

  // 最后使用传入的 fallback 或 cwd
  return fallback || process.cwd()
}

/**
 * 从 stdin 读取全部内容
 * Claude Code hook 通过 stdin 传入 JSON 数据
 */
function readStdin(): Promise<string> {
  return new Promise((resolve) => {
    let data = ''
    process.stdin.setEncoding('utf-8')
    process.stdin.on('data', (chunk: string | Buffer) => {
      data += chunk.toString()
    })
    process.stdin.on('end', () => resolve(data))
    // stdin 可能不会被 close（比如 pipe 被提前断开），设置超时兜底
    setTimeout(() => resolve(data), 5000)
  })
}

// ======================== record 子命令 ========================

/**
 * record：记录一次文件变更到 changelog
 *
 * 从 stdin 读取 Claude Code 的 PostToolUse hook JSON，
 * 提取 tool_name、file_path、content/new_string/old_string，
 * 调用 recorder.record() 写入 changelog.log
 */
async function handleRecord(input: string, projectRoot: string): Promise<void> {
  const hookInput = parseHookInput(input)
  if (!hookInput?.tool_input) return

  const toolName = hookInput.tool ?? 'unknown'
  const toolInput = hookInput.tool_input

  record({
    tool_name: toolName,
    file_path: toolInput.file_path ?? '',
    content: toolInput.content,
    new_string: toolInput.new_string,
    old_string: toolInput.old_string,
    project_root: projectRoot,
  })
}

// ======================== process 子命令 ========================

/**
 * process：串行执行总结和沉淀
 *
 * 从 stdin 读取 Stop hook JSON（仅作为触发信号，内容不重要），
 * 依次调用 summarize -> consolidate。
 * 任何内部错误都 catch 住，不阻止 exit 0
 */
async function handleProcess(projectRoot: string): Promise<void> {
  try {
    await summarize(projectRoot)
  } catch {
    // 总结失败不应阻止后续沉淀尝试
  }

  try {
    await consolidate(projectRoot)
  } catch {
    // 沉淀失败静默忽略
  }
}

// ======================== inject-index 子命令 ========================

/**
 * inject-index：向 Claude Code SessionStart hook 输出知识库索引
 *
 * 读取 formal/index.md 和 formal/tag_index.md，
 * 如果存在则按 Claude Code 要求的 JSON 格式输出到 stdout。
 * 不存在则输出空 JSON {}
 */
function handleInjectIndex(input: string, projectRoot: string): void {
  const hookInput = parseHookInput(input)

  // SessionStart hook 的 JSON 中可能包含 cwd 字段
  // 优先级：hook JSON 中的 cwd > 环境变量 > process.cwd()
  const root = hookInput?.cwd || projectRoot
  const slug = projectPathToSlug(root)
  const knowledgeDir = getKnowledgeDir(slug)

  const indexPath = join(knowledgeDir, 'formal', 'index.md')
  const tagIndexPath = join(knowledgeDir, 'formal', 'tag_index.md')

  const parts: string[] = []

  if (existsSync(indexPath)) {
    parts.push(readFileSync(indexPath, 'utf-8'))
  }

  if (existsSync(tagIndexPath)) {
    parts.push(readFileSync(tagIndexPath, 'utf-8'))
  }

  const indexContent = parts.join('\n\n').trim()

  if (!indexContent) {
    // 无知识库索引，输出空 JSON
    console.log('{}')
    return
  }

  // Claude Code SessionStart hook 要求的输出格式
  const output = {
    hookSpecificOutput: {
      hookEventName: 'SessionStart',
      additionalContext: indexContent,
    },
  }

  console.log(JSON.stringify(output))
}

// ======================== cleanup 子命令 ========================

/**
 * cleanup：清理已被成功总结且已沉淀的 changelog 条目
 *
 * 条件：changelog 条目的时间戳早于 state.json.lastSummarizedCommit
 * 对应的 git commit 时间，且该 commit 的 temp 文件已不存在。
 *
 * temp 文件不存在说明该条目已被 consolidate 处理完毕（consolidate
 * 在成功后会删除对应的 temp 文件），可以安全清理 changelog。
 */
function handleCleanup(projectRoot: string): void {
  const gitRoot = findProjectRoot(projectRoot)
  if (!gitRoot) return

  const slug = projectPathToSlug(gitRoot)
  const knowledgeDir = getKnowledgeDir(slug)
  const changelogPath = join(knowledgeDir, 'changelog.log')
  const statePath = join(knowledgeDir, 'state.json')

  // changelog 或 state 不存在则无需清理
  if (!existsSync(changelogPath) || !existsSync(statePath)) return

  let state: StateFile
  try {
    state = JSON.parse(readFileSync(statePath, 'utf-8')) as StateFile
  } catch {
    return
  }

  if (!state.lastSummarizedCommit) return

  // 获取 lastSummarizedCommit 的 git commit 时间（unix timestamp）
  const gitResult = spawnSync(
    'git',
    ['log', '-1', '--format=%ct', state.lastSummarizedCommit],
    { cwd: gitRoot, encoding: 'utf-8', timeout: 10000 },
  )

  if (gitResult.status !== 0 || !gitResult.stdout.trim()) return

  const summarizedTimestamp = parseInt(gitResult.stdout.trim(), 10)
  if (isNaN(summarizedTimestamp)) return

  // 读取 changelog 内容，逐行判断是否应保留
  const changelogContent = readFileSync(changelogPath, 'utf-8')
  const lines = changelogContent.trim().split('\n')

  const tempDir = join(knowledgeDir, 'temp')
  const keptLines: string[] = []

  for (const line of lines) {
    // changelog 格式：timestamp|tool_name|file_path|preview
    const pipeIndex = line.indexOf('|')
    if (pipeIndex === -1) {
      // 无法解析的行保留，避免丢失数据
      keptLines.push(line)
      continue
    }

    const timestampStr = line.slice(0, pipeIndex)
    const entryTimestamp = new Date(timestampStr).getTime() / 1000

    if (isNaN(entryTimestamp)) {
      keptLines.push(line)
      continue
    }

    // 条目时间晚于 lastSummarizedCommit 时间 -> 保留（尚未被总结）
    if (entryTimestamp > summarizedTimestamp) {
      keptLines.push(line)
      continue
    }

    // 条目时间早于或等于 -> 尝试判断对应的 temp 文件是否已不存在
    // changelog 条目没有直接关联 commit hash，所以通过时间范围间接判断
    // 如果条目时间 <= lastSummarizedCommit 时间，且 lastSummarizedCommit 的
    // temp 文件已被 consolidate 清理，说明这些条目已被处理
    const tempFile = join(tempDir, `${state.lastSummarizedCommit}.md`)
    if (existsSync(tempFile)) {
      // temp 文件还在，说明 consolidate 尚未处理完毕，保留这些条目
      keptLines.push(line)
    }
    // temp 文件不存在 -> 条目已被处理，丢弃
  }

  // 只有实际有变化时才重写文件，避免无意义的 IO
  if (keptLines.length < lines.length) {
    const newContent = keptLines.join('\n') + (keptLines.length > 0 ? '\n' : '')
    writeFileSync(changelogPath, newContent, 'utf-8')
  }
}

// ======================== 主入口 ========================

async function main(): Promise<void> {
  const command = process.argv[2]

  switch (command) {
    case 'record': {
      const input = await readStdin()
      const projectRoot = getProjectRoot()
      await handleRecord(input, projectRoot)
      break
    }

    case 'process': {
      // process 子命令不需要读取 stdin 内容，但需要等待 stdin 关闭
      // 因为 Claude Code hook 会 pipe 数据到 stdin
      await readStdin()
      const projectRoot = getProjectRoot()
      await handleProcess(projectRoot)
      break
    }

    case 'inject-index': {
      const input = await readStdin()
      const projectRoot = getProjectRoot()
      handleInjectIndex(input, projectRoot)
      break
    }

    case 'cleanup': {
      const projectRoot = getProjectRoot()
      handleCleanup(projectRoot)
      break
    }

    default:
      // 未知命令静默退出
      break
  }
}

main().then(() => process.exit(0)).catch(() => process.exit(0))
