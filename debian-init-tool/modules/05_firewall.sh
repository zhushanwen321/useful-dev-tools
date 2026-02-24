#!/bin/bash
# 防火墙配置模块
# 配置 UFW 或 nftables 防火墙

# 获取配置的 SSH 端口 (优先级: 全局变量 > 配置文件 > sshd_config > 默认值)
get_ssh_port() {
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

configure_firewall() {
    log_info "开始配置防火墙..."

    # 选择防火墙工具
    local fw_options=(
        "ufw" "UFW (Uncomplicated Firewall，推荐新手)" "ON"
        "nftables" "nftables (现代 Linux 防火墙)" "OFF"
        "none" "不配置防火墙" "OFF"
    )

    local fw_choice
    fw_choice=$(whiptail --title "防火墙选择" --radiolist \
        "选择要使用的防火墙工具:" \
        12 55 4 "${fw_options[@]}" 3>&1 1>&2 2>&3)

    if [[ $? -ne 0 ]] || [[ "$fw_choice" == "none" ]]; then
        log_info "跳过防火墙配置"
        return 0
    fi

    # 获取 SSH 端口
    CONFIGURED_SSH_PORT=$(get_ssh_port)
    log_info "使用 SSH 端口: $CONFIGURED_SSH_PORT"

    # 根据选择配置防火墙
    case "$fw_choice" in
        ufw)
            configure_ufw
            ;;
        nftables)
            configure_nftables
            ;;
    esac
}

# 配置 UFW
configure_ufw() {
    log_info "配置 UFW 防火墙..."

    # 安装 UFW
    if ! command_exists ufw; then
        apt-get install -y ufw
    fi

    # 备份配置
    backup_file "/etc/default/ufw" "UFW 默认配置"
    [[ -f "/etc/ufw/before.rules" ]] && backup_file "/etc/ufw/before.rules" "UFW 规则"

    # 端口配置选项
    local port_options=(
        "ssh" "SSH (${CONFIGURED_SSH_PORT}/tcp)" "ON"
        "http" "HTTP (80/tcp)" "OFF"
        "https" "HTTPS (443/tcp)" "OFF"
        "custom" "自定义端口" "OFF"
    )

    local selected_ports
    selected_ports=$(whiptail --title "开放端口" --checklist \
        "选择要开放的端口:\n\n注意: SSH 端口 (${CONFIGURED_SSH_PORT}) 必须开放，否则可能无法连接" \
        15 50 6 "${port_options[@]}" 3>&1 1>&2 2>&3 | tr -d '"')

    if [[ $? -ne 0 ]]; then
        selected_ports="ssh"
    fi

    # 确保 SSH 端口被选中
    if [[ "$selected_ports" != *"ssh"* ]]; then
        if draw_yesno "警告" "未选择 SSH 端口！\n\n如果不开放 SSH 端口，您可能无法连接服务器。\n\n是否添加 SSH 端口？"; then
            selected_ports="ssh ${selected_ports}"
        fi
    fi

    # 处理自定义端口
    local custom_ports=""
    if [[ "$selected_ports" == *"custom"* ]]; then
        custom_ports=$(draw_inputbox "自定义端口" "请输入要开放的端口 (多个用逗号分隔，如: 8080,8443/tcp):")
        if [[ $? -eq 0 ]]; then
            selected_ports="${selected_ports/custom/}"
        fi
    fi

    # 默认策略
    local default_policy
    default_policy=$(whiptail --title "默认策略" --radiolist \
        "选择默认的入站策略:" \
        10 50 2 \
        "deny" "拒绝所有入站连接 (推荐)" "ON" \
        "allow" "允许所有入站连接 (不推荐)" "OFF" 3>&1 1>&2 2>&3)

    if [[ $? -ne 0 ]]; then
        default_policy="deny"
    fi

    # 确认配置
    local confirm_msg="将进行以下 UFW 配置:\n\n"
    confirm_msg+="默认策略: ${default_policy} incoming\n"
    confirm_msg+="开放端口: ${selected_ports} ${custom_ports}\n\n"
    confirm_msg+="是否继续？"

    if ! draw_yesno "确认配置" "$confirm_msg"; then
        return 1
    fi

    # 重置 UFW
    ufw --force reset

    # 设置默认策略 (允许出站，限制入站)
    ufw default allow outgoing
    ufw default "$default_policy" incoming

    # 开放端口
    # SSH 端口
    ufw allow "${CONFIGURED_SSH_PORT}/tcp" comment 'SSH'

    # 其他端口
    for port in $selected_ports; do
        case "$port" in
            http)
                ufw allow 80/tcp comment 'HTTP'
                ;;
            https)
                ufw allow 443/tcp comment 'HTTPS'
                ;;
        esac
    done

    # 自定义端口
    if [[ -n "$custom_ports" ]]; then
        IFS=',' read -ra ports <<< "$custom_ports"
        for port in "${ports[@]}"; do
            port=$(echo "$port" | tr -d ' ')
            if [[ -n "$port" ]]; then
                ufw allow "$port" comment 'Custom'
            fi
        done
    fi

    # 启用 UFW
    ufw --force enable

    # 验证状态
    if ufw status | grep -q "Status: active"; then
        local status_info
        status_info=$(ufw status numbered 2>/dev/null | head -20)
        draw_msgbox "成功" "UFW 防火墙已启用！\n\n规则列表:\n${status_info}"
        return 0
    else
        draw_msgbox "警告" "UFW 可能未正确启用"
        return 1
    fi
}

# 配置 nftables
configure_nftables() {
    log_info "配置 nftables 防火墙..."

    # 安装 nftables
    if ! command_exists nft; then
        apt-get install -y nftables
    fi

    # 备份配置
    backup_file "/etc/nftables.conf" "nftables 配置"

    # 端口配置
    local additional_ports=""
    if draw_yesno "额外端口" "是否开放 HTTP (80) 和 HTTPS (443) 端口？"; then
        additional_ports="80 443"
    fi

    # 生成 nftables 配置
    generate_nftables_config "$CONFIGURED_SSH_PORT" "$additional_ports"

    # 启用 nftables
    systemctl enable nftables
    systemctl restart nftables

    # 验证
    if nft list ruleset | grep -q "ssh"; then
        draw_msgbox "成功" "nftables 防火墙已配置！"
        return 0
    else
        draw_msgbox "警告" "nftables 配置可能存在问题"
        return 1
    fi
}

# 生成 nftables 配置
generate_nftables_config() {
    local ssh_port="$1"
    local extra_ports="$2"

    cat > /etc/nftables.conf << EOF
#!/usr/sbin/nft -f

# 由 debian-init-tool 自动生成
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')

flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;

        # 接受已建立的连接
        ct state established,related accept

        # 接受本地连接
        iif lo accept

        # ICMP
        ip protocol icmp accept
        ip6 nexthdr icmpv6 accept

        # SSH
        tcp dport ${ssh_port} accept

        # 额外端口
EOF

    for port in $extra_ports; do
        echo "        tcp dport ${port} accept" >> /etc/nftables.conf
    done

    cat >> /etc/nftables.conf << EOF
    }

    chain forward {
        type filter hook forward priority 0; policy drop;
    }

    chain output {
        type filter hook output priority 0; policy accept;
    }
}
EOF

    log_info "nftables 配置已生成"
}

# 获取防火墙状态
get_firewall_status() {
    if command_exists ufw && ufw status | grep -q "active"; then
        echo "UFW (active)"
    elif command_exists nft && nft list ruleset | grep -q "chain"; then
        echo "nftables (active)"
    else
        echo "未启用"
    fi
}
