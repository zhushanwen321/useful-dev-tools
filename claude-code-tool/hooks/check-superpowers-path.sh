#!/bin/bash
# PostToolUse hook: 拦截 docs/superpowers 路径的写入，强制使用 .superpowers/ 目录
# 从 stdin 读取 JSON，提取 file_path 检查路径规范

set -euo pipefail

FILE_PATH=$(jq -r '.tool_input.file_path // .tool_response.filePath // empty' 2>/dev/null) || exit 0

[ -z "$FILE_PATH" ] && exit 0

case "$FILE_PATH" in
  *docs/superpowers*|*docs/.superpowers*)
    echo '{"systemMessage":"违反目录规范：文件路径包含 docs/superpowers 或 docs/.superpowers，应使用项目根目录的 .superpowers/ 目录。"}'
    ;;
esac
