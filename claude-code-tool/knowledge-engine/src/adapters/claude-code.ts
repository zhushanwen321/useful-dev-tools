import type { HookInput } from '../core/types.js'

/**
 * 解析 Claude Code hook 通过 stdin 传入的 JSON
 * Claude Code hook 的输入结构不固定，这里做容错处理
 * 返回 null 表示输入无效，调用方应静默跳过
 */
export function parseHookInput(input: string): HookInput | null {
  const trimmed = input.trim()
  if (!trimmed) return null

  try {
    const parsed = JSON.parse(trimmed) as Record<string, unknown>

    // Claude Code 的 hook JSON 结构可能变化，只要能解析就返回
    // 调用方（cli.ts）会根据具体子命令取需要的字段
    return {
      tool: typeof parsed.tool === 'string' ? parsed.tool : undefined,
      tool_input:
        parsed.tool_input && typeof parsed.tool_input === 'object'
          ? (parsed.tool_input as Record<string, any>)
          : undefined,
      cwd: typeof parsed.cwd === 'string' ? parsed.cwd : undefined,
      session_id: typeof parsed.session_id === 'string' ? parsed.session_id : undefined,
    }
  } catch {
    return null
  }
}
