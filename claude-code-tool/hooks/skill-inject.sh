#!/bin/bash
# skill-inject.sh - 入口脚本，调用 python 处理逻辑
# 通过 PreToolUse hook 拦截 Skill 工具调用

python3 "$(dirname "$0")/skill-inject.py"

exit 0
