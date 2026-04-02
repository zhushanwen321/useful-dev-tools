#!/bin/bash

input=$(cat)

# ═══════════════════════════════════════════════════════════
# ┃  Claude Code Statusline — Refined Single-Line Theme   ┃
# ═══════════════════════════════════════════════════════════

# --- ANSI Colors (curated palette) ---
R='\033[31m' G='\033[32m' Y='\033[33m' B='\033[34m' M='\033[35m' C='\033[36m' W='\033[37m' D='\033[0m'
# Refined 256-color tones
DG='\033[38;5;65m'     # Teal (dim labels)
CY='\033[38;5;180m'    # Warm gold
WH='\033[38;5;254m'    # Soft white
GM='\033[38;5;245m'    # Gray-mid
BGB='\033[38;5;117m'   # Ice blue (bright)
BGC='\033[38;5;152m'   # Steel teal
# Bright
BG='\033[1;32m' BY='\033[1;33m' BB='\033[1;34m' BC='\033[1;36m' BM='\033[1;35m'
# Bold 256-color
BGG='\033[1;38;5;150m'  # Bright sage

# Decorative separators
SEP="${GM}│${D}"        # Section divider
NSEP="${GM}·${D}"      # Sub-item divider
ARW="${DG}›${D}"        # Arrow accent

# ============================================================
# --- Token Speed Tracking ---
# ============================================================
TOKEN_STATS_DIR="${HOME}/.claude/token-stats"
mkdir -p "$TOKEN_STATS_DIR"

get_token_speed_stats() {
    local output_tokens=$1
    local api_duration_ms=$2
    local model=$3

    local current_speed=0
    if [ -n "$api_duration_ms" ] && [ "$api_duration_ms" -gt 0 ] 2>/dev/null; then
        current_speed=$(awk "BEGIN {printf \"%.0f\", ($output_tokens / $api_duration_ms) * 1000}")
    fi

    local today=$(date +%Y-%m-%d)
    local today_dir="${TOKEN_STATS_DIR}/${today}"
    mkdir -p "$today_dir"

    local file_name="${model}"
    file_name="${file_name//\//_}"
    file_name="${file_name// /_}"
    local today_file="${today_dir}/${file_name}.txt"

    if [ -n "$model" ] && [ "$current_speed" -gt 0 ] 2>/dev/null; then
        echo "$(date +%s),${output_tokens},${api_duration_ms},${current_speed}" >> "$today_file"
    fi

    local today_avg=0
    if [ -f "$today_file" ]; then
        today_avg=$(awk -F, '
            BEGIN { sum=0; count=0 }
            { sum+=$4; count++ }
            END { if(count>0) printf "%.0f", sum/count }
        ' "$today_file" 2>/dev/null || echo "0")
    fi

    local seven_day_avg=0
    local seven_day_total=0
    local date_cmd
    if date -v-1d +%Y-%m-%d >/dev/null 2>&1; then
        date_cmd="bsd"
    else
        date_cmd="gnu"
    fi

    local seven_day_count=0
    for i in {0..6}; do
        local day_str
        if [ "$date_cmd" = "bsd" ]; then
            day_str=$(date -v-${i}d +%Y-%m-%d)
        else
            day_str=$(date -d "${i} days ago" +%Y-%m-%d)
        fi
        local day_dir="${TOKEN_STATS_DIR}/${day_str}"
        local day_file="${day_dir}/${file_name}.txt"
        if [ -f "$day_file" ]; then
            while IFS=',' read -r ts otps dm spd; do
                [ -n "$spd" ] && [ "$spd" -gt 0 ] 2>/dev/null && {
                    seven_day_total=$((seven_day_total + spd))
                    seven_day_count=$((seven_day_count + 1))
                }
            done < "$day_file"
        fi
    done
    if [ "$seven_day_count" -gt 0 ] 2>/dev/null; then
        seven_day_avg=$(awk "BEGIN {printf \"%.0f\", $seven_day_total / $seven_day_count}")
    fi

    local thirty_day_avg=0
    local thirty_day_total=0
    local thirty_day_count=0
    for i in {0..29}; do
        local day_str
        if [ "$date_cmd" = "bsd" ]; then
            day_str=$(date -v-${i}d +%Y-%m-%d)
        else
            day_str=$(date -d "${i} days ago" +%Y-%m-%d)
        fi
        local day_dir="${TOKEN_STATS_DIR}/${day_str}"
        local day_file="${day_dir}/${file_name}.txt"
        if [ -f "$day_file" ]; then
            while IFS=',' read -r ts otps dm spd; do
                [ -n "$spd" ] && [ "$spd" -gt 0 ] 2>/dev/null && {
                    thirty_day_total=$((thirty_day_total + spd))
                    thirty_day_count=$((thirty_day_count + 1))
                }
            done < "$day_file"
        fi
    done
    if [ "$thirty_day_count" -gt 0 ] 2>/dev/null; then
        thirty_day_avg=$(awk "BEGIN {printf \"%.0f\", $thirty_day_total / $thirty_day_count}")
    fi

    echo "${current_speed} ${today_avg} ${seven_day_avg} ${thirty_day_avg}"
}

# --- Progress bar (ANSI background colors, baseline-safe) ---
# 用背景色空格替代 Unicode 块字符，避免行高被撑大导致百分比文字偏移
build_bar() {
    local pct=$1
    local width=${2:-8}
    [ "$pct" -lt 0 ]  2>/dev/null && pct=0
    [ "$pct" -gt 100 ] 2>/dev/null && pct=100

    local filled=$((pct * width / 100))
    local remaining=$((width - filled))

    # 填充色：按阈值从绿到红
    local fill_bg
    if [ "$pct" -ge 80 ]; then fill_bg='\033[48;5;196m'
    elif [ "$pct" -ge 60 ]; then fill_bg='\033[48;5;208m'
    elif [ "$pct" -ge 40 ]; then fill_bg='\033[48;5;220m'
    else fill_bg='\033[48;5;114m'; fi
    # 空白背景色
    local empty_bg='\033[48;5;239m'

    local bar=""
    for ((i = 0; i < filled; i++)); do bar+="${fill_bg} "; done
    for ((i = 0; i < remaining; i++)); do bar+="${empty_bg} "; done
    bar+="${D}"

    echo -e "$bar"
}

# --- Format duration ---
format_duration() {
    local ms=$1
    local total_sec=$((ms / 1000))
    local hours=$((total_sec / 3600))
    local mins=$(((total_sec % 3600) / 60))
    local secs=$((total_sec % 60))

    if [ $hours -gt 0 ]; then
        printf "%dh%02dm" $hours $mins
    elif [ $mins -gt 0 ]; then
        printf "%dm%02ds" $mins $secs
    else
        printf "%ds" $secs
    fi
}

# --- Parse input JSON ---
parsed=$(echo "$input" | jq -c '{
    project_dir: .workspace.project_dir,
    current_dir: (.workspace.current_dir // .cwd),
    model: .model.display_name,
    used_pct: (.context_window.used_percentage // 0),
    agent: .agent.name,
    worktree_name: .worktree.name,
    worktree_branch: .worktree.branch,
    total_duration_ms: .cost.total_duration_ms,
    total_api_duration_ms: .cost.total_api_duration_ms,
    total_output_tokens: .context_window.total_output_tokens,
    session_id: .session_id,
    transcript_path: .transcript_path
}')

project_dir=$(echo "$parsed" | jq -r '.project_dir // empty')
current_dir=$(echo "$parsed" | jq -r '.current_dir // empty')
model=$(echo "$parsed" | jq -r '.model // "Unknown"')
used_pct=$(echo "$parsed" | jq -r '.used_pct // 0')
agent_name=$(echo "$parsed" | jq -r '.agent // empty')
worktree_name=$(echo "$parsed" | jq -r '.worktree_name // empty')
worktree_branch=$(echo "$parsed" | jq -r '.worktree_branch // empty')
total_duration_ms=$(echo "$parsed" | jq -r '.total_duration_ms // 0')
total_api_duration_ms=$(echo "$parsed" | jq -r '.total_api_duration_ms // 0')
total_output_tokens=$(echo "$parsed" | jq -r '.total_output_tokens // 0')
session_id=$(echo "$parsed" | jq -r '.session_id // empty')
transcript_path=$(echo "$parsed" | jq -r '.transcript_path // empty')

# --- Directory display ---
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
            dir_display="$project_name/${relative}"
        fi
    fi
fi
[ -z "$dir_display" ] && [ -n "$current_dir" ] && dir_display=$(basename "$current_dir")

# --- Load calculation ---
BUFFER_PCT=16
load_pct=$(echo "$parsed" | jq -r --argjson buf "$BUFFER_PCT" '
  .used_pct as $used |
  (100 - $buf) as $usable |
  if $usable > 0 then
    [$used * 100 / $usable | floor, 100] | min
  else
    100
  end
')

# --- Session start time ---
session_start=""
if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
    start_ts=$(stat -f %B "$transcript_path" 2>/dev/null || stat -c %W "$transcript_path" 2>/dev/null)
    if [ -n "$start_ts" ] && [ "$start_ts" -gt 0 ] 2>/dev/null; then
        session_start=$(date -r "$start_ts" "+%H:%M:%S" 2>/dev/null || date -d "@$start_ts" "+%H:%M:%S" 2>/dev/null)
    fi
fi

# --- Last LLM response time ---
last_llm_time=""
last_response_time=""
state_file="/tmp/claude-statusline-${session_id}.time"
now_ts=$(date +%s)

if [ -n "$session_id" ]; then
    if [ -f "$state_file" ]; then
        last_ts=$(cat "$state_file" 2>/dev/null)
        if [ -n "$last_ts" ] && [ "$last_ts" -gt 0 ] 2>/dev/null; then
            elapsed=$((now_ts - last_ts))
            if [ $elapsed -lt 60 ]; then
                last_llm_time="${elapsed}s"
            else
                last_llm_time="$((elapsed / 60))m$((elapsed % 60))s"
            fi
            last_response_time=$(date -r "$last_ts" "+%H:%M:%S" 2>/dev/null || date -d "@$last_ts" "+%H:%M:%S" 2>/dev/null)
        fi
    fi
    echo "$now_ts" > "$state_file"
fi

# --- Session duration ---
duration_str=""
if [ -n "$total_duration_ms" ] && [ "$total_duration_ms" -gt 0 ] 2>/dev/null; then
    duration_str=$(format_duration "$total_duration_ms")
fi

# --- Token Speed Stats ---
read -r current_speed today_avg seven_day_avg thirty_day_avg <<< "$(get_token_speed_stats "$total_output_tokens" "$total_api_duration_ms" "$model")"

# --- Zhipu usage ---
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

has_zhipu=false
zhipu_label=""
zhipu_tokens_pct=0
zhipu_time_pct=0
zhipu_time_current=""

if echo "$zhipu_data" | jq -e '.success == true' >/dev/null 2>&1; then
    has_zhipu=true
    zhipu_level=$(echo "$zhipu_data" | jq -r '.data.level // ""')
    zhipu_label="Z.ai"
    [ -n "$zhipu_level" ] && zhipu_label="Z.ai-${zhipu_level}"

    tokens_limit=$(echo "$zhipu_data" | jq -r '.data.limits[] | select(.type == "TOKENS_LIMIT")')
    if [ -n "$tokens_limit" ]; then
        zhipu_tokens_pct=$(echo "$tokens_limit" | jq -r '.percentage // 0')
    fi

    time_limit=$(echo "$zhipu_data" | jq -r '.data.limits[] | select(.type == "TIME_LIMIT")')
    if [ -n "$time_limit" ]; then
        zhipu_time_pct=$(echo "$time_limit" | jq -r '.percentage // 0')
        zhipu_time_current=$(echo "$time_limit" | jq -r '.currentValue // 0')
    fi
fi

# --- Git branch ---
git_branch=""
if [ -z "$worktree_name" ] && [ -z "$worktree_branch" ]; then
    if [ -n "$current_dir" ] && [ -d "$current_dir/.git" ] 2>/dev/null || git -C "$current_dir" rev-parse --git-dir >/dev/null 2>&1; then
        git_branch=$(git -C "${current_dir:-.}" branch --show-current 2>/dev/null || git -C "${current_dir:-.}" rev-parse --short HEAD 2>/dev/null)
    fi
fi

# ═══════════════════════════════════════════════════════════
# ┃  BUILD MULTI-LINE OUTPUT                              ┃
# ═══════════════════════════════════════════════════════════
#
# 布局（3行分区）：
# Line 1: 项目 · 分支 · Agent │ 模型
# Line 2: ctx ▓▓▓░░ 45% · load ▓▓▓▓░░ 53% │ Z.ai ▓░░ 12% · mcp ▒░░ 11%
# Line 3: 274t/s · day 274 · 7d 274 · 30d 274 │ from 10:30 · run 2m05s · last 4m │ abc123de · resp 11:30

NSEP="${GM}·${D}"

# --- Line 1: Identity + Model ---
identity=""
if [ -n "$dir_display" ]; then
    identity="${BG}${dir_display}${D}"
fi
branch_display=""
if [ -n "$worktree_name" ]; then branch_display="${BC}${worktree_name}${D}"
elif [ -n "$worktree_branch" ]; then branch_display="${BC}${worktree_branch}${D}"
elif [ -n "$git_branch" ]; then branch_display="${BC}${git_branch}${D}"; fi
if [ -n "$branch_display" ]; then
    [ -n "$identity" ] && identity="${identity} ${NSEP} "
    identity="${identity}⎇ ${branch_display}"
fi
if [ -n "$agent_name" ]; then
    [ -n "$identity" ] && identity="${identity} ${NSEP} "
    identity="${identity}${BY}${agent_name}${D}"
fi
if [ -n "$model" ]; then
    [ -n "$identity" ] && identity="${identity} ${SEP} "
    identity="${identity}${BGB}${model}${D}"
fi

# --- Line 2: Context + Provider ---
ctx_bar=$(build_bar "$used_pct" 8)
load_bar=$(build_bar "$load_pct" 8)
metrics="${DG}ctx${D} ${ctx_bar} ${WH}${used_pct}%${D} ${NSEP} ${DG}load${D} ${load_bar} ${WH}${load_pct}%${D}"

if [ "$has_zhipu" = true ]; then
    provider_bar=$(build_bar "$zhipu_tokens_pct" 6)
    provider_part="${DG}${zhipu_label}${D} ${provider_bar} ${WH}${zhipu_tokens_pct}%${D}"
    if [ -n "$zhipu_time_current" ]; then
        mcp_bar=$(build_bar "$zhipu_time_pct" 6)
        provider_part="${provider_part} ${NSEP} ${DG}mcp${D} ${mcp_bar} ${WH}${zhipu_time_pct}%${D} ${GM}(${zhipu_time_current})${D}"
    fi
    metrics="${metrics} ${SEP} ${provider_part}"
fi

# --- Line 3: Speed + Time + Session ---
# Speed
speed_parts=()
[ -n "$current_speed" ] && [ "$current_speed" -gt 0 ] 2>/dev/null && speed_parts+=("${G}${current_speed}${D}t/s")
[ -n "$today_avg" ] && [ "$today_avg" -gt 0 ] 2>/dev/null && speed_parts+=("day ${C}${today_avg}${D}")
[ -n "$seven_day_avg" ] && [ "$seven_day_avg" -gt 0 ] 2>/dev/null && speed_parts+=("7d ${CY}${seven_day_avg}${D}")
[ -n "$thirty_day_avg" ] && [ "$thirty_day_avg" -gt 0 ] 2>/dev/null && speed_parts+=("30d ${M}${thirty_day_avg}${D}")

line3=""
if [ ${#speed_parts[@]} -gt 0 ]; then
    line3="${speed_parts[0]}"
    for part in "${speed_parts[@]:1}"; do
        line3="${line3} ${NSEP} ${part}"
    done
fi

# Time
time_items=()
[ -n "$session_start" ] && time_items+=("${DG}from${D} ${C}${session_start}${D}")
[ -n "$duration_str" ] && time_items+=("${DG}run${D} ${G}${duration_str}${D}")
[ -n "$last_llm_time" ] && time_items+=("${DG}last${D} ${Y}${last_llm_time}${D}")

time_str=""
if [ ${#time_items[@]} -gt 0 ]; then
    time_str="${time_items[0]}"
    for item in "${time_items[@]:1}"; do
        time_str="${time_str} ${NSEP} ${item}"
    done
fi

if [ -n "$time_str" ]; then
    [ -n "$line3" ] && line3="${line3} ${SEP} ${time_str}" || line3="$time_str"
fi

# Session
session_str=""
if [ -n "$session_id" ]; then
    session_str="${GM}${session_id:0:8}${D}"
    [ -n "$last_response_time" ] && session_str="${session_str} ${NSEP} ${DG}resp${D} ${C}${last_response_time}${D}"
fi

if [ -n "$session_str" ]; then
    [ -n "$line3" ] && line3="${line3} ${SEP} ${session_str}" || line3="$session_str"
fi

# ═══════════════════════════════════════════════════════════
# ┃  ASSEMBLE FINAL OUTPUT                                ┃
# ═══════════════════════════════════════════════════════════

output=""
[ -n "$identity" ] && output="${identity}"
[ -n "$metrics" ] && output="${output}\n${metrics}"
[ -n "$line3" ] && output="${output}\n${line3}"

# 去掉开头的 \n（identity 为空时）
output="${output#\\n}"

echo -e "$output"
