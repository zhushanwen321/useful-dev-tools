/**
 * Claude CLI 配置
 */

// summarize 等短 prompt 默认超时
export const CLAUDE_TIMEOUT_DEFAULT = 60000

// consolidate 等长 prompt 需要更长超时
export const CLAUDE_TIMEOUT_CONSOLIDATE = 180000

// claude 的环境变量配置（对应 ~/.zsh/claude.zsh 中的 clode alias）
export const CLAUDE_ENV = {
  ANTHROPIC_AUTH_TOKEN: 'sk-router-4c5823f4808c6614dd7f111ad9c96562cecb182560c3852f589fbd4461e58558',
  ANTHROPIC_BASE_URL: 'http://192.168.1.111:9981',
  ANTHROPIC_MODEL: 'glm-5',
  ANTHROPIC_DEFAULT_OPUS_MODEL: 'glm-5.1',
  ANTHROPIC_DEFAULT_SONNET_MODEL: 'glm-5',
  ANTHROPIC_DEFAULT_HAIKU_MODEL: 'glm-5-turbo',
  ANTHROPIC_SMALL_FAST_MODEL: 'glm-5-turbo',
}
