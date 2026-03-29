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

# load = 已用空间 / 可用空间(扣除 autocompact buffer) * 100
# 当 load = 100% 时 autocompact 触发
# total_output_tokens 是累计计数器(压缩后不减少), 不能用于当前上下文计算
BUFFER_PCT=16
load_pct=$(echo "$input" | jq -r --argjson buf "$BUFFER_PCT" '
  if .context_window.used_percentage != null then
    (100 - $buf) as $usable |
    if $usable > 0 then
      [.context_window.used_percentage * 100 / $usable | floor, 100] | min
    else
      100
    end
  else
    empty
  end
')

# --- ANSI 颜色 ---
R='\033[31m' G='\033[32m' Y='\033[33m' D='\033[0m'

build_bar() {
    local pct=$1 color=$2
    [ "$pct" -lt 0 ] 2>/dev/null && pct=0
    [ "$pct" -gt 100 ] 2>/dev/null && pct=100
    local filled=$((pct / 10))
    local empty=$((10 - filled))
    local bar=""
    for ((i = 0; i < filled; i++)); do bar+="█"; done
    for ((i = 0; i < empty; i++)); do  bar+="░"; done
    echo -e "${color}${bar}${D}"
}

pick_ctx_color() {
    [ "$1" -ge 70 ] 2>/dev/null && echo "$R" || echo "$G"
}

pick_load_color() {
    local p=$1
    [ "$p" -ge 70 ] 2>/dev/null && { echo "$R"; return; }
    [ "$p" -le 30 ] 2>/dev/null && { echo "$G"; return; }
    echo "$Y"
}

# --- 组装: 目录 ▸ 模型 ▸ 上下文 ---
parts=()
[ -n "$dir_display" ] && parts+=("$dir_display")
[ -n "$model" ] && parts+=("$model")

if [ -n "$used_pct" ]; then
    ctx_color=$(pick_ctx_color "$used_pct")
    bar=$(build_bar "$used_pct" "$ctx_color")
    ctx="${bar} ${ctx_color}${used_pct}%${D}"

    if [ -n "$load_pct" ]; then
        load_color=$(pick_load_color "$load_pct")
        load_bar=$(build_bar "$load_pct" "$load_color")
        ctx="${ctx} [ load ${load_bar} ${load_color}${load_pct}%${D} ]"
    fi
    parts+=("$ctx")
fi

output="${parts[0]}"
for part in "${parts[@]:1}"; do
    output="$output ▸ $part"
done

echo -e "$output"
