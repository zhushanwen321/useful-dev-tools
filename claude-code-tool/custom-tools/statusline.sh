#!/bin/bash
# Claude Code Statusline — 入口脚本
# 所有数据处理逻辑已迁移到 statusline_core.py（Python 标准库，零依赖）
# bash 只做 stdin 透传

# 解析 symlink 的真实路径（$0 可能是 ~/.claude/custom-tools/statusline.sh -> 实际脚本）
REAL_PATH="$(readlink -f "$0" 2>/dev/null || readlink "$0" 2>/dev/null || echo "$0")"
SCRIPT_DIR="$(cd "$(dirname "$REAL_PATH")" && pwd)"
exec python3 "$SCRIPT_DIR/statusline_core.py"
