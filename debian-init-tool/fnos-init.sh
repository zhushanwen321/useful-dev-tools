#!/bin/bash
#
# 飞牛OS (fnOS) 安装后初始化脚本
#
# 功能: 飞牛OS安装完成后一键初始化配置
#   1. 创建用户主目录并赋予权限
#   2. 更新 /etc/hosts 中 GitHub DNS 解析
#   3. 克隆 useful-dev-tools 仓库
#
# 用法: sudo ./fnos-init.sh [用户名]
#

set -euo pipefail

# ============================================
# 颜色与格式
# ============================================
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# ============================================
# 配置
# ============================================
REPO_URL="https://github.com/zhushanwen321/useful-dev-tools.git"
REPO_DIR_NAME="useful-dev-tools"

# GitHub DNS IP 列表 (2024-2025 可用)
GITHUB_IPS=(
    "20.205.243.166"
    "20.200.245.247"
    "20.27.177.113"
    "140.82.112.4"
    "140.82.121.4"
    "140.82.121.3"
)

# ============================================
# 临时文件清理
# ============================================
_TEMP_FILES=()

cleanup() {
    if [[ ${#_TEMP_FILES[@]} -gt 0 ]]; then
        for f in "${_TEMP_FILES[@]}"; do
            rm -f "$f" 2>/dev/null || true
        done
    fi
}
trap cleanup EXIT

# ============================================
# 辅助函数 (全部输出到 stderr，避免污染命令替换)
# ============================================
info()    { echo -e "${GREEN}[INFO]${NC} $*" >&2; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
section() { echo -e "\n${CYAN}========================================${NC}" >&2; echo -e "${CYAN}  $*${NC}" >&2; echo -e "${CYAN}========================================${NC}" >&2; }

# 检测最优 GitHub IP (TCP 443 连通性测试)
# 注意: 本函数通过 stdout 返回 IP，内部日志必须写到 stderr
pick_best_github_ip() {
    local timeout_sec=3
    local best_ip=""
    local best_ms=99999

    for ip in "${GITHUB_IPS[@]}"; do
        if timeout "$timeout_sec" bash -c "echo >/dev/tcp/$ip/443" 2>/dev/null; then
            # 使用 bash SECONDS 级别计时，避免 date +%s%N 兼容性问题
            local start_s end_s elapsed_ds
            start_s=$SECONDS

            # 二次连接取耗时 (首次连接已成功，这次只测速度)
            if timeout "$timeout_sec" bash -c "echo >/dev/tcp/$ip/443" 2>/dev/null; then
                end_s=$SECONDS
                elapsed_ds=$(( (end_s - start_s) * 100 ))  # 分秒级精度，足以排序
            else
                elapsed_ds=9999
            fi

            if [[ $elapsed_ds -lt $best_ms ]]; then
                best_ms=$elapsed_ds
                best_ip="$ip"
            fi
        fi
    done

    # 如果所有 IP 都不可达，使用第一个
    if [[ -z "$best_ip" ]]; then
        warn "所有 GitHub IP 均不可达，使用默认: ${GITHUB_IPS[0]}"
        best_ip="${GITHUB_IPS[0]}"
    else
        info "选择最优 GitHub IP: $best_ip"
    fi

    # 唯一的 stdout 输出 — 调用方通过 $(...) 捕获此值
    echo "$best_ip"
}

# ============================================
# 步骤 1: 创建用户主目录
# ============================================
setup_user_home() {
    section "步骤 1/3: 创建用户主目录"

    local target_user="${1:-}"

    if [[ -z "$target_user" ]]; then
        error "无法确定目标用户名，请通过参数指定: sudo $0 <用户名>"
        return 1
    fi

    local home_dir="/home/$target_user"

    if [[ -d "$home_dir" ]]; then
        info "用户主目录已存在: $home_dir"
    else
        info "创建用户主目录: $home_dir"
        mkdir -p "$home_dir"
    fi

    # 获取目标用户的 uid/gid
    local uid gid
    if id "$target_user" &>/dev/null; then
        uid=$(id -u "$target_user")
        gid=$(id -g "$target_user")
    else
        # 飞牛OS 可能用户不在标准 passwd 中，使用默认值
        warn "用户 $target_user 不在系统 passwd 中，使用 1000:100"
        uid=1000
        gid=100
    fi

    # 递归转移整个主目录的所有权给目标用户
    # 飞牛OS 安装后 /home/xxx 可能由 root 创建，包含子目录，需整体移交
    chown -R "$uid:$gid" "$home_dir"
    chmod 755 "$home_dir"

    info "用户主目录设置完成: $home_dir (uid=$uid, gid=$gid)"

    # 导出变量供后续步骤使用
    _TARGET_USER="$target_user"
    _TARGET_HOME="$home_dir"
    _TARGET_UID="$uid"
    _TARGET_GID="$gid"
}

# ============================================
# 步骤 2: 更新 /etc/hosts GitHub DNS
# ============================================
update_hosts_github() {
    section "步骤 2/3: 更新 GitHub DNS 解析"

    local hosts_file="/etc/hosts"

    # 备份原 hosts 文件
    local backup="${hosts_file}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$hosts_file" "$backup"
    info "已备份 $hosts_file -> $backup"

    # 检测最优 IP
    info "检测最优 GitHub IP (TCP 443 连通性测试)..."
    local best_ip
    best_ip=$(pick_best_github_ip)

    # 创建临时文件
    local temp_hosts
    temp_hosts=$(mktemp "${TMPDIR:-/tmp}/fnos-hosts.XXXXXX")
    _TEMP_FILES+=("$temp_hosts")

    # 逐行过滤 GitHub 相关条目，写入临时文件
    local github_re='(github\.com|github\.global\.ssl\.fastly\.net|assets-cdn\.github\.com|codeload\.github\.com)([:space:不久]|$)'
    while IFS= read -r line || [[ -n "$line" ]]; do
        # 跳过包含 GitHub 域名的行 (注释行也一并清理，避免残留旧配置)
        if echo "$line" | grep -qiE 'github\.(com|global\.ssl\.fastly\.net)|assets-cdn\.github\.com|codeload\.github\.com'; then
            continue
        fi
        # 跳过本工具之前添加的标记注释
        if echo "$line" | grep -q 'auto-updated by fnos-init\.sh'; then
            continue
        fi
        echo "$line" >> "$temp_hosts"
    done < "$hosts_file"

    # 添加新的 GitHub 条目
    {
        echo ""
        echo "# GitHub DNS (auto-updated by fnos-init.sh at $(date '+%Y-%m-%d %H:%M:%S'))"
        echo "$best_ip    github.com"
        echo "$best_ip    github.global.ssl.fastly.net"
        echo "$best_ip    assets-cdn.github.com"
        echo "$best_ip    codeload.github.com"
    } >> "$temp_hosts"

    # 原子替换
    cat "$temp_hosts" > "$hosts_file"
    chmod 644 "$hosts_file"

    info "已更新 $hosts_file 中的 GitHub DNS 解析"
    info "  github.com -> $best_ip"

    # 验证
    if grep -q "^${best_ip}.*github\.com" "$hosts_file"; then
        info "DNS 解析验证通过"
    else
        warn "DNS 解析验证失败，请手动检查 $hosts_file"
    fi
}

# ============================================
# 步骤 3: 克隆仓库
# ============================================
clone_repo() {
    section "步骤 3/3: 克隆 useful-dev-tools 仓库"

    local target_home="${_TARGET_HOME:-/home/${_TARGET_USER:-$SUDO_USER}}"
    local target_user="${_TARGET_USER:-$SUDO_USER}"
    local target_uid="${_TARGET_UID:-}"
    local target_gid="${_TARGET_GID:-}"

    # 兜底获取 uid/gid
    if [[ -z "$target_uid" ]]; then
        if id "$target_user" &>/dev/null; then
            target_uid=$(id -u "$target_user")
            target_gid=$(id -g "$target_user")
        else
            target_uid=1000
            target_gid=100
        fi
    fi

    local repo_path="$target_home/$REPO_DIR_NAME"

    # 检查 git 是否安装
    if ! command -v git &>/dev/null; then
        info "安装 git..."
        apt-get update -qq && apt-get install -y -qq git || {
            error "git 安装失败"
            return 1
        }
    fi

    # 如果目录已存在，尝试更新
    if [[ -d "$repo_path/.git" ]]; then
        info "仓库已存在，尝试拉取最新代码..."
        local pull_output
        pull_output=$(cd "$repo_path" && git pull 2>&1) || {
            warn "仓库更新失败，保留现有版本"
            warn "$pull_output"
            return 0
        }
        info "仓库更新成功"
    elif [[ -d "$repo_path" ]]; then
        warn "目录 $repo_path 已存在但非 git 仓库，跳过克隆"
    else
        info "克隆仓库: $REPO_URL"
        info "目标路径: $repo_path"

        local retry=0
        local max_retries=3

        while [[ $retry -lt $max_retries ]]; do
            if git clone "$REPO_URL" "$repo_path"; then
                info "仓库克隆成功"
                break
            else
                retry=$((retry + 1))
                if [[ $retry -lt $max_retries ]]; then
                    warn "克隆失败，${retry}/${max_retries} 重试中..."
                    rm -rf "$repo_path" 2>/dev/null || true
                    sleep 5
                else
                    error "克隆失败，已达最大重试次数"
                    error "请手动执行: git clone $REPO_URL $repo_path"
                    return 1
                fi
            fi
        done
    fi

    # 确保目录属主正确
    chown -R "$target_uid:$target_gid" "$repo_path" 2>/dev/null || true
    info "仓库目录权限已设置为 $target_user"
}

# ============================================
# 主函数
# ============================================
main() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║   飞牛OS (fnOS) 初始化工具          ║${NC}"
    echo -e "${CYAN}║   Fresh Install Setup               ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
    echo ""

    # 检查 root 权限
    if [[ $EUID -ne 0 ]]; then
        error "此脚本需要 root 权限运行"
        echo "请使用: sudo $0 [用户名]" >&2
        exit 1
    fi

    # 检查是否为飞牛OS 或 Debian 系
    if [[ -f /etc/os-release ]]; then
        # source 到子 shell 避免污染当前环境变量
        eval "$(grep -E '^(NAME|VERSION)=' /etc/os-release)"
        info "当前系统: $NAME $VERSION"
    fi

    # 确定目标用户
    local target_user="${1:-$SUDO_USER}"

    if [[ -z "$target_user" ]]; then
        error "无法确定目标用户名"
        echo "用法: sudo $0 <用户名>" >&2
        echo "  例如: sudo $0 admin" >&2
        exit 1
    fi

    info "目标用户: $target_user"
    echo ""

    # 执行三步初始化
    local failed_steps=()

    if ! setup_user_home "$target_user"; then
        failed_steps+=("创建用户主目录")
    fi

    if ! update_hosts_github; then
        failed_steps+=("更新 GitHub DNS")
    fi

    if ! clone_repo; then
        failed_steps+=("克隆仓库")
    fi

    # 输出结果摘要
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║   初始化完成                         ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"

    if [[ ${#failed_steps[@]} -eq 0 ]]; then
        echo -e "${GREEN}  [OK] 所有步骤执行成功${NC}"
    else
        echo -e "${YELLOW}  以下步骤失败:${NC}"
        for step in "${failed_steps[@]}"; do
            echo -e "  ${RED}[FAIL] $step${NC}"
        done
    fi

    echo ""
    info "用户主目录: /home/$target_user"
    info "仓库路径:   /home/$target_user/$REPO_DIR_NAME"
    echo ""
    echo -e "运行 Debian 初始化工具:"
    echo -e "  ${CYAN}cd /home/$target_user/$REPO_DIR_NAME/debian-init-tool${NC}"
    echo -e "  ${CYAN}sudo ./debian-init.sh${NC}"
    echo ""
}

main "$@"
