#!/bin/bash
# cron 维护脚本：定期执行知识库的总结和清理
# 用法：添加到 crontab，例如每天 23:00 执行
# 0 23 * * * /path/to/knowledge-engine/scripts/cron-maintenance.sh

set -euo pipefail

# crontab 的 PATH 非常精简（通常只有 /usr/bin:/bin），
# 需要补充用户级工具路径（bun、qwen 等通过 npm/nvm 安装的工具在此）
export PATH="$HOME/.bun/bin:$HOME/.nvm/versions/node/$(ls "$HOME/.nvm/versions/node/" 2>/dev/null | tail -1)/bin:$PATH"

ENGINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ENGINE_DIR"

# 执行总结和沉淀
bun run src/cli.ts process

# 执行 changelog 清理
bun run src/cli.ts cleanup
