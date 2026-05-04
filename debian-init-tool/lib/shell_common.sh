#!/bin/bash
# Shell 共享配置生成库
# 为 bash/zsh 生成 ~/.shell/ 目录 (POSIX 格式)
# 为 fish 生成 ~/.config/fish/conf.d/ 目录 (Fish 格式)
# 所有 shell 共享同一份逻辑配置，只是语法不同

# 获取脚本目录
_SC_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载依赖
if [[ -z "${_LOG_SH_LOADED:-}" ]]; then
    source "${_SC_SCRIPT_DIR}/log.sh"
fi
if [[ -z "${_COMMON_SH_LOADED:-}" ]]; then
    source "${_SC_SCRIPT_DIR}/common.sh"
fi

# ============================================
# 生成 POSIX 格式共享配置 (bash/zsh)
# ============================================

# 生成 ~/.shell/ 目录下所有共享文件
# 参数: $1=home_dir  $2=proxy_host  $3=proxy_port
generate_shell_common_posix() {
    local home_dir="$1"
    local proxy_host="${2:-127.0.0.1}"
    local proxy_port="${3:-7890}"

    local shell_dir="${home_dir}/.shell"
    mkdir -p "$shell_dir"

    log_info "生成 POSIX 共享配置: $shell_dir"

    # --- proxy.sh ---
    cat > "${shell_dir}/proxy.sh" << PROXY_EOF
# 代理配置 - 由 debian-init-tool 生成
# 修改 PROXY_HOST / PROXY_PORT 即可切换代理地址

# cmd: set proxy
proxy() {
    export http_proxy="http://${proxy_host}:${proxy_port}"
    export https_proxy="http://${proxy_host}:${proxy_port}"
    export all_proxy="socks5://${proxy_host}:${proxy_port}"
    export no_proxy="localhost,127.0.0.1,::1,.local"
    echo "代理已启用: ${proxy_host}:${proxy_port}"
}

# cmd: unset proxy
noproxy() {
    unset http_proxy https_proxy all_proxy no_proxy
    echo "代理已关闭"
}

# cmd: show proxy
showproxy() {
    echo "http_proxy: \${http_proxy:-未设置}"
    echo "https_proxy: \${https_proxy:-未设置}"
    echo "all_proxy: \${all_proxy:-未设置}"
}
PROXY_EOF

    # --- aliases.sh ---
    cat > "${shell_dir}/aliases.sh" << ALIASES_EOF
# 通用别名 - 由 debian-init-tool 生成

alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'
alias cls='clear'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'
alias h='history'
alias ports='netstat -tulanp'
ALIASES_EOF

    # --- env.sh ---
    cat > "${shell_dir}/env.sh" << ENV_EOF
# 环境变量 - 由 debian-init-tool 生成

export PATH="\$HOME/.local/bin:\$PATH"
export EDITOR="\${EDITOR:-vim}"
export LANG=en_US.UTF-8
ENV_EOF

    log_info "POSIX 共享配置已生成 (proxy.sh, aliases.sh, env.sh)"
}

# ============================================
# 生成 Fish 格式共享配置
# ============================================

# 生成 ~/.config/fish/conf.d/ 目录下所有共享文件
# 参数: $1=home_dir  $2=proxy_host  $3=proxy_port
generate_shell_common_fish() {
    local home_dir="$1"
    local proxy_host="${2:-127.0.0.1}"
    local proxy_port="${3:-7890}"

    local fish_conf_dir="${home_dir}/.config/fish/conf.d"
    mkdir -p "$fish_conf_dir"

    log_info "生成 Fish 共享配置: $fish_conf_dir"

    # --- proxy.fish ---
    cat > "${fish_conf_dir}/proxy.fish" << PROXY_EOF
# 代理配置 - 由 debian-init-tool 生成

function proxy
    set -gx http_proxy "http://${proxy_host}:${proxy_port}"
    set -gx https_proxy "http://${proxy_host}:${proxy_port}"
    set -gx all_proxy "socks5://${proxy_host}:${proxy_port}"
    set -gx no_proxy "localhost,127.0.0.1,::1,.local"
    echo "代理已启用: ${proxy_host}:${proxy_port}"
end

function noproxy
    set -e http_proxy
    set -e https_proxy
    set -e all_proxy
    set -e no_proxy
    echo "代理已关闭"
end

function showproxy
    if set -q http_proxy
        echo "http_proxy: \$http_proxy"
    else
        echo "http_proxy: 未设置"
    end
    if set -q https_proxy
        echo "https_proxy: \$https_proxy"
    else
        echo "https_proxy: 未设置"
    end
    if set -q all_proxy
        echo "all_proxy: \$all_proxy"
    else
        echo "all_proxy: 未设置"
    end
end
PROXY_EOF

    # --- aliases.fish ---
    cat > "${fish_conf_dir}/aliases.fish" << ALIASES_EOF
# 通用别名 - 由 debian-init-tool 生成

alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'
alias cls='clear'
alias h='history'
alias ports='netstat -tulanp'
ALIASES_EOF

    # --- env.fish ---
    cat > "${fish_conf_dir}/env.fish" << ENV_EOF
# 环境变量 - 由 debian-init-tool 生成

set -gx PATH \$HOME/.local/bin \$PATH
set -gx EDITOR vim
set -gx LANG en_US.UTF-8
ENV_EOF

    log_info "Fish 共享配置已生成 (proxy.fish, aliases.fish, env.fish)"
}

# ============================================
# 一次性生成 POSIX + Fish 两套配置
# ============================================

# 参数: $1=home_dir  $2=user  $3=proxy_host  $4=proxy_port
ensure_shell_common() {
    local home_dir="$1"
    local user="$2"
    local proxy_host="${3:-${PROXY_HOST:-127.0.0.1}}"
    local proxy_port="${4:-${PROXY_PORT:-7890}}"

    log_info "生成 Shell 共享配置 (POSIX + Fish)..."

    generate_shell_common_posix "$home_dir" "$proxy_host" "$proxy_port"
    generate_shell_common_fish "$home_dir" "$proxy_host" "$proxy_port"

    # 设置文件归属
    if [[ -n "$user" ]]; then
        chown -R "${user}:${user}" "${home_dir}/.shell" 2>/dev/null
        chown -R "${user}:${user}" "${home_dir}/.config/fish" 2>/dev/null
    fi

    log_info "Shell 共享配置生成完成"
}

# 标记库已加载
_SHELL_COMMON_SH_LOADED=true
