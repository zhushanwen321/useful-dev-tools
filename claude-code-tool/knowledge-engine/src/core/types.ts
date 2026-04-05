// 记录层输入：从 Claude Code hook 的 stdin 解析而来
export interface RecordInput {
  tool_name: string
  file_path: string
  content?: string
  new_string?: string
  old_string?: string
  project_root: string
}

// changelog 条目：每次文件变更的轻量记录
export interface ChangelogEntry {
  timestamp: string
  tool_name: string
  file_path: string
  change_preview: string
}

// 总结层输出：AI 对一批 changelog 的分析结果
export interface SummarizeResult {
  should_summarize: boolean
  topics: string[]
  summary: string
  key_decisions: string[]
  patterns: string[]
}

// 临时知识的 frontmatter 元数据
export interface TempKnowledgeMeta {
  name: string
  description: string
  tags: string[]
  commit: string
  timestamp: string
  topics: string[]
  status: 'summarized' | 'raw'
}

// 正式知识的 frontmatter 元数据，从临时知识沉淀而来
export interface FormalKnowledgeMeta {
  name: string
  description: string
  tags: string[]
  category: string
  created: string
  updated: string
  sources: string[]
}

// 沉淀层 AI 输出的单个操作指令
export interface ConsolidateOperation {
  action: 'create' | 'update' | 'merge'
  category: string
  filename: string
  name: string
  description: string
  tags: string[]
  content: string
}

// 沉淀层 AI 输出：对临时知识进行归类、合并、创建的指令集合
export interface ConsolidateResult {
  operations: ConsolidateOperation[]
}

// 状态文件：记录上次总结的 commit 和时间，避免重复处理
export interface StateFile {
  lastSummarizedCommit: string
  lastSummarizedTimestamp: string
}

// 配置：控制知识库的分类、沉淀阈值、排除规则
export interface KnowledgeConfig {
  categories: string[]
  consolidateThreshold: number
  excludePatterns: string[]
}

// Hook 输入：Claude Code 通过 stdin 传入的 JSON 结构
export interface HookInput {
  tool?: string
  tool_input?: Record<string, any>
  cwd?: string
  session_id?: string
}
