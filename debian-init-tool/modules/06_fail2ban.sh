#!/bin/bash
# Fail2ban 配置模块
# 配置 Fail2ban 防止暴力破解

# 获取配置的 SSH 端口 (与 firewall 模块保持一致)
get_ssh_port_for_fail2ban() {
    local port

    # 1. 检查全局变量 (由 SSH 模块设置)
    if [[ -n "${CONFIGURED_SSH_PORT:-}" ]]; then
        echo "$CONFIGURED_SSH_PORT"
        return 0
    fi

    # 2. 从持久化配置读取
    if [[ -f "/etc/debian-init-tool/config.conf" ]]; then
        port=$(grep "^CONFIGURED_SSH_PORT=" /etc/debian-init-tool/config.conf 2>/dev/null | cut -d'=' -f2)
        if [[ -n "$port" ]]; then
            echo "$port"
            return 0
        fi
    fi

    # 3. 从 sshd_config 读取
    port=$(grep -E "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
    if [[ -n "$port" ]]; then
        echo "$port"
        return 0
    fi

    # 4. 默认端口
    echo "${DEFAULT_SSH_PORT:-22}"
}

configure_fail2ban() {
    log_info "开始配置 Fail2ban..."

    # 检查是否安装
    if ! command_exists fail2ban-server; then
        if draw_yesno "安装 Fail2ban" "Fail2ban 未安装，是否安装？\n\nFail2ban 可以自动封禁暴力破解 IP。"; then
            apt-get update
            apt-get install -y fail2ban
        else
            return 1
        fi
    fi

    # 获取 SSH 端口
    local ssh_port
    ssh_port=$(get_ssh_port_for_fail2ban)
    log_info "使用 SSH 端口: $ssh_port"

    # 配置参数
    local max_retry
    max_retry=$(draw_inputbox "最大重试次数" "请输入最大认证失败次数:" "3")

    if [[ $? -ne 0 ]]; then
        max_retry="3"
    fi

    local find_time
    find_time=$(draw_inputbox "检测时间窗口 (秒)" "请输入检测失败的时间窗口 (默认 10 分钟):" "600")

    if [[ $? -ne 0 ]]; then
        find_time="600"
    fi

    local ban_time
    ban_time=$(draw_inputbox "封禁时间 (秒)" "请输入封禁时间 (默认 1 小时，-1 为永久):" "3600")

    if [[ $? -ne 0 ]]; then
        ban_time="3600"
    fi

    # 确认配置
    local confirm_msg="将进行以下 Fail2ban 配置:\n\n"
    confirm_msg+="监控服务: SSH (端口 ${ssh_port})\n"
    confirm_msg+="最大重试: ${max_retry} 次\n"
    confirm_msg+="检测窗口: $((find_time / 60)) 分钟\n"
    confirm_msg+="封禁时间: $(if [[ $ban_time -eq -1 ]]; then echo '永久'; else echo "$((ban_time / 60)) 分钟"; fi)\n\n"
    confirm_msg+="是否继续？"

    if ! draw_yesno "确认配置" "$confirm_msg"; then
        return 1
    fi

    # 备份配置
    [[ -f "/etc/fail2ban/jail.local" ]] && backup_file "/etc/fail2ban/jail.local" "Fail2ban jail 配置"
    [[ -f "/etc/fail2ban/fail2ban.local" ]] && backup_file "/etc/fail2ban/fail2ban.local" "Fail2ban 主配置"

    # 创建 jail.local
    create_jail_config "$ssh_port" "$max_retry" "$find_time" "$ban_time"

    # 启动服务
    if enable_fail2ban; then
        # 显示状态
        local status
        status=$(fail2ban-client status sshd 2>/dev/null || echo "服务已启动，暂无封禁记录")
        draw_msgbox "成功" "Fail2ban 配置完成！\n\n${status}"
        return 0
    else
        draw_msgbox "错误" "Fail2ban 启动失败"
        return 1
    fi
}

# 创建 jail 配置
create_jail_config() {
    local ssh_port="$1"
    local max_retry="$2"
    local find_time="$3"
    local ban_time="$4"

    log_info "创建 Fail2ban 配置..."

    # 检测系统使用的防火墙后端
    local banaction="iptables-multiport"
    local banaction_allports="iptables"

    # Debian 12+ 默认使用 nftables
    if command_exists nft && nft list ruleset &>/dev/null; then
        banaction="nftables"
        banaction_allports="nftables"
        log_info "检测到 nftables，使用 nftables 后端"
    elif command_exists iptables && iptables -L &>/dev/null; then
        banaction="iptables-multiport"
        banaction_allports="iptables"
        log_info "检测到 iptables，使用 iptables 后端"
    else
        # 默认使用 nftables (现代系统)
        banaction="nftables"
        banaction_allports="nftables"
    fi

    cat > /etc/fail2ban/jail.local << EOF
# 由 debian-init-tool 自动生成
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')

[DEFAULT]
# 默认封禁时间
bantime = ${ban_time}

# 检测时间窗口
findtime = ${find_time}

# 最大重试次数
maxretry = ${max_retry}

# 后端
backend = systemd

# 封禁动作 (自动检测: ${banaction})
banaction = ${banaction}
banaction_allports = ${banaction_allports}

# 邮件通知 (可选)
# destemail = root@localhost
# sendername = Fail2Ban
# mta = sendmail

[sshd]
enabled = true
port = ${ssh_port}
filter = sshd
logpath = /var/log/auth.log
maxretry = ${max_retry}
findtime = ${find_time}
bantime = ${ban_time}
EOF

    log_info "jail.local 已创建"
}

# 启用 Fail2ban
enable_fail2ban() {
    log_info "启动 Fail2ban 服务..."

    # 确保服务已启用
    systemctl enable fail2ban 2>/dev/null || true

    # 重启服务
    if systemctl restart fail2ban; then
        # 等待服务就绪
        sleep 2

        if systemctl is-active --quiet fail2ban; then
            log_info "Fail2ban 服务已启动"
            return 0
        fi
    fi

    log_error "Fail2ban 启动失败"
    return 1
}

# 查看封禁状态
show_ban_status() {
    if ! systemctl is-active --quiet fail2ban; then
        draw_msgbox "状态" "Fail2ban 服务未运行"
        return 1
    fi

    local status=""
    status+="Fail2ban 服务状态: 运行中\n\n"

    # SSH jail 状态
    local ssh_status
    ssh_status=$(fail2ban-client status sshd 2>/dev/null)

    if [[ -n "$ssh_status" ]]; then
        status+="SSH 服务状态:\n${ssh_status}\n\n"
    fi

    # 当前封禁的 IP
    local banned_ips
    banned_ips=$(fail2ban-client banned 2>/dev/null | head -20)
    if [[ -n "$banned_ips" ]]; then
        status+="封禁的 IP:\n${banned_ips}"
    fi

    draw_msgbox "Fail2ban 状态" "$status"
}

# 手动封禁/解封 IP
manage_ban_ip() {
    local action_options=(
        "ban" "封禁 IP" ""
        "unban" "解封 IP" ""
        "list" "列出封禁" ""
    )

    local action
    action=$(whiptail --title "IP 管理" --menu "选择操作:" \
        12 40 4 "${action_options[@]}" 3>&1 1>&2 2>&3)

    if [[ $? -ne 0 ]]; then
        return 1
    fi

    case "$action" in
        ban)
            local ip
            ip=$(draw_inputbox "封禁 IP" "请输入要封禁的 IP 地址:")
            if [[ -n "$ip" ]]; then
                fail2ban-client set sshd banip "$ip"
                draw_msgbox "成功" "IP $ip 已被封禁"
            fi
            ;;
        unban)
            local ip
            ip=$(draw_inputbox "解封 IP" "请输入要解封的 IP 地址:")
            if [[ -n "$ip" ]]; then
                fail2ban-client set sshd unbanip "$ip"
                draw_msgbox "成功" "IP $ip 已解封"
            fi
            ;;
        list)
            local banned
            banned=$(fail2ban-client get sshd banip 2>/dev/null)
            draw_msgbox "封禁列表" "当前封禁的 IP:\n\n${banned:-无}"
            ;;
    esac
}
