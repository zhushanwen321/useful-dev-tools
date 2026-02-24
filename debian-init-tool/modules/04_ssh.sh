#!/bin/bash
# SSH 配置模块
# 配置 SSH 服务器安全选项

configure_ssh() {
    log_info "开始配置 SSH..."

    # 检查 SSH 是否已安装
    if ! command_exists sshd; then
        if draw_yesno "SSH 安装" "SSH 服务器未安装，是否安装？"; then
            apt-get update
            apt-get install -y openssh-server
        else
            return 1
        fi
    fi

    # 获取当前 SSH 端口
    local current_port
    current_port=$(grep -E "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "22")

    # SSH 端口配置
    local new_port
    new_port=$(draw_inputbox "SSH 端口" "请输入 SSH 监听端口 (当前: $current_port):" "$current_port")

    if [[ $? -ne 0 ]]; then
        return 1
    fi

    # 验证端口
    if ! validate_port "$new_port"; then
        draw_msgbox "错误" "端口号无效或已被占用"
        return 1
    fi

    # 安全选项配置
    local security_options=(
        "PermitRootLogin" "禁止 root 密码登录" "ON"
        "PubkeyAuth" "启用公钥认证" "ON"
        "PasswordAuth" "启用密码认证" "ON"
        "DisableEmptyPasswords" "禁止空密码" "ON"
        "LimitAuthTries" "限制认证尝试次数 (3次)" "ON"
    )

    local selected_security
    selected_security=$(whiptail --title "安全选项" --checklist \
        "选择要启用的 SSH 安全选项:" \
        18 55 6 "${security_options[@]}" 3>&1 1>&2 2>&3 | tr -d '"')

    if [[ $? -ne 0 ]]; then
        selected_security="PermitRootLogin PubkeyAuth DisableEmptyPasswords LimitAuthTries"
    fi

    # 询问是否生成 SSH 密钥对
    local generate_key=false
    if draw_yesno "SSH 密钥" "是否为当前用户生成 SSH 密钥对？"; then
        generate_key=true
    fi

    # 确认配置
    local confirm_msg="将进行以下 SSH 配置:\n\n"
    confirm_msg+="端口: ${new_port}\n"
    confirm_msg+="安全选项:\n"
    [[ "$selected_security" == *"PermitRootLogin"* ]] && confirm_msg+="  • 禁止 root 密码登录\n"
    [[ "$selected_security" == *"PubkeyAuth"* ]] && confirm_msg+="  • 启用公钥认证\n"
    [[ "$selected_security" == *"PasswordAuth"* ]] && confirm_msg+="  • 启用密码认证\n"
    [[ "$selected_security" == *"DisableEmptyPasswords"* ]] && confirm_msg+="  • 禁止空密码\n"
    [[ "$selected_security" == *"LimitAuthTries"* ]] && confirm_msg+="  • 限制认证尝试\n"
    $generate_key && confirm_msg+="  • 生成 SSH 密钥对\n"
    confirm_msg+="\n是否继续？"

    if ! draw_yesno "确认配置" "$confirm_msg"; then
        return 1
    fi

    # 备份配置
    backup_ssh_config

    # 切换 ssh.socket 到 ssh.service (Debian 默认使用 socket 激活)
    switch_ssh_to_service

    # 修改 sshd_config
    modify_sshd_config "$new_port" "$selected_security"

    # 生成 SSH 密钥
    if $generate_key; then
        generate_ssh_key
    fi

    # 重启 SSH
    if restart_ssh; then
        # 保存 SSH 端口到持久化配置 (供 firewall/fail2ban 模块使用)
        if declare -f save_config &>/dev/null; then
            save_config "CONFIGURED_SSH_PORT" "$new_port"
        fi
        # 同时设置全局变量
        CONFIGURED_SSH_PORT="$new_port"

        draw_msgbox "成功" "SSH 配置完成！\n\n新端口: ${new_port}\n\n请确保防火墙已开放此端口"
        return 0
    else
        draw_msgbox "错误" "SSH 重启失败，请检查配置"
        return 1
    fi
}

# 切换 ssh.socket 到 ssh.service
switch_ssh_to_service() {
    log_info "切换 SSH 到 service 模式..."

    # 停止并禁用 socket
    systemctl stop ssh.socket 2>/dev/null || true
    systemctl disable ssh.socket 2>/dev/null || true

    # 启用并启动 service
    systemctl enable ssh.service 2>/dev/null || true
}

# 修改 sshd_config
modify_sshd_config() {
    local port="$1"
    local options="$2"

    log_info "修改 sshd_config..."

    local config_file="/etc/ssh/sshd_config"

    # 端口 (支持 #Port, ##Port 等注释格式)
    if grep -qE "^[# ]*Port " "$config_file"; then
        sed -i -E "s/^[# ]*Port .*/Port ${port}/" "$config_file"
    else
        echo "Port ${port}" >> "$config_file"
    fi

    # 安全选项
    # PermitRootLogin
    if [[ "$options" == *"PermitRootLogin"* ]]; then
        if grep -qE "^[# ]*PermitRootLogin " "$config_file"; then
            sed -i -E "s/^[# ]*PermitRootLogin .*/PermitRootLogin prohibit-password/" "$config_file"
        else
            echo "PermitRootLogin prohibit-password" >> "$config_file"
        fi
    fi

    # PubkeyAuthentication
    if [[ "$options" == *"PubkeyAuth"* ]]; then
        if grep -qE "^[# ]*PubkeyAuthentication " "$config_file"; then
            sed -i -E "s/^[# ]*PubkeyAuthentication .*/PubkeyAuthentication yes/" "$config_file"
        else
            echo "PubkeyAuthentication yes" >> "$config_file"
        fi
    fi

    # PasswordAuthentication
    if [[ "$options" == *"PasswordAuth"* ]]; then
        if grep -qE "^[# ]*PasswordAuthentication " "$config_file"; then
            sed -i -E "s/^[# ]*PasswordAuthentication .*/PasswordAuthentication yes/" "$config_file"
        else
            echo "PasswordAuthentication yes" >> "$config_file"
        fi
    else
        if grep -qE "^[# ]*PasswordAuthentication " "$config_file"; then
            sed -i -E "s/^[# ]*PasswordAuthentication .*/PasswordAuthentication no/" "$config_file"
        else
            echo "PasswordAuthentication no" >> "$config_file"
        fi
    fi

    # PermitEmptyPasswords
    if [[ "$options" == *"DisableEmptyPasswords"* ]]; then
        if grep -qE "^[# ]*PermitEmptyPasswords " "$config_file"; then
            sed -i -E "s/^[# ]*PermitEmptyPasswords .*/PermitEmptyPasswords no/" "$config_file"
        else
            echo "PermitEmptyPasswords no" >> "$config_file"
        fi
    fi

    # MaxAuthTries
    if [[ "$options" == *"LimitAuthTries"* ]]; then
        if grep -qE "^[# ]*MaxAuthTries " "$config_file"; then
            sed -i -E "s/^[# ]*MaxAuthTries .*/MaxAuthTries 3/" "$config_file"
        else
            echo "MaxAuthTries 3" >> "$config_file"
        fi
    fi

    log_info "sshd_config 已更新"
}

# 生成 SSH 密钥对
generate_ssh_key() {
    local key_type
    local key_file

    # 选择密钥类型
    local key_options=(
        "ed25519" "Ed25519 (推荐，更安全更快)" "ON"
        "rsa" "RSA 4096 位 (兼容性好)" "OFF"
    )

    key_type=$(whiptail --title "密钥类型" --radiolist \
        "选择 SSH 密钥类型:" \
        12 50 3 "${key_options[@]}" 3>&1 1>&2 2>&3)

    if [[ $? -ne 0 ]]; then
        key_type="ed25519"
    fi

    local ssh_dir="${HOME}/.ssh"
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"

    if [[ "$key_type" == "ed25519" ]]; then
        key_file="${ssh_dir}/id_ed25519"
        if [[ ! -f "$key_file" ]]; then
            log_info "生成 Ed25519 密钥..."
            ssh-keygen -t ed25519 -f "$key_file" -N "" -C "${USER}@$(hostname)"
        else
            log_info "Ed25519 密钥已存在"
        fi
    else
        key_file="${ssh_dir}/id_rsa"
        if [[ ! -f "$key_file" ]]; then
            log_info "生成 RSA 4096 位密钥..."
            ssh-keygen -t rsa -b 4096 -f "$key_file" -N "" -C "${USER}@$(hostname)"
        else
            log_info "RSA 密钥已存在"
        fi
    fi

    # 显示公钥
    if [[ -f "${key_file}.pub" ]]; then
        local pubkey
        pubkey=$(cat "${key_file}.pub")
        draw_msgbox "SSH 公钥" "您的 SSH 公钥:\n\n${pubkey}\n\n请将此公钥添加到目标服务器的 ~/.ssh/authorized_keys"
    fi
}

# 重启 SSH 服务
restart_ssh() {
    log_info "重启 SSH 服务..."

    # 验证配置
    if ! sshd -t; then
        log_error "sshd_config 配置有误"
        return 1
    fi

    # 重启服务
    if systemctl restart ssh.service; then
        log_info "SSH 服务已重启"
        return 0
    else
        log_error "SSH 服务重启失败"
        return 1
    fi
}
