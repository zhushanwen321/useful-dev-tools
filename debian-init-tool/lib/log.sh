#!/bin/bash
# 日志函数库
# 提供统一的日志记录功能

# 日志级别
declare -A LOG_LEVELS=(
    ["DEBUG"]=0
    ["INFO"]=1
    ["WARN"]=2
    ["ERROR"]=3
)

# 当前日志级别 (默认 INFO)
CURRENT_LOG_LEVEL="${LOG_LEVEL:-INFO}"

# 日志文件路径
LOG_FILE="${LOG_FILE:-/var/log/debian-init-tool.log}"

# 会话 ID (用于追踪同一次执行的日志)
SESSION_ID="${SESSION_ID:-$(date +%Y%m%d_%H%M%S)_$$}"

# 颜色定义
declare -A LOG_COLORS=(
    ["DEBUG"]="\033[0;36m"    # Cyan
    ["INFO"]="\033[0;32m"     # Green
    ["WARN"]="\033[0;33m"     # Yellow
    ["ERROR"]="\033[0;31m"    # Red
    ["RESET"]="\033[0m"
)

# 初始化日志系统
init_log() {
    local log_dir
    log_dir=$(dirname "$LOG_FILE")

    # 确保日志目录存在
    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir" 2>/dev/null || {
            # 如果无法创建系统日志目录，使用用户目录
            LOG_FILE="$HOME/.debian-init-tool/debian-init.log"
            mkdir -p "$(dirname "$LOG_FILE")"
        }
    fi

    # 创建或追加日志文件
    touch "$LOG_FILE" 2>/dev/null || {
        LOG_FILE="/tmp/debian-init-${SESSION_ID}.log"
        touch "$LOG_FILE"
    }

    log_info "=== 会话开始: $SESSION_ID ==="
}

# 内部日志函数
_log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # 检查日志级别
    if [[ ${LOG_LEVELS[$level]} -ge ${LOG_LEVELS[$CURRENT_LOG_LEVEL]} ]]; then
        local log_line="[$timestamp] [$SESSION_ID] [$level] $message"

        # 写入文件
        echo "$log_line" >> "$LOG_FILE"

        # 控制台输出 (带颜色)
        if [[ -t 1 ]]; then
            echo -e "${LOG_COLORS[$level]}${log_line}${LOG_COLORS[RESET]}" >&2
        else
            echo "$log_line" >&2
        fi
    fi
}

# 公共日志函数
log_debug() { _log "DEBUG" "$@"; }
log_info()  { _log "INFO" "$@"; }
log_warn()  { _log "WARN" "$@"; }
log_error() { _log "ERROR" "$@"; }

# 记录命令执行
log_command() {
    log_debug "执行命令: $*"
}

# 记录函数调用
log_func() {
    log_debug "函数调用: ${FUNCNAME[1]}()"
}

# 结束日志会话
fini_log() {
    log_info "=== 会话结束: $SESSION_ID ==="
}

# 获取日志文件路径
get_log_file() {
    echo "$LOG_FILE"
}

# 查看日志
view_log() {
    local lines="${1:-50}"
    if [[ -f "$LOG_FILE" ]]; then
        tail -n "$lines" "$LOG_FILE"
    else
        echo "日志文件不存在: $LOG_FILE"
        return 1
    fi
}

# 标记库已加载
_LOG_SH_LOADED=true
