#!/bin/bash

input=$(cat)

# --- ANSI Colors ---
R='\033[31m' G='\033[32m' Y='\033[33m' B='\033[34m' M='\033[35m' C='\033[36m' W='\033[37m' D='\033[0m'
# Bold variants
BG='\033[1;32m' BY='\033[1;33m' BB='\033[1;34m' BC='\033[1;36m'

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
    local seven_day_count=0
    for i in {0..6}; do
        local day_dir="${TOKEN_STATS_DIR}/$(date -v-${i}d +%Y-%m-%d)"
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
        local day_dir="${TOKEN_STATS_DIR}/$(date -v-${i}d +%Y-%m-%d)"
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

# --- Progress bar (text embedded, background filled) ---
build_bar() {
    local pct=$1
    local text="${2:-$(printf "%3d%%" "$pct")}"
    [ "$pct" -lt 0 ]  2>/dev/null && pct=0
    [ "$pct" -gt 100 ] 2>/dev/null && pct=100

    local text_len=${#text}
    local total=10
    local tstart=$(( (total - text_len) / 2 ))
    local filled=$((pct * total / 100))

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

# --- Format duration (ms -> readable) ---
format_duration() {
    local ms=$1
    local total_sec=$((ms / 1000))
    local hours=$((total_sec / 3600))
    local mins=$(((total_sec % 3600) / 60))
    local secs=$((total_sec % 60))

    if [ $hours -gt 0 ]; then
        printf "%dh%dm" $hours $mins
    elif [ $mins -gt 0 ]; then
        printf "%dm%ds" $mins $secs
    else
        printf "%ds" $secs
    fi
}

# --- Parse input JSON (single parse) ---
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

# --- Directory display: project name + relative path ---
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
fi
[ -z "$dir_display" ] && [ -n "$current_dir" ] && dir_display=$(basename "$current_dir")

# --- Load calculation (relative to usable window minus 16% buffer) ---
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

# --- Session start time (from transcript file) ---
session_start=""
if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
    start_ts=$(stat -f %B "$transcript_path" 2>/dev/null || stat -c %W "$transcript_path" 2>/dev/null)
    if [ -n "$start_ts" ] && [ "$start_ts" -gt 0 ] 2>/dev/null; then
        session_start=$(date -r "$start_ts" "+%H:%M:%S" 2>/dev/null || date -d "@$start_ts" "+%H:%M:%S" 2>/dev/null)
    fi
fi

# --- Last LLM response time (recorded to temp file) ---
last_llm_time=""
state_file="/tmp/claude-statusline-${session_id}.time"
now_ts=$(date +%s)

if [ -n "$session_id" ]; then
    if [ -f "$state_file" ]; then
        last_ts=$(cat "$state_file" 2>/dev/null)
        if [ -n "$last_ts" ] && [ "$last_ts" -gt 0 ] 2>/dev/null; then
            elapsed=$((now_ts - last_ts))
            if [ $elapsed -lt 60 ]; then
                last_llm_time="${elapsed}s ago"
            else
                last_llm_time="$((elapsed / 60))m ago"
            fi
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
provider_line=""

if echo "$zhipu_data" | jq -e '.success == true' >/dev/null 2>&1; then
    zhipu_level=$(echo "$zhipu_data" | jq -r '.data.level // ""')
    provider_items=()

    # Model
    [ -n "$model" ] && provider_items+=("Model: ${BB}${model}${D}")

    # TOKENS_LIMIT
    tokens_limit=$(echo "$zhipu_data" | jq -r '.data.limits[] | select(.type == "TOKENS_LIMIT")')
    if [ -n "$tokens_limit" ]; then
        tokens_pct=$(echo "$tokens_limit" | jq -r '.percentage // 0')
        tokens_bar=$(build_bar "$tokens_pct")
        provider_items+=("Token: ${tokens_bar}")
    fi

    # TIME_LIMIT (MCP usage)
    time_limit=$(echo "$zhipu_data" | jq -r '.data.limits[] | select(.type == "TIME_LIMIT")')
    if [ -n "$time_limit" ]; then
        time_pct=$(echo "$time_limit" | jq -r '.percentage // 0')
        time_current=$(echo "$time_limit" | jq -r '.currentValue // 0')
        mcp_text="${time_pct}%(${time_current})"
        time_bar=$(build_bar "$time_pct" "$mcp_text")
        provider_items+=("MCP: ${time_bar}")
    fi

    # Build provider line
    if [ ${#provider_items[@]} -gt 0 ]; then
        provider_label="Z.ai"
        [ -n "$zhipu_level" ] && provider_label="Z.ai-${zhipu_level}"
        provider_combined="${provider_items[0]}"
        for item in "${provider_items[@]:1}"; do
            provider_combined="${provider_combined} ▸ ${item}"
        done
        provider_line="Provider: ${BC}${provider_label}${D} ▸ ${provider_combined}"
    fi
fi

# --- Git branch (fallback if no worktree) ---
git_branch=""
if [ -z "$worktree_name" ] && [ -z "$worktree_branch" ]; then
    if [ -n "$current_dir" ] && [ -d "$current_dir/.git" ] 2>/dev/null || git -C "$current_dir" rev-parse --git-dir >/dev/null 2>&1; then
        git_branch=$(git -C "${current_dir:-.}" branch --show-current 2>/dev/null || git -C "${current_dir:-.}" rev-parse --short HEAD 2>/dev/null)
    fi
fi

# --- Line 1: Project + Worktree/Branch + Agent ---
line1_parts=()
if [ -n "$dir_display" ]; then
    line1_parts+=("Project: ${BG}${dir_display}${D}")
fi
if [ -n "$worktree_name" ]; then
    line1_parts+=("Worktree: ${BC}${worktree_name}${D}")
elif [ -n "$worktree_branch" ]; then
    line1_parts+=("Branch: ${BC}${worktree_branch}${D}")
elif [ -n "$git_branch" ]; then
    line1_parts+=("Branch: ${BC}${git_branch}${D}")
fi
if [ -n "$agent_name" ]; then
    line1_parts+=("Agent: ${BY}${agent_name}${D}")
fi

line1=""
if [ ${#line1_parts[@]} -gt 0 ]; then
    line1="${line1_parts[0]}"
    for part in "${line1_parts[@]:1}"; do
        line1="$line1 ▸ $part"
    done
fi

# --- Line 2: Context + Load ---
ctx_bar=$(build_bar "$used_pct")
load_bar=$(build_bar "$load_pct")
line2="Context: ${ctx_bar} ▸ Load: ${load_bar}"

# --- Line 3: Token Speed ---
speed_parts=()
[ -n "$current_speed" ] && [ "$current_speed" -gt 0 ] 2>/dev/null && speed_parts+=("Speed: ${G}${current_speed}${D} tok/s")
[ -n "$today_avg" ] && [ "$today_avg" -gt 0 ] 2>/dev/null && speed_parts+=("Today: ${C}${today_avg}${D}")
[ -n "$seven_day_avg" ] && [ "$seven_day_avg" -gt 0 ] 2>/dev/null && speed_parts+=("7d: ${Y}${seven_day_avg}${D}")
[ -n "$thirty_day_avg" ] && [ "$thirty_day_avg" -gt 0 ] 2>/dev/null && speed_parts+=("30d: ${M}${thirty_day_avg}${D}")

line3=""
if [ ${#speed_parts[@]} -gt 0 ]; then
    line3="Token: ${speed_parts[0]}"
    for part in "${speed_parts[@]:1}"; do
        line3="$line3 ▸ $part"
    done
fi

# --- Line 4: Time info ---
time_parts=()
[ -n "$session_start" ] && time_parts+=("Start: ${C}${session_start}${D}")
[ -n "$duration_str" ] && time_parts+=("Duration: ${G}${duration_str}${D}")
[ -n "$last_llm_time" ] && time_parts+=("Last: ${Y}${last_llm_time}${D}")

line4=""
if [ ${#time_parts[@]} -gt 0 ]; then
    line4="Time: ${time_parts[0]}"
    for part in "${time_parts[@]:1}"; do
        line4="$line4 ▸ $part"
    done
fi

# --- Line 5: Session info ---
line5=""
if [ -n "$session_id" ]; then
    # Session name not available in JSON (feature request: anthropics/claude-code#15472)
    line5="Session: ID: ${M}${session_id:0:12}${D}"
fi

# --- Combine output ---
output=""
[ -n "$line1" ] && output="${line1}"
[ -n "$line2" ] && output="${output}\n${line2}"
[ -n "$provider_line" ] && output="${output}\n${provider_line}"
[ -n "$line3" ] && output="${output}\n${line3}"
[ -n "$line4" ] && output="${output}\n${line4}"
[ -n "$line5" ] && output="${output}\n${line5}"

# Remove leading newline if line1 is empty
output="${output#\\n}"

echo -e "$output"
