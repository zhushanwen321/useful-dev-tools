#!/bin/bash
# TUI 界面函数库
# 使用 whiptail 实现交互式界面

# 获取脚本目录
_UI_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载依赖
if [[ -z "${_LOG_SH_LOADED:-}" ]]; then
    source "${_UI_SCRIPT_DIR}/log.sh"
fi
if [[ -z "${_COMMON_SH_LOADED:-}" ]]; then
    source "${_UI_SCRIPT_DIR}/common.sh"
fi

# 检查 whiptail 是否可用
check_whiptail() {
    if ! command_exists whiptail; then
        apt-get update && apt-get install -y whiptail ncurses-base
    fi
}

# 对话框尺寸
DIALOG_HEIGHT=${DIALOG_HEIGHT:-20}
DIALOG_WIDTH=${DIALOG_WIDTH:-70}
MENU_HEIGHT=${MENU_HEIGHT:-12}

# 重置终端状态 (防止转义序列残留导致乱码)
reset_terminal_state() {
    # 使用 reset 命令完全重置终端
    # 但首先尝试软重置以避免清屏
    printf '\033c' >/dev/tty 2>/dev/null || true

    # 重置所有终端属性
    tput reset >/dev/tty 2>/dev/null || reset >/dev/tty 2>/dev/null || true

    # 确保终端回到正常模式
    stty sane 2>/dev/null || true

    # 清除任何残留的转义序列
    printf '\033[0m\033[?25h\033[?7h' >/dev/tty 2>/dev/null || true
}

# 初始化终端状态
init_terminal() {
    reset_terminal_state
    check_whiptail
}

# 安全的 whiptail 包装函数
# 用法: safe_whiptail [whiptail参数...]
safe_whiptail() {
    # 清理终端 - 使用 /dev/tty 直接输出到终端，避免污染 stdout/stderr
    clear >/dev/tty 2>/dev/null || printf '\033[2J\033[H' >/dev/tty 2>/dev/null || true

    # 执行 whiptail 并捕获输出
    # 注意: fd swap (3>&1 1>&2 2>&3) 会同时捕获 whiptail 的终端恢复序列，
    # 所以必须在返回前清理
    local output
    local ret
    output=$(whiptail "$@" 3>&1 1>&2 2>&3)
    ret=$?

    # 清理 whiptail 可能留下的转义序列 - 使用 /dev/tty 直接输出到终端
    printf '\033[0m\033[?25h\n' >/dev/tty 2>/dev/null || true

    # 清除 output 中可能混入的 ANSI 转义序列，只保留用户选择
    output=$(strip_ansi "$output")

    printf '%s' "$output"
    return $ret
}

# 已完成模块列表
declare -A COMPLETED_MODULES=()

# 标记模块为已完成
mark_completed() {
    local module="$1"
    COMPLETED_MODULES["$module"]="$(date '+%Y-%m-%d %H:%M:%S')"
    log_info "模块 $module 配置完成"
}

# 检查模块是否已完成
is_completed() {
    local module="$1"
    [[ -n "${COMPLETED_MODULES[$module]}" ]]
}

# 获取模块状态标记
get_module_status() {
    local module="$1"
    if is_completed "$module"; then
        echo "✓"
    else
        echo " "
    fi
}

# 显示消息框
draw_msgbox() {
    local title="$1"
    local message="$2"
    local height="${3:-$DIALOG_HEIGHT}"
    local width="${4:-$DIALOG_WIDTH}"

    safe_whiptail --title "$title" --msgbox "$message" "$height" "$width"
    return $?
}

# 显示确认框
draw_yesno() {
    local title="$1"
    local message="$2"
    local height="${3:-10}"
    local width="${4:-$DIALOG_WIDTH}"

    safe_whiptail --title "$title" --yesno "$message" "$height" "$width"
    return $?
}

# 显示输入框
draw_inputbox() {
    local title="$1"
    local prompt="$2"
    local default="${3:-}"
    local height="${4:-10}"
    local width="${5:-$DIALOG_WIDTH}"

    local result
    result=$(safe_whiptail --title "$title" --inputbox "$prompt" "$height" "$width" "$default")

    local exit_status=$?
    if [[ $exit_status -eq 0 ]]; then
        echo "$result"
        return 0
    else
        return 1
    fi
}

# 显示密码输入框
draw_passwordbox() {
    local title="$1"
    local prompt="$2"
    local height="${3:-10}"
    local width="${4:-$DIALOG_WIDTH}"

    local result
    result=$(safe_whiptail --title "$title" --passwordbox "$prompt" "$height" "$width")

    local exit_status=$?
    if [[ $exit_status -eq 0 ]]; then
        echo "$result"
        return 0
    else
        return 1
    fi
}

# 显示菜单
draw_menu() {
    local title="$1"
    local prompt="${2:-请选择:}"
    shift 2
    local options=("$@")

    local height=$((DIALOG_HEIGHT + ${#options[@]} / 3))
    [[ $height -gt 30 ]] && height=30

    local result
    result=$(safe_whiptail --title "$title" --menu "$prompt" \
        "$height" "$DIALOG_WIDTH" "$MENU_HEIGHT" \
        "${options[@]}")

    local exit_status=$?
    if [[ $exit_status -eq 0 ]]; then
        echo "$result"
        return 0
    else
        return 1
    fi
}

# 显示多选列表
draw_checklist() {
    local title="$1"
    local prompt="${2:-请选择 (空格选择，回车确认):}"
    shift 2
    local options=("$@")

    local height=$((DIALOG_HEIGHT + ${#options[@]} / 3))
    [[ $height -gt 30 ]] && height=30

    local result
    result=$(safe_whiptail --title "$title" --checklist "$prompt" \
        "$height" "$DIALOG_WIDTH" "$MENU_HEIGHT" \
        "${options[@]}")

    local exit_status=$?
    if [[ $exit_status -eq 0 ]]; then
        # 移除引号
        echo "$result" | tr -d '"'
        return 0
    else
        return 1
    fi
}

# 显示单选列表
draw_radiolist() {
    local title="$1"
    local prompt="${2:-请选择:}"
    local default="${3:-}"
    shift 3
    local options=("$@")

    # 设置默认选中项
    local processed_options=()
    local i=0
    for ((i=0; i<${#options[@]}; i+=2)); do
        local tag="${options[$i]}"
        local item="${options[$((i+1))]}"
        local status="OFF"
        [[ "$tag" == "$default" ]] && status="ON"
        processed_options+=("$tag" "$item" "$status")
    done

    local height=$((DIALOG_HEIGHT + ${#processed_options[@]} / 4))
    [[ $height -gt 30 ]] && height=30

    local result
    result=$(safe_whiptail --title "$title" --radiolist "$prompt" \
        "$height" "$DIALOG_WIDTH" "$MENU_HEIGHT" \
        "${processed_options[@]}")

    local exit_status=$?
    if [[ $exit_status -eq 0 ]]; then
        echo "$result"
        return 0
    else
        return 1
    fi
}

# 显示进度条 (Gauge)
show_gauge() {
    local title="$1"
    local message="$2"
    local percent="$3"

    clear >/dev/tty 2>/dev/null || printf '\033[2J\033[H' >/dev/tty 2>/dev/null || true
    echo "$percent" | whiptail --title "$title" --gauge "$message" \
        "$DIALOG_HEIGHT" "$DIALOG_WIDTH" 0 >/dev/tty 2>/dev/null
    printf '\033[0m\033[?25h\n' >/dev/tty 2>/dev/null || true
}

# 显示等待消息
draw_waitbox() {
    local title="$1"
    local message="${2:-请稍候...}"

    clear >/dev/tty 2>/dev/null || printf '\033[2J\033[H' >/dev/tty 2>/dev/null || true
    {
        for i in $(seq 1 100); do
            echo $i
            sleep 0.05
        done
    } | whiptail --title "$title" --gauge "$message" \
        "$DIALOG_HEIGHT" "$DIALOG_WIDTH" 0 >/dev/tty 2>/dev/null &
}

# 显示滚动文本
draw_textbox() {
    local title="$1"
    local filepath="$2"
    local height="${3:-$DIALOG_HEIGHT}"
    local width="${4:-$DIALOG_WIDTH}"

    safe_whiptail --title "$title" --textbox "$filepath" "$height" "$width"
}

# 显示文件选择
draw_fileselect() {
    local title="$1"
    local start_dir="${2:-/}"
    local filter="${3:-*}"

    local result
    result=$(safe_whiptail --title "$title" --fselect "$start_dir/$filter" \
        "$DIALOG_HEIGHT" "$DIALOG_WIDTH")

    local exit_status=$?
    if [[ $exit_status -eq 0 ]]; then
        echo "$result"
        return 0
    else
        return 1
    fi
}

# 主菜单
draw_main_menu() {
    local title="Debian 系统初始化配置工具"

    while true; do
        local options=(
            "preflight" "$(get_module_status preflight) 前置检查"
            "apt"       "$(get_module_status apt) APT 源配置"
            "locale"    "$(get_module_status locale) Locale 设置"
            "timezone"  "$(get_module_status timezone) 时区设置"
            "ssh"       "$(get_module_status ssh) SSH 配置"
            "firewall"  "$(get_module_status firewall) 防火墙配置"
            "fail2ban"  "$(get_module_status fail2ban) Fail2ban 配置"
            "user"      "$(get_module_status user) 用户管理"
            "bash"      "$(get_module_status bash) Bash 配置"
            "zsh"       "$(get_module_status zsh) Zsh 配置"
            "docker"    "$(get_module_status docker) Docker 配置"
            "podman"    "$(get_module_status podman) Podman 配置"
            "all"       "一键配置所有模块"
            "backup"    "查看/恢复备份"
            "log"       "查看日志"
            "exit"      "退出"
        )

        local choice
        choice=$(draw_menu "$title" "选择要配置的模块:" "${options[@]}")

        case $? in
            0)
                case "$choice" in
                    exit)
                        return 0
                        ;;
                    all)
                        run_all_modules
                        ;;
                    backup)
                        show_backup_menu
                        ;;
                    log)
                        show_log_viewer
                        ;;
                    *)
                        run_module "$choice"
                        ;;
                esac
                ;;
            1|255)
                return 0
                ;;
        esac
    done
}

# 运行单个模块 (交互模式)
run_module() {
    local module
    module=$(strip_ansi "$1")
    local module_file="${_UI_SCRIPT_DIR}/../modules/$(printf '%02d' $(get_module_index "$module"))_${module}.sh"

    if [[ -f "$module_file" ]]; then
        log_info "开始执行模块: $module"
        if source "$module_file" && configure_"$module"; then
            mark_completed "$module"
            # 调用持久化标记 (如果函数存在)
            if declare -f mark_module_completed &>/dev/null; then
                mark_module_completed "$module"
            fi
            draw_msgbox "成功" "模块 $module 配置完成"
        else
            draw_msgbox "错误" "模块 $module 配置失败，请查看日志"
        fi
    else
        draw_msgbox "错误" "找不到模块文件: $module_file"
    fi
}

# 获取模块索引
get_module_index() {
    local module="$1"
    case "$module" in
        preflight) echo 0 ;;
        apt) echo 1 ;;
        locale) echo 2 ;;
        timezone) echo 3 ;;
        ssh) echo 4 ;;
        firewall) echo 5 ;;
        fail2ban) echo 6 ;;
        user) echo 7 ;;
        bash) echo 8 ;;
        zsh) echo 9 ;;
        docker) echo 10 ;;
        podman) echo 11 ;;
        *) echo 99 ;;
    esac
}

# 运行所有模块
run_all_modules() {
    local modules=("preflight" "apt" "locale" "timezone" "ssh" "firewall" "fail2ban" "user" "bash" "zsh" "docker" "podman")
    local total=${#modules[@]}
    local current=0
    local failed=()

    for module in "${modules[@]}"; do
        ((current++))
        show_gauge "一键配置" "正在配置: $module ($current/$total)" $((current * 100 / total))

        if ! run_module_silent "$module"; then
            failed+=("$module")
        fi
    done

    if [[ ${#failed[@]} -eq 0 ]]; then
        draw_msgbox "成功" "所有模块配置完成!"
    else
        draw_msgbox "警告" "以下模块配置失败: ${failed[*]}"
    fi
}

# 静默运行模块
run_module_silent() {
    local module
    module=$(strip_ansi "$1")
    local module_file="${_UI_SCRIPT_DIR}/../modules/$(printf '%02d' $(get_module_index "$module"))_${module}.sh"

    if [[ -f "$module_file" ]]; then
        if source "$module_file" && configure_"$module"; then
            mark_completed "$module"
            return 0
        fi
    fi
    return 1
}

# 显示备份菜单
show_backup_menu() {
    local backups
    backups=$(list_backups 2>/dev/null)

    if [[ -z "$backups" ]]; then
        draw_msgbox "备份" "没有找到备份"
        return
    fi

    local options=()
    while IFS= read -r backup; do
        options+=("$backup" "")
    done <<< "$backups"

    local choice
    choice=$(draw_menu "备份列表" "选择要恢复的备份:" "${options[@]}")

    if [[ $? -eq 0 ]]; then
        if draw_yesno "确认恢复" "确定要恢复备份 $choice 吗？\n这将覆盖当前配置。"; then
            if restore_backup "$choice"; then
                draw_msgbox "成功" "备份已恢复"
            else
                draw_msgbox "错误" "恢复备份失败"
            fi
        fi
    fi
}

# 显示日志查看器
show_log_viewer() {
    local logfile
    logfile=$(get_log_file)

    if [[ -f "$logfile" ]]; then
        # 创建临时文件用于显示最后 100 行
        local tmpfile
        tmpfile=$(mktemp)
        tail -n 100 "$logfile" > "$tmpfile"
        draw_textbox "日志查看 (最后100行)" "$tmpfile" 25 80
        rm -f "$tmpfile"
    else
        draw_msgbox "日志" "日志文件不存在"
    fi
}

# 标记库已加载
_UI_SH_LOADED=true
