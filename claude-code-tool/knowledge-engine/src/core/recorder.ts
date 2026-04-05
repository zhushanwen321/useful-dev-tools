import { appendFileSync } from 'node:fs'
import { join } from 'node:path'
import { homedir } from 'node:os'
import type { RecordInput } from './types.js'
import { projectPathToSlug } from './slug.js'
import { loadConfig, ensureKnowledgeDir } from './config.js'

// changelog 每行记录的最大预览长度，避免单条记录过大
const PREVIEW_MAX_LENGTH = 200

// 知识库根目录，用于自引用防护
const KNOWLEDGE_BASE_DIR = join(homedir(), '.claude', 'knowledge')

/**
 * 将简单的 glob 模式转换为正则表达式
 * 只处理 excludePatterns 中实际出现的模式类型：**、*、?
 * 不追求完整的 glob 规范兼容，够用即可
 */
function globToRegex(pattern: string): RegExp {
  const escaped = pattern
    .replace(/[.+^${}()|[\]\\]/g, '\\$&')
    .replace(/\*\*/g, '{{GLOBSTAR}}')
    .replace(/\*/g, '[^/]*')
    .replace(/\?/g, '[^/]')
    .replace(/\{\{GLOBSTAR\}\}/g, '.*')

  return new RegExp(`(^|/)${escaped}(/|$)`)
}

/**
 * 检查文件路径是否匹配任一排除模式
 */
function isExcluded(filePath: string, patterns: string[]): boolean {
  return patterns.some((pattern) => {
    try {
      return globToRegex(pattern).test(filePath)
    } catch {
      return false
    }
  })
}

/**
 * 检查是否为纯空白变更（去掉所有空白字符后新旧内容相同）
 * 用于过滤无意义的格式调整触发记录
 */
function isWhitespaceOnlyChange(newStr?: string, oldStr?: string): boolean {
  if (newStr === undefined || oldStr === undefined) {
    return false
  }
  return newStr.replace(/\s+/g, '') === oldStr.replace(/\s+/g, '')
}

/**
 * 提取变更预览文本，Write 取 content，Edit 取 new_string
 */
function extractPreview(input: RecordInput): string {
  const raw = input.content ?? input.new_string ?? ''
  // 去掉换行，压缩成单行，方便后续日志解析
  const flattened = raw.replace(/\n/g, ' ').trim()
  return flattened.length > PREVIEW_MAX_LENGTH
    ? flattened.slice(0, PREVIEW_MAX_LENGTH) + '...'
    : flattened
}

/**
 * 记录一次文件变更到 changelog.log
 *
 * 设计为同步函数：追加操作本身在微秒级完成，
 * 同步写入保证数据持久性，且避免 hook 调用方需要 await
 */
export function record(input: RecordInput): void {
  const { file_path, project_root } = input

  // 自引用防护：不记录知识库内部文件的操作，避免循环污染
  if (file_path.startsWith(KNOWLEDGE_BASE_DIR)) {
    return
  }

  // 加载项目配置，获取排除规则
  const slug = projectPathToSlug(project_root)
  const config = loadConfig(slug)

  // 排除匹配配置规则的文件
  if (isExcluded(file_path, config.excludePatterns)) {
    return
  }

  // 过滤纯空白变更，这类改动不产生语义信息
  if (isWhitespaceOnlyChange(input.new_string, input.old_string)) {
    return
  }

  // 确保知识目录存在
  const dir = ensureKnowledgeDir(slug)
  const changelogPath = join(dir, 'changelog.log')

  // 拼接日志行：timestamp|tool_name|file_path|change_preview
  const timestamp = new Date().toISOString()
  const preview = extractPreview(input)
  const entry = `${timestamp}|${input.tool_name}|${file_path}|${preview}\n`

  // 追加写入，appendFileSync 对单行追加操作足够快（< 1ms）
  appendFileSync(changelogPath, entry, 'utf-8')
}
