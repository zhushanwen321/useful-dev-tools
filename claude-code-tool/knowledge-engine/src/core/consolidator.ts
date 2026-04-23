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
import { callClaude, isClaudeAvailable } from './ai.js'

// 并发锁标记文件超过此时间视为过期（10 分钟），防止异常退出后死锁
const LOCK_EXPIRE_MS = 10 * 60 * 1000

// 单次 consolidate 最多处理的 temp 文件数，防止 prompt 过大导致超时
const MAX_FILES_PER_CONSOLIDATE = 5

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

    // 质量门：raw 文件占比过高时跳过合并，避免产生低质量知识
    if (hasLowQualityTempFiles(tempDir, currentTempFiles)) {
      // 只清理已被标记为过期的 raw 文件，保留 summarized 文件等下次合并
      cleanupStaleRawFiles(tempDir, currentTempFiles)
      return
    }

    // 读取现有正式知识库结构
    const formalStructure = scanFormalStructure(formalDir)
    const existingFilesSummary = scanExistingFilesSummary(formalDir)

    if (isClaudeAvailable()) {
      // AI 路径：分批处理，防止 prompt 过大导致超时
      const batchFiles = currentTempFiles.slice(0, MAX_FILES_PER_CONSOLIDATE)
      const tempContents = readAllTempFiles(tempDir, batchFiles)
      const prompt = buildConsolidatePrompt(
        formalStructure,
        existingFilesSummary,
        tempContents,
        config.categories,
      )
      const rawOutput = await callClaude(prompt, { timeout: 180000 })
      const result = parseConsolidateResult(rawOutput)

      if (result) {
        executeOperations(formalDir, result.operations, config.categories, batchFiles)
      }
      // 只清理本批次处理的文件，剩余留给下次 consolidate
      generateAllIndexes(formalDir, config.categories)
      cleanupTempFiles(tempDir, batchFiles)
    } else {
      // AI 不可用时：只保留 summarized 的 temp 文件（下次再合并），清理 raw 文件
      const summarizedFiles: string[] = []
      for (const file of currentTempFiles) {
        const parsed = parseTempFile(join(tempDir, file))
        if (parsed && parsed.meta.status === 'summarized') {
          summarizedFiles.push(file)
        } else {
          // raw 文件直接清理，不再 1:1 复制到 formal
          try { unlinkSync(join(tempDir, file)) } catch { /* ignore */ }
        }
      }
      // summarized 文件保留在 temp 中，等下次 AI 可用时再合并
      void summarizedFiles
    }
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

// 质量门：检查 temp 文件中 raw 占比是否过高
// 全是 raw 说明 AI 一直不可用，合并只会产生低质量知识
function hasLowQualityTempFiles(tempDir: string, files: string[]): boolean {
  let rawCount = 0
  for (const file of files) {
    const parsed = parseTempFile(join(tempDir, file))
    if (parsed && parsed.meta.status === 'raw') rawCount++
  }
  // raw 占比超过 50% 就跳过合并
  return rawCount > files.length / 2
}

// 清理超过 7 天的 raw temp 文件，防止无限积累
function cleanupStaleRawFiles(tempDir: string, files: string[]): void {
  const SEVEN_DAYS_MS = 7 * 24 * 60 * 60 * 1000
  const now = Date.now()

  for (const file of files) {
    const filePath = join(tempDir, file)
    const parsed = parseTempFile(filePath)
    if (!parsed || parsed.meta.status !== 'raw') continue

    const fileTime = new Date(parsed.meta.timestamp).getTime()
    if (isNaN(fileTime)) continue

    if (now - fileTime > SEVEN_DAYS_MS) {
      try { unlinkSync(filePath) } catch { /* ignore */ }
    }
  }
}

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
- filename 使用小写字母、数字和连字符，.md 结尾，不要包含目录路径前缀`
}

// ======================== AI 响应解析 ========================

/**
 * 从可能包含 markdown 代码块、前导文字等噪声的文本中提取 JSON 对象
 *
 * 策略：找到第一个 { 后，通过花括号配对定位完整的 JSON 对象。
 * 这样即使 content 中包含 ``` 代码块也不会干扰提取。
 */
function extractJsonString(raw: string): string {
  const start = raw.indexOf('{')
  if (start === -1) return raw.trim()

  let depth = 0
  let inString = false
  let escape = false

  for (let i = start; i < raw.length; i++) {
    const ch = raw[i]

    if (escape) {
      escape = false
      continue
    }
    if (ch === '\\') {
      escape = true
      continue
    }
    if (ch === '"') {
      inString = !inString
      continue
    }
    if (inString) continue

    if (ch === '{') depth++
    else if (ch === '}') {
      depth--
      if (depth === 0) {
        return raw.substring(start, i + 1)
      }
    }
  }

  // 花括号未配对，回退到原始行为
  return raw.substring(start).trim()
}

/**
 * 解析 AI 返回的合并指令，容错处理各种异常格式
 *
 * 注意：不能用 ``` 代码块正则提取，因为 AI 返回的 JSON content 字段中
 * 可能包含 markdown 代码块（如 ```python），会干扰外层正则匹配。
 * 改用花括号配对来定位 JSON 对象边界。
 */
function parseConsolidateResult(raw: string): ConsolidateResult | null {
  const jsonStr = extractJsonString(raw)

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

    // 防御 AI 返回带路径前缀的 filename
    const filename = op.filename.split('/').pop() || op.filename
    const filePath = join(catDir, filename)
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
