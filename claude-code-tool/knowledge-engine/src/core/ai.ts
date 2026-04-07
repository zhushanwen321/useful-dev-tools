import { spawnSync } from 'node:child_process'

// qwen CLI 默认超时，summarize 等短 prompt 使用
const QWEN_TIMEOUT_DEFAULT = 30000
// consolidate 等长 prompt 需要更长超时
const QWEN_TIMEOUT_CONSOLIDATE = 120000

/**
 * 检测 qwen CLI 是否可用
 * 通过尝试获取版本号来判断，比 `which` 更可靠（能检测到权限问题等）
 */
export function isQwenAvailable(): boolean {
  const result = spawnSync('qwen', ['--version'], {
    timeout: 5000,
    encoding: 'utf-8',
    stdio: 'pipe',
  })

  return result.status === 0
}

/**
 * 调用 qwen CLI，将 prompt 通过 stdin 传入，返回 stdout 输出
 *
 * --approval-mode plan: 只允许规划，禁止执行任何工具调用（文件写入、命令执行等）
 * --output-format text: 只要纯文本输出，不要 json 包裹
 * --exclude-tools Write Edit Bash: 额外排除写入和执行类工具作为双保险
 */
export async function callQwen(prompt: string, options?: { timeout?: number }): Promise<string> {
  const timeout = options?.timeout ?? QWEN_TIMEOUT_DEFAULT
  const result = spawnSync('qwen', [
    '--approval-mode', 'plan',
    '--exclude-tools', 'Write', 'Edit', 'Bash', 'NotebookEdit',
    '--output-format', 'text',
  ], {
    input: prompt,
    timeout,
    encoding: 'utf-8',
    stdio: ['pipe', 'pipe', 'pipe'],
  })

  if (result.error) {
    throw new Error(`qwen 进程错误: ${result.error.message}`)
  }

  if (result.status !== 0) {
    const stderr = result.stderr?.trim() || '无错误输出'
    throw new Error(`qwen 执行失败 (exit ${result.status}): ${stderr}`)
  }

  return result.stdout.trim()
}
