#!/bin/bash
# 公共函数库
# 提供通用工具函数

# 严格模式
set -o pipefail

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# 获取 lib 目录 (不覆盖主脚本的 SCRIPT_DIR)
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载依赖 (log.sh)
if [[ -z "${_LOG_SH_LOADED:-}" ]]; then
    source "${_LIB_DIR}/log.sh"
fi

# 检查是否为 root 用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误: 此脚本需要 root 权限运行${NC}" >&2
        echo "请使用: sudo $0"
        exit 1
    fi
}

# 检查系统是否为 Debian
check_debian_version() {
    if [[ ! -f /etc/os-release ]]; then
        echo -e "${RED}错误: 无法检测系统版本${NC}" >&2
        return 1
    fi

    source /etc/os-release

    if [[ "$ID" != "debian" ]]; then
        echo -e "${YELLOW}警告: 当前系统为 $ID，此工具专为 Debian 设计${NC}" >&2
        read -rp "是否继续? [y/N]: " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || exit 1
    fi

    DEBIAN_VERSION="${VERSION_ID:-unknown}"
    DEBIAN_CODENAME="${VERSION_CODENAME:-unknown}"

    log_info "检测到 Debian $DEBIAN_VERSION ($DEBIAN_CODENAME)"
    echo "$DEBIAN_VERSION"
}

# 检查命令是否存在
command_exists() {
    command -v "$1" &>/dev/null
}

# 检查文件是否存在
file_exists() {
    [[ -f "$1" ]]
}

# 检查目录是否存在
dir_exists() {
    [[ -d "$1" ]]
}

# 安装软件包
install_packages() {
    local packages=("$@")
    local to_install=()

    for pkg in "${packages[@]}"; do
        if ! dpkg -l "$pkg" &>/dev/null | grep -q "^ii"; then
            to_install+=("$pkg")
        fi
    done

    if [[ ${#to_install[@]} -eq 0 ]]; then
        log_info "所有软件包已安装"
        return 0
    fi

    log_info "安装软件包: ${to_install[*]}"

    # 使用 retry_command 处理网络问题
    if retry_command 3 apt-get install -y "${to_install[@]}"; then
        log_info "软件包安装成功"
        return 0
    else
        log_error "软件包安装失败"
        return 1
    fi
}

# 带重试的命令执行
retry_command() {
    local max_attempts="${1:-3}"
    local delay="${2:-5}"
    shift 2
    local cmd=("$@")

    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        log_debug "尝试 $attempt/$max_attempts: ${cmd[*]}"

        if "${cmd[@]}"; then
            return 0
        fi

        if [[ $attempt -lt $max_attempts ]]; then
            log_warn "命令失败，${delay}秒后重试..."
            sleep "$delay"
        fi

        ((attempt++))
    done

    log_error "命令执行失败，已达最大重试次数"
    return 1
}

# 获取用户确认
get_user_confirmation() {
    local prompt="${1:-确认继续?}"
    local default="${2:-n}"

    local yn
    if [[ "$default" == "y" ]]; then
        read -rp "$prompt [Y/n]: " yn
        [[ -z "$yn" || "$yn" =~ ^[Yy]$ ]]
    else
        read -rp "$prompt [y/N]: " yn
        [[ "$yn" =~ ^[Yy]$ ]]
    fi
}

# 验证输入不为空
validate_not_empty() {
    local value="$1"
    local name="${2:-输入}"

    if [[ -z "$value" ]]; then
        echo -e "${RED}错误: $name 不能为空${NC}" >&2
        return 1
    fi
    return 0
}

# 验证用户名格式
validate_username() {
    local username="$1"

    # Linux 用户名规范: 字母开头，可包含字母、数字、下划线、连字符，最长 32 字符
    if [[ ! "$username" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
        echo -e "${RED}错误: 用户名格式无效${NC}" >&2
        echo "用户名必须: 以小写字母或下划线开头，只能包含小写字母、数字、下划线和连字符，最长 32 字符" >&2
        return 1
    fi

    # 检查用户名是否已存在
    if id "$username" &>/dev/null; then
        echo -e "${YELLOW}警告: 用户 $username 已存在${NC}" >&2
        return 2
    fi

    return 0
}

# 验证端口号
validate_port() {
    local port="$1"

    if [[ ! "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
        echo -e "${RED}错误: 端口号必须在 1-65535 之间${NC}" >&2
        return 1
    fi

    # 检查端口是否被占用
    if ss -tlnp | grep -q ":${port} "; then
        echo -e "${YELLOW}警告: 端口 $port 已被占用${NC}" >&2
        return 2
    fi

    return 0
}

# 验证 SSH 公钥格式
validate_ssh_pubkey() {
    local key="$1"

    # 基本格式检查
    if [[ ! "$key" =~ ^(ssh-rsa|ssh-ed25519|ssh-dss|ecdsa-sha2-nistp) ]]; then
        echo -e "${RED}错误: SSH 公钥格式无效${NC}" >&2
        return 1
    fi

    return 0
}

# 安全地获取数值输入
read_number() {
    local prompt="$1"
    local default="${2:-}"
    local min="${3:-1}"
    local max="${4:-65535}"

    while true; do
        local input
        read -rp "$prompt [$default]: " input

        # 使用默认值
        if [[ -z "$input" ]]; then
            input="$default"
        fi

        # 验证是否为数字
        if [[ "$input" =~ ^[0-9]+$ ]]; then
            if [[ "$input" -ge $min ]] && [[ "$input" -le $max ]]; then
                echo "$input"
                return 0
            else
                echo -e "${RED}错误: 请输入 $min 到 $max 之间的数字${NC}" >&2
            fi
        else
            echo -e "${RED}错误: 请输入有效的数字${NC}" >&2
        fi
    done
}

# 等待服务就绪
wait_for_service() {
    local service="$1"
    local timeout="${2:-30}"
    local interval="${3:-2}"

    log_info "等待服务 $service 启动..."

    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        if systemctl is-active --quiet "$service"; then
            log_info "服务 $service 已启动"
            return 0
        fi

        sleep "$interval"
        ((elapsed += interval))
    done

    log_error "等待服务 $service 超时"
    return 1
}

# 获取系统内存大小 (MB)
get_memory_size() {
    free -m | awk '/^Mem:/{print $2}'
}

# 获取系统 CPU 核心数
get_cpu_cores() {
    nproc
}

# 检查是否为虚拟机
is_virtual_machine() {
    if command_exists systemd-detect-virt; then
        local virt_type
        virt_type=$(systemd-detect-virt --vm 2>/dev/null)
        [[ -n "$virt_type" && "$virt_type" != "none" ]]
    else
        # 备用检测方法
        grep -q "hypervisor" /proc/cpuinfo 2>/dev/null
    fi
}

# 打印分隔线
print_separator() {
    local char="${1:--}"
    local length="${2:-60}"
    printf "%${length}s\n" | tr ' ' "$char"
}

# 打印标题
print_title() {
    local title="$1"
    echo ""
    print_separator "="
    echo "  $title"
    print_separator "="
    echo ""
}

# 显示进度
show_progress() {
    local current="$1"
    local total="$2"
    local message="${3:-处理中}"

    local percent=$((current * 100 / total))
    local filled=$((percent / 2))
    local empty=$((50 - filled))

    printf "\r%s [%s%s] %d%%" "$message" "$(printf '#%.0s' $(seq 1 $filled))" "$(printf ' %.0s' $(seq 1 $empty))" "$percent"
    [[ $current -eq $total ]] && echo ""
}

# 标记库已加载
_COMMON_SH_LOADED=true
