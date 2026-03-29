#!/bin/bash

# 读取 JSON 输入
input=$(cat)

# 提取模型显示名称
model=$(echo "$input" | jq -r '.model.display_name // "Unknown"')

# 提取上下文使用百分比
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
remaining=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')

# 构建输出
output="[$model"

if [ -n "$used" ]; then
    output="$output | 上下文: ${used}%"
fi

output="$output]"

# 提取当前目录（使用 basename 显示短路径）
cwd=$(echo "$input" | jq -r '.workspace.current_dir // empty')
if [ -n "$cwd" ]; then
    # 使用 basename 获取短路径名
    short_cwd=$(basename "$cwd")
    output="$output $short_cwd"
fi

echo "$output"
