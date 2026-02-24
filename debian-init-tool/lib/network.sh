#!/bin/bash
# 网络代理函数库
# 处理代理检测、配置和使用

# 获取脚本目录
_NET_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载依赖 (ui.sh 会自动加载 log.sh 和 common.sh)
if [[ -z "${_UI_SH_LOADED:-}" ]]; then
    source "${_NET_SCRIPT_DIR}/ui.sh"
fi

# 代理配置
PROXY_HOST="${PROXY_HOST:-}"
PROXY_PORT="${PROXY_PORT:-7890}"
PROXY_TYPE="${PROXY_TYPE:-http}"

# 原始代理设置 (用于恢复)
_ORIG_HTTP_PROXY="${http_proxy:-}"
_ORIG_HTTPS_PROXY="${https_proxy:-}"
_ORIG_ALL_PROXY="${all_proxy:-}"

# 检测系统代理
detect_proxy() {
    log_debug "检测系统代理设置..."

    # 检查环境变量
    if [[ -n "$http_proxy" || -n "$https_proxy" || -n "$ALL_PROXY" ]]; then
        log_info "检测到代理环境变量"
        return 0
    fi

    # 检查常见代理端口
    local common_ports=(7890 1080 8080 10809 2080)
    for port in "${common_ports[@]}"; do
        if nc -z 127.0.0.1 "$port" 2>/dev/null; then
            log_info "检测到本地代理端口: $port"
            PROXY_PORT="$port"
            return 0
        fi
    done

    return 1
}

# 设置代理环境变量
set_proxy() {
    local host="${1:-$PROXY_HOST}"
    local port="${2:-$PROXY_PORT}"
    local type="${3:-$PROXY_TYPE}"

    if [[ -z "$host" ]]; then
        host="127.0.0.1"
    fi

    case "$type" in
        http|https)
            export http_proxy="http://${host}:${port}"
            export https_proxy="http://${host}:${port}"
            export HTTP_PROXY="http://${host}:${port}"
            export HTTPS_PROXY="http://${host}:${port}"
            ;;
        socks5)
            export http_proxy="socks5://${host}:${port}"
            export https_proxy="socks5://${host}:${port}"
            export all_proxy="socks5://${host}:${port}"
            export HTTP_PROXY="socks5://${host}:${port}"
            export HTTPS_PROXY="socks5://${host}:${port}"
            export ALL_PROXY="socks5://${host}:${port}"
            ;;
        *)
            log_error "不支持的代理类型: $type"
            return 1
            ;;
    esac

    # 设置 no_proxy
    export no_proxy="localhost,127.0.0.1,::1,localaddress,.localdomain.com"
    export NO_PROXY="localhost,127.0.0.1,::1,localaddress,.localdomain.com"

    log_info "代理已设置: ${type}://${host}:${port}"
    return 0
}

# 取消代理设置
unset_proxy() {
    unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY no_proxy NO_PROXY
    log_info "代理已取消"
}

# 恢复原始代理设置
restore_proxy() {
    if [[ -n "$_ORIG_HTTP_PROXY" ]]; then
        export http_proxy="$_ORIG_HTTP_PROXY"
    fi
    if [[ -n "$_ORIG_HTTPS_PROXY" ]]; then
        export https_proxy="$_ORIG_HTTPS_PROXY"
    fi
    if [[ -n "$_ORIG_ALL_PROXY" ]]; then
        export all_proxy="$_ORIG_ALL_PROXY"
    fi
    log_debug "原始代理设置已恢复"
}

# 测试代理连通性
test_proxy_connection() {
    local host="${1:-$PROXY_HOST}"
    local port="${2:-$PROXY_PORT}"
    local timeout="${3:-10}"

    if [[ -z "$host" ]]; then
        host="127.0.0.1"
    fi

    log_debug "测试代理连接: ${host}:${port}"

    # 使用 nc 测试端口
    if timeout "$timeout" nc -z "$host" "$port" 2>/dev/null; then
        log_debug "代理端口可达"
        return 0
    else
        log_debug "代理端口不可达"
        return 1
    fi
}

# 测试网络连接
test_network_connection() {
    local targets=("baidu.com" "aliyun.com" "cloudflare.com")
    local timeout="${1:-5}"

    log_debug "测试网络连接..."

    for target in "${targets[@]}"; do
        if timeout "$timeout" ping -c 1 "$target" &>/dev/null; then
            log_debug "网络连接正常 (通过 $target)"
            return 0
        fi
    done

    # 尝试 HTTP 方式
    for target in "https://www.baidu.com" "https://www.aliyun.com"; do
        if timeout "$timeout" curl -sI "$target" &>/dev/null; then
            log_debug "网络连接正常 (通过 HTTP)"
            return 0
        fi
    done

    log_warn "网络连接测试失败"
    return 1
}

# 测试外网 IP 获取
test_external_ip() {
    local services=("ifconfig.me" "icanhazip.com" "ipinfo.io/ip")
    local timeout="${1:-10}"

    for service in "${services[@]}"; do
        local ip
        ip=$(timeout "$timeout" curl -s "https://$service" 2>/dev/null)
        if [[ -n "$ip" && "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "$ip"
            return 0
        fi
    done

    return 1
}

# 带代理重试的下载
download_with_retry() {
    local url="$1"
    local output="${2:-}"
    local max_attempts="${3:-3}"
    local use_gitee="${4:-true}"

    local download_cmd="curl -fsSL"
    [[ -n "$output" ]] && download_cmd+=" -o $output"

    # 第一次尝试：直接下载
    log_debug "尝试直接下载: $url"
    if eval "$download_cmd \"$url\""; then
        return 0
    fi

    # 第二次尝试：Gitee 镜像
    if [[ "$use_gitee" == "true" ]]; then
        local gitee_url
        gitee_url=$(github_to_gitee "$url")
        if [[ "$gitee_url" != "$url" ]]; then
            log_debug "尝试 Gitee 镜像: $gitee_url"
            if eval "$download_cmd \"$gitee_url\""; then
                return 0
            fi
        fi
    fi

    # 第三次尝试：使用代理
    if detect_proxy || [[ -n "$PROXY_HOST" ]]; then
        log_debug "尝试使用代理下载"
        local old_proxy_settings
        old_proxy_settings=$(env | grep -i proxy)

        set_proxy "$PROXY_HOST" "$PROXY_PORT" "$PROXY_TYPE"

        if eval "$download_cmd \"$url\""; then
            # 下载成功，保持代理设置
            return 0
        fi

        # 恢复代理设置
        unset_proxy
        [[ -n "$old_proxy_settings" ]] && eval "$old_proxy_settings"
    fi

    log_error "下载失败: $url"
    return 1
}

# GitHub URL 转 Gitee 镜像
github_to_gitee() {
    local url="$1"
    local result="$url"

    # 常见的 GitHub 到 Gitee 映射
    case "$url" in
        *github.com/ohmyzsh/ohmyzsh*)
            result="${url/github.com\/ohmyzsh\/ohmyzsh/gitee.com\/mirrors\/oh-my-zsh}"
            ;;
        *github.com/robbyrussell/oh-my-zsh*)
            result="${url/github.com\/robbyrussell\/oh-my-zsh/gitee.com\/mirrors\/oh-my-zsh}"
            ;;
        *github.com/romkatv/powerlevel10k*)
            result="${url/github.com/gitee.com}"
            ;;
        *github.com/zsh-users/*)
            result="${url/github.com/gitee.com}"
            ;;
    esac

    echo "$result"
}

# 配置 APT 代理
configure_apt_proxy() {
    local host="${1:-$PROXY_HOST}"
    local port="${2:-$PROXY_PORT}"

    if [[ -z "$host" ]]; then
        host="127.0.0.1"
    fi

    local apt_proxy_file="/etc/apt/apt.conf.d/95proxy"

    cat > "$apt_proxy_file" << EOF
# 由 debian-init-tool 自动生成
Acquire::http::Proxy "http://${host}:${port}";
Acquire::https::Proxy "http://${host}:${port}";
EOF

    log_info "APT 代理已配置"
}

# 移除 APT 代理
remove_apt_proxy() {
    local apt_proxy_file="/etc/apt/apt.conf.d/95proxy"

    if [[ -f "$apt_proxy_file" ]]; then
        rm -f "$apt_proxy_file"
        log_info "APT 代理已移除"
    fi
}

# 交互式配置代理
interactive_configure_proxy() {
    local title="代理配置"

    if draw_yesno "$title" "是否需要配置网络代理？\n\n如果您在中国大陆且网络受限，建议配置代理。"; then
        # 代理类型
        local proxy_type
        proxy_type=$(draw_radiolist "$title" "选择代理类型:" "http" \
            "http" "HTTP/HTTPS 代理" \
            "socks5" "SOCKS5 代理") || return 1

        # 代理主机
        local proxy_host
        proxy_host=$(draw_inputbox "$title" "请输入代理主机地址:" "127.0.0.1") || return 1

        # 代理端口
        local proxy_port
        proxy_port=$(draw_inputbox "$title" "请输入代理端口:" "7890") || return 1

        # 测试连接
        draw_msgbox "$title" "正在测试代理连接..."

        if test_proxy_connection "$proxy_host" "$proxy_port"; then
            PROXY_HOST="$proxy_host"
            PROXY_PORT="$proxy_port"
            PROXY_TYPE="$proxy_type"

            set_proxy "$PROXY_HOST" "$PROXY_PORT" "$PROXY_TYPE"

            draw_msgbox "$title" "代理连接成功！\n\n地址: ${proxy_type}://${proxy_host}:${proxy_port}"
            return 0
        else
            draw_msgbox "$title" "代理连接失败，请检查配置"
            return 1
        fi
    fi

    return 0
}

# 标记库已加载
_NET_SH_LOADED=true
