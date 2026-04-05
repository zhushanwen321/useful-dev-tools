import { existsSync, mkdirSync, readFileSync } from 'node:fs'
import { join } from 'node:path'
import { homedir } from 'node:os'
import type { KnowledgeConfig } from './types.js'

// 知识库根目录
const KNOWLEDGE_BASE_DIR = join(homedir(), '.claude', 'knowledge')

// 默认配置：定义知识分类、沉淀阈值、文件排除规则
const DEFAULT_CONFIG: KnowledgeConfig = {
  categories: ['architecture', 'patterns', 'domain', 'troubleshooting'],
  consolidateThreshold: 3,
  excludePatterns: ['**/*.lock', '**/node_modules/**', '.env*'],
}

/**
 * 获取默认配置，不依赖任何文件系统读取
 */
export function getDefaultConfig(): KnowledgeConfig {
  return { ...DEFAULT_CONFIG }
}

/**
 * 获取项目级知识目录路径
 */
export function getKnowledgeDir(slug: string): string {
  return join(KNOWLEDGE_BASE_DIR, slug)
}

/**
 * 确保项目级知识目录存在（递归创建），返回路径
 */
export function ensureKnowledgeDir(slug: string): string {
  const dir = getKnowledgeDir(slug)

  if (!existsSync(dir)) {
    mkdirSync(dir, { recursive: true })
  }

  return dir
}

// 读取并解析 JSON 文件，文件不存在时返回 null
function readJsonFile<T>(filePath: string): T | null {
  if (!existsSync(filePath)) {
    return null
  }

  try {
    const content = readFileSync(filePath, 'utf-8')
    return JSON.parse(content) as T
  } catch {
    // JSON 解析失败时静默返回 null，使用上级配置兜底
    return null
  }
}

/**
 * 加载配置：项目级覆盖全局，最终回退到默认值
 * 合并策略：项目级配置中的字段覆盖全局配置中同名字段
 */
export function loadConfig(slug: string): KnowledgeConfig {
  const globalConfigPath = join(KNOWLEDGE_BASE_DIR, 'config.json')
  const projectConfigPath = join(getKnowledgeDir(slug), 'config.json')

  const globalConfig = readJsonFile<KnowledgeConfig>(globalConfigPath)
  const projectConfig = readJsonFile<KnowledgeConfig>(projectConfigPath)

  // 浅合并：默认 -> 全局 -> 项目级，后者覆盖前者
  return {
    ...DEFAULT_CONFIG,
    ...globalConfig,
    ...projectConfig,
  }
}
