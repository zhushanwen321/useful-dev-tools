#!/bin/bash
# @name fish
# @title Fish Shell 配置
# @category base-tools
# @weight 12
# Fish Shell 配置模块
# 安装和配置 Fish Shell
# 通用配置（proxy/aliases/env）通过 ~/.config/fish/conf.d/ 共享

configure_fish() {
    log_info "开始配置 Fish..."

    # 1. 安装 Fish
    if ! install_fish; then
        return 1
    fi

    # 2. 选择目标用户
    local target_user
    target_user=$(select_fish_target_user)

    if [[ -z "$target_user" ]]; then
        return 1
    fi

    local home_dir
    home_dir=$(getent passwd "$target_user" | cut -d: -f6)

    if [[ ! -d "$home_dir" ]]; then
        draw_msgbox "错误" "用户目录不存在: $home_dir"
        return 1
    fi

    # 3. 配置选项
    local config_options=(
        "shared"              "共享配置 (proxy/aliases/env)" "ON"
        "set-as-default-shell" "设为默认 Shell"              "OFF"
        "abbreviation"        "Fish abbreviation 补全"        "ON"
    )

    local selected
    selected=$(whiptail --title "Fish 配置选项" --checklist \
        "选择要配置的功能:" \
        14 50 5 "${config_options[@]}" 3>&1 1>&2 2>&3 | tr -d '"')

    if [[ $? -ne 0 ]]; then
        log_info "用户取消配置"
        return 1
    fi

    # 4. 如果选择了共享配置，检查是否已有代理配置
    local proxy_host="${PROXY_HOST:-127.0.0.1}"
    local proxy_port="${PROXY_PORT:-7890}"

    if echo "$selected" | grep -qw "shared"; then
        if [[ -f "${home_dir}/.shell/proxy.sh" ]]; then
            log_info "检测到已有 ~/.shell/proxy.sh，跳过代理配置"
            proxy_host=$(grep -oP 'http://\K[^:]+' "${home_dir}/.shell/proxy.sh" | head -1)
            proxy_port=$(grep -oP 'http://[^:]+:\K[0-9]+' "${home_dir}/.shell/proxy.sh" | head -1)
            proxy_host="${proxy_host:-127.0.0.1}"
            proxy_port="${proxy_port:-7890}"
        else
            proxy_host=$(draw_inputbox "代理配置" "代理主机地址:" "$proxy_host") || proxy_host="${PROXY_HOST:-127.0.0.1}"
            proxy_port=$(draw_inputbox "代理配置" "代理端口:" "$proxy_port") || proxy_port="${PROXY_PORT:-7890}"
        fi
    fi

    # 5. 确认
    if ! draw_yesno "确认配置" "将为用户 $target_user 配置以下功能:\n\n${selected// /\\n}\n\n是否继续？"; then
        return 1
    fi

    # 6. 生成共享配置
    if echo "$selected" | grep -qw "shared"; then
        ensure_shell_common "$home_dir" "$target_user" "$proxy_host" "$proxy_port"
    fi

    # 7. 生成 Fish 专属配置
    generate_fish_config "$home_dir" "$target_user" "$selected"

    # 8. 设置为默认 shell
    if echo "$selected" | grep -qw "set-as-default-shell"; then
        chsh -s /usr/bin/fish "$target_user"
        log_info "已将 Fish 设为用户 $target_user 的默认 Shell"
    fi

    # 确保文件归属正确
    chown -R "${target_user}:${target_user}" "${home_dir}/.config/fish" 2>/dev/null

    # 9. 成功提示
    local default_info=""
    echo "$selected" | grep -qw "set-as-default-shell" && default_info="\n已设为默认 Shell"

    draw_msgbox "成功" "Fish 配置完成！\n\n共享配置: ~/.config/fish/conf.d/${default_info}\n\n请用户 $target_user 执行:\nfish"

    return 0
}

# 安装 Fish
install_fish() {
    if command_exists fish; then
        log_info "Fish 已安装"
        return 0
    fi

    log_info "安装 Fish Shell..."

    # 优先尝试从官方 APT 源安装（Debian 12+ 自带较新版本）
    apt-get update
    if apt-get install -y fish; then
        if command_exists fish; then
            log_info "Fish 安装成功"
            return 0
        fi
    fi

    # 备用: 从 Fish 官方 PPA/仓库安装
    log_info "尝试从 Fish 官方仓库安装..."

    # Debian 需要添加 Fish 官方仓库
    apt-get install -y curl gnupg2

    local codename
    codename=$(cat /etc/os-release | grep VERSION_CODENAME | cut -d= -f2)
    if [[ -z "$codename" ]]; then
        codename="bookworm"
    fi

    # 添加 Fish 官方 GPG key 和仓库
    curl -fsSL https://download.opensuse.org/repositories/shells:fish:release:3/Debian_${codename}/Release.gpg \
        | gpg --dearmor -o /usr/share/keyrings/fish.gpg 2>/dev/null

    echo "deb [signed-by=/usr/share/keyrings/fish.gpg] https://download.opensuse.org/repositories/shells:fish:release:3/Debian_${codename}/ /" \
        > /etc/apt/sources.list.d/fish.list

    apt-get update
    if apt-get install -y fish; then
        if command_exists fish; then
            log_info "Fish 从官方仓库安装成功"
            return 0
        fi
    fi

    log_error "Fish 安装失败"
    draw_msgbox "错误" "Fish Shell 安装失败\n\n请检查网络连接或手动安装:\napt-get install fish"
    return 1
}

# 选择目标用户
select_fish_target_user() {
    local users=()

    # root 用户始终可选
    users+=("root" "Root 用户 (uid=0)")

    while IFS=: read -r username _ uid _ _ home _; do
        if [[ $uid -ge 1000 ]] && [[ $uid -lt 65534 ]]; then
            users+=("$username" "普通用户 ($home)")
        fi
    done < /etc/passwd

    whiptail --title "选择用户" --menu "选择要配置 Fish 的用户:" \
        15 50 8 "${users[@]}" 3>&1 1>&2 2>&3
}

# 生成 Fish 专属配置
generate_fish_config() {
    local home_dir="$1"
    local user="$2"
    local features="$3"

    local fish_conf_dir="${home_dir}/.config/fish"
    mkdir -p "$fish_conf_dir"

    # --- config.fish (Fish 主配置文件) ---
    local config_file="${fish_conf_dir}/config.fish"

    cat > "$config_file" << 'EOF'
# 由 debian-init-tool 自动生成
# 生成时间: TIMESTAMP

# Fish 主配置文件
# 通用配置已在 conf.d/ 中自动加载，无需手动 source

EOF

    # 替换时间戳
    sed -i "s/TIMESTAMP/$(date '+%Y-%m-%d %H:%M:%S')/" "$config_file"

    # --- abbreviation 补全 (Fish 原生的命令缩写) ---
    if echo "$features" | grep -qw "abbreviation"; then
        local abbr_file="${fish_conf_dir}/conf.d/abbreviations.fish"
        cat > "$abbr_file" << 'ABBR_EOF'
# Fish Abbreviations - 由 debian-init-tool 生成
# abbreviation 展开后可编辑，比 alias 更友好

abbr -a -- cls 'clear'
abbr -a -- ll 'ls -alF'
abbr -a -- la 'ls -A'
abbr -a -- .. 'cd ..'
abbr -a -- ... 'cd ../..'
abbr -a -- gs 'git status'
abbr -a -- gl 'git log --oneline -20'
abbr -a -- gd 'git diff'
abbr -a -- ga 'git add'
abbr -a -- gc 'git commit'
abbr -a -- gp 'git push'
ABBR_EOF
        log_info "Fish abbreviations 已生成"
    fi

    # --- Fish 专属函数目录 ---
    local func_dir="${fish_conf_dir}/functions"
    mkdir -p "$func_dir"

    # myip 函数 (Fish 版)
    cat > "${func_dir}/myip.fish" << 'EOF'
function myip
    set -l ip (curl -s --connect-timeout 5 ifconfig.me 2>/dev/null)
    if test -n "$ip"
        echo "外网 IP: $ip"
    else
        echo "无法获取外网 IP"
    end
end
EOF

    # localip 函数 (Fish 版)
    cat > "${func_dir}/localip.fish" << 'EOF'
function localip
    echo "内网 IP: "(hostname -I | awk '{print $1}')
end
EOF

    # 设置文件归属
    chown -R "${user}:${user}" "$fish_conf_dir"

    log_info "Fish 配置已生成: $fish_conf_dir"
}
