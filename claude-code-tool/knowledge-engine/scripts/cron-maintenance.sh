#!/bin/bash
# cron 维护脚本：定期执行知识库的总结和清理
# 用法：添加到 crontab，例如每 30 分钟执行一次
# */30 * * * * /path/to/knowledge-engine/scripts/cron-maintenance.sh

set -euo pipefail

ENGINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ENGINE_DIR"

# 执行总结和沉淀
bun run src/cli.ts process

# 执行 changelog 清理
bun run src/cli.ts cleanup
