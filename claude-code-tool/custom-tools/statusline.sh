#!/bin/bash

input=$(cat)

# --- ANSI 颜色（必须在最前面定义） ---
R='\033[31m' G='\033[32m' Y='\033[33m' D='\033[0m'

# --- 进度条函数 ---
build_bar() {
    local pct=$1 color=$2
    [ "$pct" -lt 0 ]  2>/dev/null && pct=0
    [ "$pct" -gt 100 ] 2>/dev/null && pct=100
    local filled=$((pct / 10))
    local empty=$((10 - filled))
    local bar=""
    for ((i = 0; i < filled; i++)); do bar+="█"; done
    for ((i = 0; i < empty; i++)); do  bar+="░"; done
    echo -e "${color}${bar}${D}"
}

pick_color() {
    local p=$1
    [ "$p" -ge 70 ] 2>/dev/null && { echo "$R"; return; }
    [ "$p" -ge 40 ] 2>/dev/null && { echo "$Y"; return; }
    echo "$G"
}

pick_ctx_color() {
    local p=$1
    [ "$p" -ge 70 ] 2>/dev/null && { echo "$R"; return; }
    [ "$p" -le 30 ] 2>/dev/null && { echo "$G"; return; }
    echo "$Y"
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

# --- 智谱 API 用量 ---
get_zhipu_usage() {
    local cache_file="$HOME/.claude/.zhipu_usage_cache"
    local cache_time=300

    if [ -f "$cache_file" ]; then
        local last_mod=$(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null)
        local now=$(date +%s)
        local elapsed=$((now - last_mod))

        if [ $elapsed -lt $cache_time ]; then
            cat "$cache_file" 2>/dev/null
            return
        fi
    fi

    # 从缓存文件读取 token（不触发 Keychain）
    local auth_token=""
    if [ -f "$HOME/.claude/.zhipu_auth_token" ]; then
        auth_token=$(cat "$HOME/.claude/.zhipu_auth_token" 2>/dev/null)
    fi

    [ -z "$auth_token" ] && return

    local response=$(curl -s --max-time 5 'https://bigmodel.cn/api/monitor/usage/quota/limit' \
        -H 'accept: application/json, text/plain, */*' \
        -H "authorization: ${auth_token}" \
        -H 'bigmodel-organization: org-8F82302F73594F44B2bdCc5A57BCfD1f' \
        -H 'bigmodel-project: proj_8E86D38C8211410Baa4852408071D1F2' \
        -H 'referer: https://bigmodel.cn/usercenter/glm-coding/usage' \
        -H 'user-agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36' 2>/dev/null)

    echo "$response" > "$cache_file" 2>/dev/null
    echo "$response"
}

zhipu_data=$(get_zhipu_usage)
zhipu_parts=""

if echo "$zhipu_data" | jq -e '.success == true' >/dev/null 2>&1; then
    zhipu_level=$(echo "$zhipu_data" | jq -r '.data.level // ""')
    zhipu_items=()

    # TOKENS_LIMIT（优先展示）
    tokens_limit=$(echo "$zhipu_data" | jq -r '.data.limits[] | select(.type == "TOKENS_LIMIT")')
    if [ -n "$tokens_limit" ]; then
        tokens_pct=$(echo "$tokens_limit" | jq -r '.percentage // 0')
        tokens_color=$(pick_color "$tokens_pct")
        tokens_bar=$(build_bar "$tokens_pct" "$tokens_color")
        zhipu_items+=("${tokens_color}Token:${tokens_bar} ${tokens_pct}%${D}")
    fi

    # TIME_LIMIT（MCP 用量）
    time_limit=$(echo "$zhipu_data" | jq -r '.data.limits[] | select(.type == "TIME_LIMIT")')
    if [ -n "$time_limit" ]; then
        time_pct=$(echo "$time_limit" | jq -r '.percentage // 0')
        time_current=$(echo "$time_limit" | jq -r '.currentValue // 0')
        time_remaining=$(echo "$time_limit" | jq -r '.remaining // 0')
        time_color=$(pick_color "$time_pct")
        time_bar=$(build_bar "$time_pct" "$time_color")
        zhipu_items+=("${time_color}MCP:${time_bar} ${time_pct}%${D} (${time_current}/${time_remaining})")
    fi

    # 组合智谱部分
    if [ ${#zhipu_items[@]} -gt 0 ]; then
        zhipu_label="GLM"
        [ -n "$zhipu_level" ] && zhipu_label="GLM-${zhipu_level}"
        zhipu_combined="${zhipu_items[0]}"
        for item in "${zhipu_items[@]:1}"; do
            zhipu_combined="${zhipu_combined} ${item}"
        done
        zhipu_parts="${zhipu_label} ${zhipu_combined}"
    fi
fi

# --- 组装: 目录 ▸ 模型 ▸ 上下文 ▸ 智谱用量 ---
parts=()
[ -n "$dir_display" ] && parts+=("$dir_display")
[ -n "$model" ] && parts+=("$model")

# Context 部分
ctx_color=$(pick_ctx_color "$used_pct")
bar=$(build_bar "$used_pct" "$ctx_color")
ctx="${bar} ${ctx_color}${used_pct}%${D}"

parts+=("$ctx")

# 智谱部分（先 Token 再 MCP）
[ -n "$zhipu_parts" ] && parts+=("$zhipu_parts")

# 拼接输出
output="${parts[0]}"
for part in "${parts[@]:1}"; do
    output="$output ▸ $part"
done

echo -e "$output"
