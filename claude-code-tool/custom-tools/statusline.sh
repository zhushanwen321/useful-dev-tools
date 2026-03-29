#!/bin/bash

input=$(cat)

# --- ANSI 颜色（必须在最前面定义） ---
R='\033[31m' G='\033[32m' Y='\033[33m' D='\033[0m'

# --- 进度条函数（文字嵌入中间，背景色填充） ---
# $1=百分比, $2=自定义文字（可选，默认 " 35%"）
build_bar() {
    local pct=$1
    local text="${2:-$(printf "%3d%%" "$pct")}"
    [ "$pct" -lt 0 ]  2>/dev/null && pct=0
    [ "$pct" -gt 100 ] 2>/dev/null && pct=100

    local text_len=${#text}
    local total=10
    local tstart=$(( (total - text_len) / 2 ))
    local filled=$((pct * total / 100))

    # 根据用量选填充背景色
    local fill_bg
    if [ "$pct" -ge 70 ]; then fill_bg='\033[41m'
    elif [ "$pct" -ge 40 ]; then fill_bg='\033[43m'
    else fill_bg='\033[42m'; fi
    local empty_bg='\033[100m'

    local bar="" ti=0
    for ((i = 0; i < total; i++)); do
        if (( i >= tstart && ti < text_len )); then
            local ch="${text:$ti:1}"; ((ti++))
            if (( i < filled )); then
                bar+="${fill_bg}\033[30m${ch}"
            else
                bar+="${empty_bg}\033[37m${ch}"
            fi
        elif (( i < filled )); then
            bar+="${fill_bg} "
        else
            bar+="${empty_bg} "
        fi
    done
    echo -e "${bar}${D}"
}

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

# --- Context (null 统一降级为 0, 保证始终展示) ---
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0')

# --- Load: 相对于可用窗口（扣除16%缓冲）的占用率 ---
BUFFER_PCT=16
load_pct=$(echo "$input" | jq -r --argjson buf "$BUFFER_PCT" '
  (.context_window.used_percentage // 0) as $used |
  (100 - $buf) as $usable |
  if $usable > 0 then
    [$used * 100 / $usable | floor, 100] | min
  else
    100
  end
')

# --- 智谱 API 用量（无缓存，每次实时查询） ---
get_zhipu_usage() {
    local auth_token=""
    if [ -f "$HOME/.claude/.zhipu_auth_token" ]; then
        auth_token=$(cat "$HOME/.claude/.zhipu_auth_token" 2>/dev/null)
    fi

    [ -z "$auth_token" ] && return

    curl -s --max-time 5 'https://bigmodel.cn/api/monitor/usage/quota/limit' \
        -H 'accept: application/json, text/plain, */*' \
        -H "authorization: ${auth_token}" \
        -H 'bigmodel-organization: org-8F82302F73594F44B2bdCc5A57BCfD1f' \
        -H 'bigmodel-project: proj_8E86D38C8211410Baa4852408071D1F2' \
        -H 'referer: https://bigmodel.cn/usercenter/glm-coding/usage' \
        -H 'user-agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36' 2>/dev/null
}

zhipu_data=$(get_zhipu_usage)
zhipu_line3=""

if echo "$zhipu_data" | jq -e '.success == true' >/dev/null 2>&1; then
    zhipu_level=$(echo "$zhipu_data" | jq -r '.data.level // ""')
    zhipu_items=()

    # TOKENS_LIMIT（优先展示）
    tokens_limit=$(echo "$zhipu_data" | jq -r '.data.limits[] | select(.type == "TOKENS_LIMIT")')
    if [ -n "$tokens_limit" ]; then
        tokens_pct=$(echo "$tokens_limit" | jq -r '.percentage // 0')
        tokens_bar=$(build_bar "$tokens_pct")
        zhipu_items+=("Token:${tokens_bar}")
    fi

    # TIME_LIMIT（MCP 用量）
    time_limit=$(echo "$zhipu_data" | jq -r '.data.limits[] | select(.type == "TIME_LIMIT")')
    if [ -n "$time_limit" ]; then
        time_pct=$(echo "$time_limit" | jq -r '.percentage // 0')
        time_current=$(echo "$time_limit" | jq -r '.currentValue // 0')
        mcp_text="${time_pct}%(${time_current})"
        time_bar=$(build_bar "$time_pct" "$mcp_text")
        zhipu_items+=("MCP:${time_bar}")
    fi

    # 组合智谱第三行
    if [ ${#zhipu_items[@]} -gt 0 ]; then
        zhipu_label="Z.ai CodingPlan"
        [ -n "$zhipu_level" ] && zhipu_label="Z.ai CodingPlan-${zhipu_level}"
        zhipu_combined="${zhipu_items[0]}"
        for item in "${zhipu_items[@]:1}"; do
            zhipu_combined="${zhipu_combined} ${item}"
        done
        zhipu_line3="${zhipu_label} ${zhipu_combined}"
    fi
fi

# --- 第一行: Project + Model ---
line1_parts=()
[ -n "$dir_display" ] && line1_parts+=("Project:${dir_display}")
[ -n "$model" ] && line1_parts+=("Model:${model}")

line1="${line1_parts[0]}"
for part in "${line1_parts[@]:1}"; do
    line1="$line1 ▸ $part"
done

# --- 第二行: Context + Load ---
ctx_bar=$(build_bar "$used_pct")
load_bar=$(build_bar "$load_pct")
line2="Context:${ctx_bar} ▸ Load:${load_bar}"

# --- 组合输出 ---
output="${line1}\n${line2}"
[ -n "$zhipu_line3" ] && output="${output}\n${zhipu_line3}"

echo -e "$output"
