#!/bin/bash
#
# Debian 系统初始化配置工具
#
# 功能: 一键式 Debian 系统初始化配置
# 支持: Debian 11 (Bullseye) / Debian 12 (Bookworm)
#

set -o pipefail

# ============================================
# 强制设置 UTF-8 locale (避免中文乱码)
# ============================================
force_utf8_locale() {
    # 检查是否已经是 UTF-8
    case "${LANG:-}" in
        *UTF-8*|*utf8*) return 0 ;;
    esac

    # 需要强制设置
    echo "Setting UTF-8 locale..."

    # 确保 locale 文件中有 en_US.UTF-8
    if [[ -f /etc/locale.gen ]]; then
        sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen 2>/dev/null
        locale-gen en_US.UTF-8 2>/dev/null
    fi

    # 导出环境变量
    export LANG="en_US.UTF-8"
    export LC_ALL="en_US.UTF-8"
    export LANGUAGE="en_US:en"
}

# ============================================
# 设置终端类型 (避免 whiptail 转义序列乱码)
# ============================================
set_term_type() {
    # Debian 12 需要更保守的 TERM 设置
    if [[ -z "${TERM:-}" ]] || [[ "$TERM" == "dumb" ]]; then
        export TERM=linux
    fi
    
    # 确保使用基本的终端类型以避免兼容性问题
    case "$TERM" in
        xterm*|tmux*|screen*)
            # 保持原样，但确保基础功能
            ;;
        *)
            export TERM=linux
            ;;
    esac
    
    # 禁用 ACS 字符集问题
    export NCURSES_NO_UTF8_ACS=1
    
    # 确保终端大小被正确识别
    if [[ -n "$LINES" ]] && [[ -n "$COLUMNS" ]]; then
        stty rows "$LINES" cols "$COLUMNS" 2>/dev/null
    fi
}

# 在最开始设置 locale
force_utf8_locale

# 设置终端类型
set_term_type

# 版本信息
VERSION="1.0.0"
SCRIPT_NAME="Debian Init Tool"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载公共函数
source "${SCRIPT_DIR}/lib/log.sh" || { echo "无法加载日志模块"; exit 1; }
source "${SCRIPT_DIR}/lib/common.sh" || { echo "无法加载公共模块"; exit 1; }
source "${SCRIPT_DIR}/lib/ui.sh" || { echo "无法加载界面模块"; exit 1; }
source "${SCRIPT_DIR}/lib/network.sh" || { echo "无法加载网络模块"; exit 1; }
source "${SCRIPT_DIR}/lib/backup.sh" || { echo "无法加载备份模块"; exit 1; }

# 加载默认配置
if [[ -f "${SCRIPT_DIR}/config/defaults.conf" ]]; then
    source "${SCRIPT_DIR}/config/defaults.conf"
fi

# 帮助信息
show_help() {
    cat << EOF
${SCRIPT_NAME} v${VERSION}

用法: $(basename "$0") [选项]

选项:
    -h, --help          显示帮助信息
    -v, --version       显示版本信息
    -a, --auto          自动模式 (非交互)
    -p, --profile       使用预设配置文件 (server|desktop|minimal)
    -o, --only          仅执行指定模块 (逗号分隔)
    -s, --skip          跳过指定模块 (逗号分隔)
    -r, --restore       恢复备份
    -l, --list-backups  列出可用备份
    --dry-run           模拟运行 (不实际执行)
    --debug             启用调试模式

模块列表:
    preflight   前置检查
    apt         APT 源配置
    locale      Locale 设置
    timezone    时区设置
    ssh         SSH 配置
    firewall    防火墙配置
    fail2ban    Fail2ban 配置
    user        用户管理
    bash        Bash 配置
    zsh         Zsh 配置
    docker      Docker 配置
    podman      Podman 配置

示例:
    $(basename "$0")                    # 交互模式
    $(basename "$0") --auto             # 自动配置所有
    $(basename "$0") --only ssh,docker  # 仅配置 SSH 和 Docker
    $(basename "$0") --restore          # 恢复备份

EOF
}

# 显示版本
show_version() {
    echo "${SCRIPT_NAME} v${VERSION}"
}

# 解析命令行参数
parse_args() {
    AUTO_MODE=false
    PROFILE=""
    ONLY_MODULES=""
    SKIP_MODULES=""
    RESTORE_MODE=false
    LIST_BACKUPS=false
    DRY_RUN=false
    DEBUG_MODE=false
    BACKUP_NAME=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                show_version
                exit 0
                ;;
            -a|--auto)
                AUTO_MODE=true
                shift
                ;;
            -p|--profile)
                PROFILE="$2"
                shift 2
                ;;
            -o|--only)
                ONLY_MODULES="$2"
                shift 2
                ;;
            -s|--skip)
                SKIP_MODULES="$2"
                shift 2
                ;;
            -r|--restore)
                RESTORE_MODE=true
                BACKUP_NAME="$2"
                shift 2 2>/dev/null || shift
                ;;
            -l|--list-backups)
                LIST_BACKUPS=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --debug)
                DEBUG_MODE=true
                CURRENT_LOG_LEVEL="DEBUG"
                shift
                ;;
            *)
                echo "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# 加载模块
load_modules() {
    local modules_dir="${SCRIPT_DIR}/modules"

    for module_file in "${modules_dir}"/*.sh; do
        if [[ -f "$module_file" ]]; then
            source "$module_file" || log_warn "无法加载模块: $module_file"
        fi
    done
}

# 运行指定模块 (命令行/自动模式)
run_module_cli() {
    local module="$1"
    local module_func="configure_${module}"

    if declare -f "$module_func" &>/dev/null; then
        log_info "执行模块: $module"

        if $DRY_RUN; then
            log_info "[模拟] 将执行: $module_func"
            return 0
        fi

        if $module_func; then
            mark_completed "$module"
            # 调用持久化标记 (如果函数存在)
            if declare -f mark_module_completed &>/dev/null; then
                mark_module_completed "$module"
            fi
            return 0
        else
            log_error "模块 $module 执行失败"
            return 1
        fi
    else
        log_error "找不到模块: $module"
        return 1
    fi
}

# 自动模式运行
run_auto_mode() {
    log_info "启动自动配置模式..."

    local modules=("preflight" "apt" "locale" "timezone" "ssh" "firewall" "fail2ban" "user" "bash" "zsh" "docker" "podman")

    # 处理 --only 参数
    if [[ -n "$ONLY_MODULES" ]]; then
        IFS=',' read -ra modules <<< "$ONLY_MODULES"
    fi

    # 处理 --skip 参数
    local skip_array=()
    if [[ -n "$SKIP_MODULES" ]]; then
        IFS=',' read -ra skip_array <<< "$SKIP_MODULES"
    fi

    local failed_modules=()
    local total=${#modules[@]}
    local current=0

    for module in "${modules[@]}"; do
        # 检查是否跳过
        local skip=false
        for skip_module in "${skip_array[@]}"; do
            if [[ "$module" == "$skip_module" ]]; then
                skip=true
                break
            fi
        done

        if $skip; then
            log_info "跳过模块: $module"
            continue
        fi

        ((current++))
        echo "[$current/$total] 配置: $module"

        if ! run_module_cli "$module"; then
            failed_modules+=("$module")
        fi
    done

    # 报告结果
    echo ""
    echo "================================"
    if [[ ${#failed_modules[@]} -eq 0 ]]; then
        echo "所有模块配置完成!"
    else
        echo "配置完成，以下模块失败:"
        for module in "${failed_modules[@]}"; do
            echo "  - $module"
        done
    fi
    echo "================================"

    return ${#failed_modules[@]}
}

# 打印退出会话摘要
print_exit_summary() {
    fini_log

    echo ""
    echo "========================================"
    echo "  Debian Init Tool - 会话结束"
    echo "========================================"
    echo "  日志文件: $LOG_FILE"
    echo "  查看日志: tail -50 $LOG_FILE"
    echo "========================================"

    local completed_count=0
    for module in "${!COMPLETED_MODULES[@]}"; do
        ((completed_count++))
    done

    if [[ $completed_count -gt 0 ]]; then
        echo "  已完成 $completed_count 个模块:"
        for module in "${!COMPLETED_MODULES[@]}"; do
            echo "    - $module (${COMPLETED_MODULES[$module]})"
        done
    else
        echo "  未完成任何模块"
    fi

    echo "========================================"
    echo ""
}

# 交互模式运行
run_interactive_mode() {
    # 初始化日志
    init_log

    # 初始化终端状态
    init_terminal

    # 运行前置检查
    if ! run_module "preflight"; then
        draw_msgbox "错误" "前置检查失败，无法继续"
        exit 1
    fi

    # 显示主菜单
    draw_main_menu

    # 退出时打印会话摘要（whiptail 已释放终端，输出可见）
    print_exit_summary
}

# 恢复备份
restore_backup_mode() {
    if [[ -z "$BACKUP_NAME" ]]; then
        # 列出可用备份
        local backups
        backups=$(list_backups)

        if [[ -z "$backups" ]]; then
            echo "没有找到可用备份"
            exit 1
        fi

        echo "可用备份:"
        echo "$backups"
        exit 0
    fi

    log_info "恢复备份: $BACKUP_NAME"

    if restore_backup "$BACKUP_NAME"; then
        echo "备份恢复成功"
        exit 0
    else
        echo "备份恢复失败"
        exit 1
    fi
}

# 列出备份
list_backups_mode() {
    local backups
    backups=$(list_backups)

    if [[ -z "$backups" ]]; then
        echo "没有找到可用备份"
    else
        echo "可用备份:"
        echo "$backups"
    fi
    exit 0
}

# 主函数
main() {
    # 解析参数
    parse_args "$@"

    # 检查 root 权限
    if [[ $EUID -ne 0 ]]; then
        echo "错误: 此脚本需要 root 权限运行" >&2
        echo "请使用: sudo $0"
        exit 1
    fi

    # 加载模块
    load_modules

    # 列出备份模式
    if $LIST_BACKUPS; then
        list_backups_mode
    fi

    # 恢复备份模式
    if $RESTORE_MODE; then
        restore_backup_mode
    fi

    # 自动模式
    if $AUTO_MODE; then
        init_log
        run_auto_mode
        exit $?
    fi

    # 交互模式
    run_interactive_mode
}

# 执行主函数
main "$@"
