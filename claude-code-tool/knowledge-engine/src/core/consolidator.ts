import {
  existsSync,
  readdirSync,
  readFileSync,
  writeFileSync,
  renameSync,
  unlinkSync,
  mkdirSync,
  openSync,
  closeSync,
  statSync,
} from 'node:fs'
import { join } from 'node:path'
import type {
  ConsolidateOperation,
  ConsolidateResult,
  FormalKnowledgeMeta,
  TempKnowledgeMeta,
} from './types.js'
import { projectPathToSlug, findProjectRoot } from './slug.js'
import { loadConfig, ensureKnowledgeDir } from './config.js'
import { callQwen, isQwenAvailable } from './ai.js'

// 并发锁标记文件超过此时间视为过期（10 分钟），防止异常退出后死锁
const LOCK_EXPIRE_MS = 10 * 60 * 1000

// 索引文件排除列表，避免把索引本身编入索引
const INDEX_FILES = new Set(['index.md', 'tag_index.md'])

// ======================== 主入口 ========================

/**
 * 沉淀层主入口：将临时知识合并到正式知识库并生成索引
 *
 * 流程：检查阈值 -> 加锁 -> 读取现有结构 -> AI 合并 -> 写入 formal -> 生成索引 -> 清理 temp -> 解锁
 * 并发安全：通过 temp/.consolidating 原子文件实现跨进程互斥
 */
export async function consolidate(projectRoot: string): Promise<void> {
  // 非 git 项目不处理
  const gitRoot = findProjectRoot(projectRoot)
  if (!gitRoot) return

  const slug = projectPathToSlug(gitRoot)
  const knowledgeDir = ensureKnowledgeDir(slug)
  const config = loadConfig(slug)
  const tempDir = join(knowledgeDir, 'temp')
  const formalDir = join(knowledgeDir, 'formal')
  const lockPath = join(tempDir, '.consolidating')

  // 确保 temp 和 formal 目录存在
  ensureDir(tempDir)
  ensureDir(formalDir)

  // 未达阈值则静默退出，避免频繁触发无意义的合并
  const tempFiles = getTempFiles(tempDir)
  if (tempFiles.length < config.consolidateThreshold) return

  // 尝试获取并发锁，失败说明另一个进程正在执行
  if (!acquireLock(lockPath)) return

  try {
    // 重新读取 temp 文件列表，因为获取锁期间可能有变化
    const currentTempFiles = getTempFiles(tempDir)
    if (currentTempFiles.length === 0) return

    // 读取现有正式知识库结构
    const formalStructure = scanFormalStructure(formalDir)
    const existingFilesSummary = scanExistingFilesSummary(formalDir)

    if (isQwenAvailable()) {
      // AI 路径：让 AI 决定如何归类和合并
      const tempContents = readAllTempFiles(tempDir, currentTempFiles)
      const prompt = buildConsolidatePrompt(
        formalStructure,
        existingFilesSummary,
        tempContents,
        config.categories,
      )
      const rawOutput = await callQwen(prompt)
      const result = parseConsolidateResult(rawOutput)

      if (result) {
        executeOperations(formalDir, result.operations, config.categories, currentTempFiles)
      }
    } else {
      // 降级路径：按 topics 字段做简单目录归类，不执行合并
      fallbackClassify(tempDir, formalDir, currentTempFiles, config.categories)
    }

    // 索引生成是纯本地的，不依赖 AI
    generateAllIndexes(formalDir, config.categories)

    // 清理已处理的临时知识文件
    cleanupTempFiles(tempDir, currentTempFiles)
  } finally {
    // 无论成功失败都必须释放锁
    releaseLock(lockPath)
  }
}

// ======================== 并发锁 ========================

/**
 * 原子创建锁文件实现跨进程互斥
 * O_EXCL 保证只有第一个创建者成功，失败则说明另一个进程正在执行
 */
function acquireLock(lockPath: string): boolean {
  try {
    const fd = openSync(lockPath, 'w') // 默认 O_WRONLY | O_CREAT | O_EXCL
    closeSync(fd)
    return true
  } catch {
    // 创建失败，检查锁文件是否过期（异常退出导致死锁）
    try {
      if (existsSync(lockPath)) {
        const stat = statSync(lockPath)
        const age = Date.now() - stat.mtimeMs
        if (age > LOCK_EXPIRE_MS) {
          // 过期锁强制删除后重新获取
          unlinkSync(lockPath)
          const fd = openSync(lockPath, 'w')
          closeSync(fd)
          return true
        }
      }
    } catch {
      // 锁文件操作异常，放弃本次执行
    }
    return false
  }
}

function releaseLock(lockPath: string): void {
  try {
    if (existsSync(lockPath)) {
      unlinkSync(lockPath)
    }
  } catch {
    // 删除锁文件失败不影响主流程
  }
}

// ======================== 文件扫描 ========================

/**
 * 获取 temp 目录下所有 .md 文件（排除标记文件）
 */
function getTempFiles(tempDir: string): string[] {
  if (!existsSync(tempDir)) return []

  try {
    return readdirSync(tempDir)
      .filter((f) => f.endsWith('.md'))
      .sort()
  } catch {
    return []
  }
}

/**
 * 扫描 formal 目录结构，生成树形文本供 AI 理解现有组织方式
 */
function scanFormalStructure(formalDir: string): string {
  if (!existsSync(formalDir)) return '（空，尚无正式知识）'

  const lines: string[] = []
  const categories = readdirSync(formalDir, { withFileTypes: true })
    .filter((d) => d.isDirectory())
    .map((d) => d.name)
    .sort()

  for (const cat of categories) {
    const catDir = join(formalDir, cat)
    const files = readdirSync(catDir).filter((f) => f.endsWith('.md') && !INDEX_FILES.has(f))
    lines.push(`${cat}/`)
    for (const file of files) {
      lines.push(`  ${file}`)
    }
  }

  return lines.length > 0 ? lines.join('\n') : '（空，尚无正式知识）'
}

/**
 * 读取所有正式知识文件的 name + description，供 AI 理解已有内容避免重复
 */
function scanExistingFilesSummary(formalDir: string): string {
  if (!existsSync(formalDir)) return '（无）'

  const entries: string[] = []

  for (const cat of readdirSync(formalDir, { withFileTypes: true })) {
    if (!cat.isDirectory()) continue
    const catDir = join(formalDir, cat.name)

    for (const file of readdirSync(catDir)) {
      if (!file.endsWith('.md') || INDEX_FILES.has(file)) continue
      const meta = parseFormalMeta(join(catDir, file))
      if (meta) {
        entries.push(`- [${meta.name}](${cat.name}/${file}) — ${meta.description}`)
      }
    }
  }

  return entries.length > 0 ? entries.join('\n') : '（无）'
}

// ======================== 临时文件读取 ========================

interface TempFileData {
  filename: string
  meta: TempKnowledgeMeta
  body: string
}

/**
 * 读取所有临时知识文件的 frontmatter 和内容
 */
function readAllTempFiles(tempDir: string, files: string[]): TempFileData[] {
  return files
    .map((filename) => {
      const filePath = join(tempDir, filename)
      const parsed = parseTempFile(filePath)
      if (!parsed) return null
      return { filename, meta: parsed.meta, body: parsed.body }
    })
    .filter((d): d is TempFileData => d !== null)
}

// ======================== AI Prompt ========================

/**
 * 构建沉淀层的 AI prompt，包含现有结构、已有文件摘要和临时知识内容
 */
function buildConsolidatePrompt(
  formalStructure: string,
  existingFilesSummary: string,
  tempFiles: TempFileData[],
  categories: string[],
): string {
  const tempContents = tempFiles
    .map(
      (f) => `### ${f.meta.name}
**文件**: ${f.filename}
**标签**: ${f.meta.tags.join(', ')}
**状态**: ${f.meta.status}

${f.body}`,
    )
    .join('\n\n---\n\n')

  return `你是一个知识整合器。将以下临时知识合并到现有知识库中。

## 现有目录结构
${formalStructure}

## 现有知识文件索引（name + description）
${existingFilesSummary}

## 临时知识文件
${tempContents}

## 输出要求
直接输出 JSON，不要执行任何文件操作（创建、修改、删除文件）。所有合并动作由外部程序根据你的 JSON 输出执行。
返回 JSON：
{
  "operations": [
    {
      "action": "create|update|merge",
      "category": "分类",
      "filename": "文件名.md",
      "name": "简短标识名",
      "description": "一句话描述（用于索引生成）",
      "tags": ["tag1", "tag2"],
      "content": "完整 markdown 内容"
    }
  ]
}

规则：
- category 只能使用以下值: ${categories.join(', ')}，不能创建新分类
- merge 操作将多个临时知识合并到已有文件
- update 操作更新已有文件内容
- create 操作创建新文件
- 每个文件的 content 应包含完整的知识内容，不要省略
- filename 使用小写字母、数字和连字符，.md 结尾`
}

// ======================== AI 响应解析 ========================

/**
 * 解析 AI 返回的合并指令，容错处理各种异常格式
 */
function parseConsolidateResult(raw: string): ConsolidateResult | null {
  // AI 经常会在 JSON 外包裹 markdown 代码块
  const jsonMatch = raw.match(/```(?:json)?\s*([\s\S]*?)```/) || [null, raw]
  const jsonStr = (jsonMatch[1] || raw).trim()

  try {
    const parsed = JSON.parse(jsonStr)
    if (!Array.isArray(parsed.operations)) return null

    // 校验每个 operation 的必要字段
    const validOps = (parsed.operations as unknown[])
      .filter((op): op is ConsolidateOperation => {
        if (typeof op !== 'object' || op === null) return false
        const o = op as Record<string, unknown>
        return (
          typeof o.action === 'string' &&
          ['create', 'update', 'merge'].includes(o.action) &&
          typeof o.category === 'string' &&
          typeof o.filename === 'string' &&
          typeof o.name === 'string' &&
          typeof o.description === 'string' &&
          Array.isArray(o.tags) &&
          typeof o.content === 'string'
        )
      })

    return { operations: validOps }
  } catch {
    return null
  }
}

// ======================== 文件操作执行 ========================

/**
 * 执行 AI 输出的合并操作到 formal 目录
 */
function executeOperations(
  formalDir: string,
  operations: ConsolidateOperation[],
  validCategories: string[],
  tempFilenames: string[],
): void {
  for (const op of operations) {
    // 校验 category，未知分类归入第一个默认分类
    let category = op.category
    let originalCategory: string | undefined

    if (!validCategories.includes(category)) {
      originalCategory = category
      category = validCategories[0]
    }

    const catDir = join(formalDir, category)
    ensureDir(catDir)

    const filePath = join(catDir, op.filename)
    const now = new Date().toISOString()

    if (op.action === 'create') {
      writeFormalKnowledge(filePath, {
        name: op.name,
        description: op.description,
        tags: op.tags,
        category,
        created: now,
        updated: now,
        sources: tempFilenames,
        ...(originalCategory ? { original_category: originalCategory } : {}),
      }, op.content)
    } else if (op.action === 'update' || op.action === 'merge') {
      // update/merge：保留原有 created 和 sources，追加新 sources
      const existingMeta = parseFormalMeta(filePath)
      const mergedSources = existingMeta
        ? [...new Set([...existingMeta.sources, ...tempFilenames])]
        : tempFilenames

      writeFormalKnowledge(filePath, {
        name: op.name,
        description: op.description,
        tags: op.tags,
        category,
        created: existingMeta?.created || now,
        updated: now,
        sources: mergedSources,
        ...(originalCategory ? { original_category: originalCategory } : {}),
      }, op.content)
    }
  }
}

// ======================== 降级路径 ========================

/**
 * 无 AI 时按 topics 字段做简单目录归类
 * 规则匹配：topics 中包含已知 category 名则归入，否则归入第一个 category
 */
function fallbackClassify(
  tempDir: string,
  formalDir: string,
  tempFiles: string[],
  categories: string[],
): void {
  for (const filename of tempFiles) {
    const filePath = join(tempDir, filename)
    const parsed = parseTempFile(filePath)
    if (!parsed) continue
    const { meta, body } = parsed

    // 尝试从 topics 中匹配已知分类
    const matchedCategory =
      categories.find((cat) => meta.topics.some((topic: string) => topic.toLowerCase().includes(cat.toLowerCase()))) ||
      categories[0]

    const catDir = join(formalDir, matchedCategory)
    ensureDir(catDir)

    const now = new Date().toISOString()
    writeFormalKnowledge(join(catDir, filename), {
      name: meta.name,
      description: meta.description,
      tags: meta.tags,
      category: matchedCategory,
      created: now,
      updated: now,
      sources: [filename],
    }, body)
  }
}

// ======================== 索引生成 ========================

/**
 * 扫描所有正式知识文件并生成三类索引
 * 索引是纯文件扫描操作，不依赖 AI，每次 consolidate 都全量重建
 */
function generateAllIndexes(formalDir: string, categories: string[]): void {
  // 收集所有知识文件的元数据
  const allEntries: Array<{
    category: string
    filename: string
    relativePath: string
    meta: FormalKnowledgeMeta
  }> = []

  for (const cat of readdirSync(formalDir, { withFileTypes: true })) {
    if (!cat.isDirectory()) continue
    const catDir = join(formalDir, cat.name)

    for (const file of readdirSync(catDir)) {
      if (!file.endsWith('.md') || INDEX_FILES.has(file)) continue
      const filePath = join(catDir, file)
      const meta = parseFormalMeta(filePath)
      if (meta) {
        allEntries.push({
          category: cat.name,
          filename: file,
          relativePath: `${cat.name}/${file}`,
          meta,
        })
      }
    }
  }

  const now = new Date().toISOString().split('T')[0]

  // 生成按 category 分层的主索引
  generateMainIndex(formalDir, allEntries, now)

  // 生成按 tag 交叉索引的标签索引
  generateTagIndex(formalDir, allEntries, now)

  // 生成每个分类目录下的分类索引
  for (const cat of categories) {
    const catDir = join(formalDir, cat)
    if (!existsSync(catDir)) continue
    const catEntries = allEntries.filter((e) => e.category === cat)
    generateCategoryIndex(catDir, cat, catEntries, now)
  }
}

/**
 * 生成 formal/index.md：按 category 分层列出所有知识文件
 */
function generateMainIndex(
  formalDir: string,
  entries: Array<{ category: string; relativePath: string; meta: FormalKnowledgeMeta }>,
  date: string,
): void {
  const lines = ['# 项目知识库索引', '']

  // 按 category 分组
  const grouped = new Map<string, typeof entries>()
  for (const entry of entries) {
    const list = grouped.get(entry.category) || []
    list.push(entry)
    grouped.set(entry.category, list)
  }

  for (const [category, catEntries] of grouped) {
    lines.push(`## ${category}`)
    for (const entry of catEntries) {
      lines.push(`- [${entry.meta.name}](${entry.relativePath}) — ${entry.meta.description}`)
    }
    lines.push('')
  }

  lines.push(`---`)
  lines.push(`最近更新：${date} | 文档数：${entries.length}`)

  atomicWrite(join(formalDir, 'index.md'), lines.join('\n') + '\n')
}

/**
 * 生成 formal/tag_index.md：按 tag 交叉索引
 */
function generateTagIndex(
  formalDir: string,
  entries: Array<{ relativePath: string; meta: FormalKnowledgeMeta }>,
  date: string,
): void {
  // 按 tag 聚合
  const tagMap = new Map<string, typeof entries>()
  for (const entry of entries) {
    for (const tag of entry.meta.tags) {
      const list = tagMap.get(tag) || []
      list.push(entry)
      tagMap.set(tag, list)
    }
  }

  const lines = ['# 标签索引', '']

  for (const [tag, tagEntries] of tagMap) {
    lines.push(`## ${tag}`)
    for (const entry of tagEntries) {
      lines.push(`- [${entry.meta.name}](${entry.relativePath}) — ${entry.meta.description}`)
    }
    lines.push('')
  }

  const uniqueTags = tagMap.size
  lines.push(`---`)
  lines.push(`最近更新：${date} | 标签数：${uniqueTags} | 文档数：${entries.length}`)

  atomicWrite(join(formalDir, 'tag_index.md'), lines.join('\n') + '\n')
}

/**
 * 生成 category/index.md：单个分类下的知识文件索引
 */
function generateCategoryIndex(
  catDir: string,
  categoryName: string,
  entries: Array<{ relativePath: string; meta: FormalKnowledgeMeta }>,
  date: string,
): void {
  const lines = [`# ${categoryName}`, '']

  for (const entry of entries) {
    // 分类索引中使用相对于分类目录的路径
    const filename = entry.relativePath.split('/').pop() || entry.relativePath
    lines.push(`- [${entry.meta.name}](${filename}) — ${entry.meta.description}`)
  }

  if (entries.length > 0) {
    lines.push('')
    lines.push(`---`)
    lines.push(`最近更新：${date} | 文档数：${entries.length}`)
  }

  atomicWrite(join(catDir, 'index.md'), lines.join('\n') + '\n')
}

// ======================== Frontmatter 解析 ========================

/**
 * 解析临时知识文件的 frontmatter 和 body
 * frontmatter 格式：--- 开头结尾的 YAML 块
 */
function parseTempFile(filePath: string): { meta: TempKnowledgeMeta; body: string } | null {
  try {
    const content = readFileSync(filePath, 'utf-8')
    const match = content.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/)

    if (!match) return null

    const yamlStr = match[1]
    const body = match[2].trim()

    // 简单 YAML 解析，只处理项目实际使用的字段类型
    const meta: Record<string, unknown> = {}
    for (const line of yamlStr.split('\n')) {
      const arrayMatch = line.match(/^(\w+):\s*\[(.+)\]$/)
      if (arrayMatch) {
        // 数组字段：tags, topics
        meta[arrayMatch[1]] = arrayMatch[2]
          .split(',')
          .map((v) => v.trim().replace(/^"|"$/g, ''))
          .filter(Boolean)
      } else {
        const kvMatch = line.match(/^(\w+):\s*"?(.+?)"?\s*$/)
        if (kvMatch) {
          meta[kvMatch[1]] = kvMatch[2]
        }
      }
    }

    return {
      meta: {
        name: String(meta.name || ''),
        description: String(meta.description || ''),
        tags: Array.isArray(meta.tags) ? meta.tags : [],
        commit: String(meta.commit || ''),
        timestamp: String(meta.timestamp || ''),
        topics: Array.isArray(meta.topics) ? meta.topics : [],
        status: (meta.status === 'summarized' ? 'summarized' : 'raw'),
      },
      body,
    }
  } catch {
    return null
  }
}

/**
 * 解析正式知识文件的 frontmatter
 */
function parseFormalMeta(filePath: string): FormalKnowledgeMeta | null {
  try {
    const content = readFileSync(filePath, 'utf-8')
    const match = content.match(/^---\n([\s\S]*?)\n---\n/)

    if (!match) return null

    const yamlStr = match[1]
    const meta: Record<string, unknown> = {}

    for (const line of yamlStr.split('\n')) {
      const arrayMatch = line.match(/^(\w+):\s*\[(.+)\]$/)
      if (arrayMatch) {
        meta[arrayMatch[1]] = arrayMatch[2]
          .split(',')
          .map((v) => v.trim().replace(/^"|"$/g, ''))
          .filter(Boolean)
      } else {
        const kvMatch = line.match(/^(\w+):\s*"?(.+?)"?\s*$/)
        if (kvMatch) {
          meta[kvMatch[1]] = kvMatch[2]
        }
      }
    }

    return {
      name: String(meta.name || ''),
      description: String(meta.description || ''),
      tags: Array.isArray(meta.tags) ? meta.tags : [],
      category: String(meta.category || ''),
      created: String(meta.created || ''),
      updated: String(meta.updated || ''),
      sources: Array.isArray(meta.sources) ? meta.sources : [],
    }
  } catch {
    return null
  }
}

// ======================== 文件写入 ========================

/**
 * 写入正式知识文件，包含完整的 frontmatter
 * 额外字段（如 original_category）通过 extraFields 传入
 */
function writeFormalKnowledge(
  filePath: string,
  meta: FormalKnowledgeMeta & Record<string, unknown>,
  body: string,
): void {
  const frontmatter = Object.entries(meta)
    .map(([key, value]) => {
      if (Array.isArray(value)) {
        return `${key}: [${value.map((v) => `"${v}"`).join(', ')}]`
      }
      return `${key}: "${String(value).replace(/"/g, '\\"')}"`
    })
    .join('\n')

  const content = `---\n${frontmatter}\n---\n\n${body}\n`
  atomicWrite(filePath, content)
}

/**
 * 原子写入文件：先写 .tmp 再 rename，避免中途失败导致文件损坏
 */
function atomicWrite(filePath: string, content: string): void {
  const tmpPath = filePath + '.tmp'
  writeFileSync(tmpPath, content, 'utf-8')
  renameSync(tmpPath, filePath)
}

/**
 * 确保目录存在
 */
function ensureDir(dir: string): void {
  if (!existsSync(dir)) {
    mkdirSync(dir, { recursive: true })
  }
}

// ======================== 清理 ========================

/**
 * 清理已处理的临时知识文件
 */
function cleanupTempFiles(tempDir: string, files: string[]): void {
  for (const file of files) {
    try {
      const filePath = join(tempDir, file)
      if (existsSync(filePath)) {
        unlinkSync(filePath)
      }
    } catch {
      // 单个文件删除失败不影响整体流程
    }
  }
}
