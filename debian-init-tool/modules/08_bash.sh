#!/bin/bash
# Bash 配置模块
# 配置 Bash Shell 环境

configure_bash() {
    log_info "开始配置 Bash..."

    # 选择目标用户
    local target_user
    target_user=$(select_target_user)

    if [[ -z "$target_user" ]]; then
        return 1
    fi

    local home_dir
    home_dir=$(getent passwd "$target_user" | cut -d: -f6)

    if [[ ! -d "$home_dir" ]]; then
        draw_msgbox "错误" "用户目录不存在: $home_dir"
        return 1
    fi

    # 配置选项
    local config_options=(
        "aliases" "常用别名" "ON"
        "proxy" "代理函数 (proxy/noproxy)" "ON"
        "myip" "IP 查询函数" "ON"
        "ps1" "美化命令提示符" "ON"
        "history" "历史命令优化" "ON"
        "completion" "自动补全增强" "OFF"
    )

    local selected
    selected=$(whiptail --title "Bash 配置选项" --checklist \
        "选择要配置的功能:" \
        16 50 7 "${config_options[@]}" 3>&1 1>&2 2>&3 | tr -d '"')

    if [[ $? -ne 0 ]] || [[ -z "$selected" ]]; then
        log_info "用户取消配置"
        return 1
    fi

    # 确认
    if ! draw_yesno "确认配置" "将为用户 $target_user 配置以下功能:\n\n${selected// /\\n}\n\n是否继续？"; then
        return 1
    fi

    # 备份现有配置
    backup_file "${home_dir}/.bashrc" "用户 $target_user 的 bashrc"

    # 生成配置
    generate_bash_config "$home_dir" "$selected" "$target_user"

    # 设置权限
    chown "${target_user}:${target_user}" "${home_dir}/.bashrc"

    draw_msgbox "成功" "Bash 配置完成！\n\n请用户 $target_user 重新登录或执行:\nsource ~/.bashrc"

    return 0
}

# 选择目标用户
select_target_user() {
    local users=()
    users+=("root" "root 用户")

    while IFS=: read -r username _ uid _ _ _ _; do
        if [[ $uid -ge 1000 ]] && [[ $uid -lt 65534 ]]; then
            users+=("$username" "普通用户")
        fi
    done < /etc/passwd

    whiptail --title "选择用户" --menu "选择要配置的用户:" \
        15 40 8 "${users[@]}" 3>&1 1>&2 2>&3
}

# 生成 Bash 配置
generate_bash_config() {
    local home_dir="$1"
    local features="$2"
    local user="$3"

    local bashrc_file="${home_dir}/.bashrc"
    local config_block="
# ========== debian-init-tool 配置 (自动生成) ==========
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')

"

    # 代理配置
    local proxy_host="${PROXY_HOST:-127.0.0.1}"
    local proxy_port="${PROXY_PORT:-7890}"

    for feature in $features; do
        case "$feature" in
            aliases)
                config_block+="# --- 常用别名 ---
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'
alias h='history'
alias j='jobs -l'
alias now='date +\"%Y-%m-%d %H:%M:%S\"'
alias ports='netstat -tulanp'
alias myip='curl -s ifconfig.me'

"
                ;;
            proxy)
                config_block+="# --- 代理函数 ---
proxy() {
    export http_proxy=\"http://${proxy_host}:${proxy_port}\"
    export https_proxy=\"http://${proxy_host}:${proxy_port}\"
    export all_proxy=\"socks5://${proxy_host}:${proxy_port}\"
    export no_proxy=\"localhost,127.0.0.1,::1,.local\"
    echo \"代理已启用: ${proxy_host}:${proxy_port}\"
}

noproxy() {
    unset http_proxy https_proxy all_proxy no_proxy
    echo \"代理已关闭\"
}

"
                ;;
            myip)
                config_block+="# --- IP 查询函数 ---
myip() {
    local ip
    ip=\$(curl -s --connect-timeout 5 ifconfig.me 2>/dev/null)
    if [[ -n \"\$ip\" ]]; then
        echo \"外网 IP: \$ip\"
    else
        echo \"无法获取外网 IP\"
    fi
}

localip() {
    echo \"内网 IP: \$(hostname -I | awk '{print \$1}')\"
}

"
                ;;
            ps1)
                config_block+="# --- 命令提示符 ---
if [[ \"\$UID\" -eq 0 ]]; then
    PS1='\[\033[01;31m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]# '
else
    PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
fi

"
                ;;
            history)
                config_block+="# --- 历史命令配置 ---
HISTSIZE=10000
HISTFILESIZE=20000
HISTCONTROL=ignoreboth:erasedups
HISTIGNORE='ls:cd:cd -:pwd:exit:date:* --help'
shopt -s histappend

# 实时保存历史
PROMPT_COMMAND=\"history -a; history -c; history -r; \$PROMPT_COMMAND\"

"
                ;;
            completion)
                config_block+="# --- 补全增强 ---
if [[ -f /etc/bash_completion ]]; then
    source /etc/bash_completion
fi

# 忽略大小写
bind 'set completion-ignore-case on'
bind 'set show-all-if-ambiguous on'

"
                ;;
        esac
    done

    config_block+="export PATH=\"\$HOME/.local/bin:\$PATH\"

# ========== debian-init-tool 配置结束 ==========

"

    # 追加到 .bashrc
    # 检查是否已存在配置
    if ! grep -q "debian-init-tool 配置" "$bashrc_file" 2>/dev/null; then
        echo "$config_block" >> "$bashrc_file"
        log_info "Bash 配置已添加到 $bashrc_file"
    else
        log_info "Bash 配置已存在，跳过"
    fi
}

# 为所有用户配置
configure_bash_all_users() {
    local users=()
    while IFS=: read -r username _ uid _ _ _ _; do
        if [[ $uid -ge 1000 ]] && [[ $uid -lt 65534 ]]; then
            users+=("$username")
        fi
    done < /etc/passwd

    users+=("root")

    for user in "${users[@]}"; do
        local home_dir
        if [[ "$user" == "root" ]]; then
            home_dir="/root"
        else
            home_dir=$(getent passwd "$user" | cut -d: -f6)
        fi

        if [[ -d "$home_dir" ]]; then
            log_info "配置用户 $user 的 Bash..."
            # 使用默认配置
            generate_bash_config "$home_dir" "aliases proxy myip ps1 history" "$user"
            chown "${user}:${user}" "${home_dir}/.bashrc" 2>/dev/null
        fi
    done

    draw_msgbox "完成" "已为所有用户配置 Bash"
}
