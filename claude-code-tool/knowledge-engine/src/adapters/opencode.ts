/**
 * OpenCode Plugin 入口
 *
 * OpenCode 是一个类似 Claude Code 的终端 AI 编码助手，支持插件机制。
 * 其 Plugin 类型目前没有正式的 npm 包，因此这里使用 any 类型。
 * 当 OpenCode 发布正式类型定义后，应替换为具体的类型导入。
 *
 * 插件钩子说明：
 * - tool.execute.after: 文件写入/编辑操作完成后触发，用于记录变更
 * - session.end: 会话结束时触发，执行总结和沉淀
 * - session.start: 会话开始时触发，注入项目知识库索引到上下文
 */

import { record } from '../core/recorder.js'
import { summarize } from '../core/summarizer.js'
import { consolidate } from '../core/consolidator.js'
import { projectPathToSlug } from '../core/slug.js'
import { getKnowledgeDir } from '../core/config.js'
import { existsSync, readFileSync } from 'node:fs'
import { join } from 'node:path'

// OpenCode Plugin 类型定义（暂无官方包，用 any 兜底）
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type OpenCodeContext = any
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type OpenCodePlugin = any

/**
 * 读取指定 slug 的知识库索引文件内容
 * 同时读取 index.md 和 tag_index.md（如果存在）
 */
function readIndexContent(slug: string): string {
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

  return parts.join('\n\n')
}

export const KnowledgeEnginePlugin: OpenCodePlugin = async (ctx: OpenCodeContext) => {
  return {
    'tool.execute.after': async (input: any, output: any) => {
      // 只关注 Write 和 Edit 操作
      const toolName = input?.tool
      if (toolName !== 'Write' && toolName !== 'Edit') return

      record({
        tool_name: toolName,
        file_path: output?.args?.file_path ?? input?.tool_input?.file_path ?? '',
        content: output?.args?.content ?? input?.tool_input?.content,
        new_string: output?.args?.new_string ?? input?.tool_input?.new_string,
        old_string: output?.args?.old_string ?? input?.tool_input?.old_string,
        project_root: ctx.directory,
      })
    },

    'session.end': async () => {
      // 会话结束时串行执行总结和沉淀
      try {
        await summarize(ctx.directory)
        await consolidate(ctx.directory)
      } catch {
        // 内部错误不应阻止会话正常结束
      }
    },

    'session.start': async () => {
      // 会话开始时注入知识库索引到上下文
      const slug = projectPathToSlug(ctx.directory)
      const indexContent = readIndexContent(slug)

      if (!indexContent.trim()) return null

      return {
        additionalContext: indexContent,
      }
    },
  }
}
