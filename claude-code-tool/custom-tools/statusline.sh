#!/bin/bash

input=$(cat)

# --- 目录: 项目根名称 + 相对路径 ---
project_dir=$(echo "$input" | jq -r '.workspace.project_dir // empty')
current_dir=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')

dir_display=""
if [ -n "$project_dir" ] && [ -n "$current_dir" ]; then
    project_name=$(basename "$project_dir")
    if [ "$current_dir" = "$project_dir" ]; then
        dir_display="$project_name"
    else
        relative="${current_dir#$project_dir/}"
        if [ "$relative" = "$current_dir" ]; then
            dir_display=$(basename "$current_dir")
        else
            dir_display="$project_name/$relative"
        fi
    fi
elif [ -n "$current_dir" ]; then
    dir_display=$(basename "$current_dir")
fi

# --- 模型 ---
model=$(echo "$input" | jq -r '.model.display_name // "Unknown"')

# --- Context ---
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# used = output_tokens / (context_size - non_msg_context) * 100
# non_msg_context = context_size * used_percentage / 100 (当前上下文输入占用)
# 等价于: output_tokens / (context_size * remaining_percentage / 100) * 100
msg_used_pct=$(echo "$input" | jq -r '
  if .context_window.total_output_tokens != null
     and .context_window.context_window_size != null
     and .context_window.remaining_percentage != null
     and .context_window.remaining_percentage > 0
     and .context_window.total_output_tokens > 0 then
    (.context_window.total_output_tokens * 10000 / (.context_window.context_window_size * .context_window.remaining_percentage) | floor)
  else
    empty
  end
')

build_bar() {
    local pct=$1
    local filled=$((pct / 10))
    local empty=$((10 - filled))
    local bar=""
    for ((i = 0; i < filled; i++)); do bar+="█"; done
    for ((i = 0; i < empty; i++)); do bar+="░"; done
    echo "$bar"
}

# --- 组装: 目录 ▸ 模型 ▸ 上下文 ---
parts=()
[ -n "$dir_display" ] && parts+=("$dir_display")
[ -n "$model" ] && parts+=("$model")

if [ -n "$used_pct" ]; then
    bar=$(build_bar "$used_pct")
    ctx="$bar ${used_pct}%"
    if [ -n "$msg_used_pct" ]; then
        ctx="$ctx [ msg ▸ used ${msg_used_pct}% ]"
    fi
    parts+=("$ctx")
fi

output="${parts[0]}"
for part in "${parts[@]:1}"; do
    output="$output ▸ $part"
done

echo "$output"
