import { spawnSync } from 'node:child_process'

// qwencode CLI 的超时时间，30 秒足够处理大部分知识总结任务
const QWENCODE_TIMEOUT = 30000

/**
 * 检测 qwencode CLI 是否可用
 * 通过尝试获取版本号来判断，比 `which` 更可靠（能检测到权限问题等）
 */
export function isQwenAvailable(): boolean {
  const result = spawnSync('qwencode', ['--version'], {
    timeout: 5000,
    encoding: 'utf-8',
    stdio: 'pipe',
  })

  return result.status === 0
}

/**
 * 调用 qwencode CLI，将 prompt 通过 stdin 传入，返回 stdout 输出
 * 使用 spawnSync 保证同步等待结果，适合在 hook 流程中调用
 *
 * 为什么用 stdin 传入 prompt 而非命令行参数：
 * - 避免 shell 转义问题（prompt 中可能包含特殊字符）
 * - 不受命令行长度限制
 */
export async function callQwen(prompt: string): Promise<string> {
  const result = spawnSync('qwencode', ['--headless'], {
    input: prompt,
    timeout: QWENCODE_TIMEOUT,
    encoding: 'utf-8',
    stdio: ['pipe', 'pipe', 'pipe'],
  })

  if (result.error) {
    // 进程级错误（如找不到 qwencode）
    throw new Error(`qwencode 进程错误: ${result.error.message}`)
  }

  if (result.status !== 0) {
    // qwencode 返回非零退出码
    const stderr = result.stderr?.trim() || '无错误输出'
    throw new Error(`qwencode 执行失败 (exit ${result.status}): ${stderr}`)
  }

  return result.stdout.trim()
}
