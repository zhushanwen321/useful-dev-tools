#!/bin/bash
# cron 维护脚本：定期执行所有项目的知识库总结、清理和修剪
# 用法：添加到 crontab，例如每天 23:00 执行
# 0 23 * * * /path/to/knowledge-engine/scripts/cron-maintenance.sh >> ~/.claude/knowledge/maintenance.log 2>&1

set -euo pipefail

# crontab 的 PATH 非常精简（通常只有 /usr/bin:/bin），
# 需要补充用户级工具路径（bun、claude 等通过 npm/nvm 安装的工具在此）
export PATH="$HOME/.bun/bin:$HOME/.nvm/versions/node/$(ls "$HOME/.nvm/versions/node/" 2>/dev/null | tail -1)/bin:$PATH"

ENGINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ENGINE_DIR"

LOG_FILE="$HOME/.claude/knowledge/maintenance.log"
mkdir -p "$(dirname "$LOG_FILE")"

# 日志轮转：超过 1MB 时截断保留最后 200 行，防止无限增长
if [ -f "$LOG_FILE" ]; then
  LOG_SIZE=$(stat -f%z "$LOG_FILE" 2>/dev/null || echo 0)
  if [ "$LOG_SIZE" -gt 1048576 ]; then
    tail -200 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
    echo "========== $(date '+%Y-%m-%d %H:%M:%S') 日志轮转（超过 1MB，保留最后 200 行） ==========" >> "$LOG_FILE"
  fi
fi

echo "========== $(date '+%Y-%m-%d %H:%M:%S') cron-maintenance 开始 ==========" >> "$LOG_FILE"

# 1. 遍历所有项目执行总结和沉淀
bun run src/cli.ts process-all >> "$LOG_FILE" 2>&1

# 2. 遍历所有项目执行 changelog 清理
bun run src/cli.ts cleanup-all >> "$LOG_FILE" 2>&1

# 3. 遍历所有项目执行知识库修剪（清理 SHA 条目、空洞条目、陈旧项目）
bun run src/cli.ts prune-all >> "$LOG_FILE" 2>&1

echo "========== $(date '+%Y-%m-%d %H:%M:%S') cron-maintenance 结束 ==========" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"
