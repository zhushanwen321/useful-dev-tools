import { spawnSync } from 'node:child_process'

// summarize 等短 prompt 默认超时
const CLAUDE_TIMEOUT_DEFAULT = 60000
// consolidate 等长 prompt 需要更长超时
const CLAUDE_TIMEOUT_CONSOLIDATE = 180000

// clode 的环境变量配置（对应 ~/.zsh/claude.zsh 中的 clode alias）
const CLAUDE_ENV = {
  ANTHROPIC_AUTH_TOKEN: 'sk-router-4c5823f4808c6614dd7f111ad9c96562cecb182560c3852f589fbd4461e58558',
  ANTHROPIC_BASE_URL: 'http://192.168.1.111:9981',
  ANTHROPIC_MODEL: 'glm-5',
  ANTHROPIC_DEFAULT_OPUS_MODEL: 'glm-5.1',
  ANTHROPIC_DEFAULT_SONNET_MODEL: 'glm-5',
  ANTHROPIC_DEFAULT_HAIKU_MODEL: 'glm-5-turbo',
  ANTHROPIC_SMALL_FAST_MODEL: 'glm-5-turbo',
}

/**
 * 检测 claude CLI 是否可用
 */
export function isClaudeAvailable(): boolean {
  const result = spawnSync('claude', ['--version'], {
    timeout: 5000,
    encoding: 'utf-8',
    stdio: 'pipe',
  })

  return result.status === 0
}

/** @deprecated 使用 isClaudeAvailable */
export const isQwenAvailable = isClaudeAvailable

/**
 * 调用 claude CLI 无头模式，将 prompt 作为参数传入，返回 stdout 输出
 *
 * -p: 无头模式，输出结果后退出
 * --output-format text: 只要纯文本输出
 * --dangerously-skip-permissions: 跳过交互式权限确认（cron 环境需要）
 */
export async function callClaude(prompt: string, options?: { timeout?: number }): Promise<string> {
  const timeout = options?.timeout ?? CLAUDE_TIMEOUT_DEFAULT
  const result = spawnSync('claude', [
    '-p', prompt,
    '--output-format', 'text',
    '--dangerously-skip-permissions',
  ], {
    timeout,
    encoding: 'utf-8',
    stdio: ['pipe', 'pipe', 'pipe'],
    env: { ...process.env, ...CLAUDE_ENV },
  })

  if (result.error) {
    throw new Error(`claude 进程错误: ${result.error.message}`)
  }

  if (result.status !== 0) {
    const stderr = result.stderr?.trim() || '无错误输出'
    throw new Error(`claude 执行失败 (exit ${result.status}): ${stderr}`)
  }

  return result.stdout.trim()
}

/** @deprecated 使用 callClaude */
export const callQwen = callClaude
