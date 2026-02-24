#!/bin/bash
# 用户管理模块
# 创建和配置用户账户

configure_user() {
    log_info "开始用户管理..."

    # 选择操作
    local action_options=(
        "create" "创建新用户" ""
        "modify" "修改现有用户" ""
        "sudo" "配置 sudo 权限" ""
        "list" "查看用户列表" ""
    )

    local action
    action=$(whiptail --title "用户管理" --menu "选择要执行的操作:" \
        14 45 5 "${action_options[@]}" 3>&1 1>&2 2>&3)

    if [[ $? -ne 0 ]]; then
        return 1
    fi

    case "$action" in
        create)
            create_new_user
            ;;
        modify)
            modify_user
            ;;
        sudo)
            configure_sudo
            ;;
        list)
            list_users
            ;;
    esac
}

# 创建新用户
create_new_user() {
    log_info "创建新用户..."

    # 用户名
    local username
    username=$(draw_inputbox "用户名" "请输入新用户名 (小写字母开头):")

    if [[ $? -ne 0 ]] || [[ -z "$username" ]]; then
        return 1
    fi

    # 验证用户名
    if ! validate_username "$username"; then
        local result=$?
        if [[ $result -eq 2 ]] && [[ $(id "$username" 2>/dev/null) ]]; then
            if ! draw_yesno "用户存在" "用户 $username 已存在，是否修改该用户？"; then
                return 1
            fi
            modify_specific_user "$username"
            return $?
        fi
        return 1
    fi

    # 认证方式
    local auth_options=(
        "password" "密码认证" "ON"
        "key" "SSH 密钥认证" "OFF"
        "both" "密码 + 密钥 (推荐)" "OFF"
    )

    local auth_method
    auth_method=$(whiptail --title "认证方式" --radiolist \
        "选择用户认证方式:" \
        12 45 4 "${auth_options[@]}" 3>&1 1>&2 2>&3)

    if [[ $? -ne 0 ]]; then
        auth_method="both"
    fi

    # 密码
    local password=""
    local confirm_password=""

    if [[ "$auth_method" == "password" ]] || [[ "$auth_method" == "both" ]]; then
        while true; do
            password=$(draw_passwordbox "密码" "请输入用户密码:")
            if [[ $? -ne 0 ]]; then
                return 1
            fi

            if [[ -z "$password" ]]; then
                draw_msgbox "错误" "密码不能为空"
                continue
            fi

            confirm_password=$(draw_passwordbox "确认密码" "请再次输入密码:")
            if [[ $? -ne 0 ]]; then
                return 1
            fi

            if [[ "$password" != "$confirm_password" ]]; then
                draw_msgbox "错误" "两次输入的密码不匹配"
                continue
            fi

            break
        done
    fi

    # SSH 公钥
    local ssh_pubkey=""
    if [[ "$auth_method" == "key" ]] || [[ "$auth_method" == "both" ]]; then
        ssh_pubkey=$(draw_inputbox "SSH 公钥" "请粘贴 SSH 公钥 (以 ssh-rsa 或 ssh-ed25519 开头):")

        if [[ $? -ne 0 ]] || [[ -z "$ssh_pubkey" ]]; then
            if [[ "$auth_method" == "key" ]]; then
                draw_msgbox "错误" "SSH 密钥认证需要提供公钥"
                return 1
            fi
        else
            if ! validate_ssh_pubkey "$ssh_pubkey"; then
                draw_msgbox "错误" "SSH 公钥格式无效"
                return 1
            fi
        fi
    fi

    # sudo 权限
    local with_sudo=false
    if draw_yesno "Sudo 权限" "是否为用户 $username 授予 sudo 权限？"; then
        with_sudo=true
    fi

    # 附加组
    local groups=""
    if draw_yesno "用户组" "是否将用户加入附加组？\n\n常用组: docker, sudo, www-data"; then
        groups=$(draw_inputbox "用户组" "请输入组名 (多个用逗号分隔):" "docker")
    fi

    # 确认创建
    local confirm_msg="将创建以下用户:\n\n"
    confirm_msg+="用户名: ${username}\n"
    confirm_msg+="认证方式: ${auth_method}\n"
    $with_sudo && confirm_msg+="Sudo 权限: 是\n"
    [[ -n "$groups" ]] && confirm_msg+="附加组: ${groups}\n"
    confirm_msg+="\n是否继续？"

    if ! draw_yesno "确认创建" "$confirm_msg"; then
        return 1
    fi

    # 创建用户
    if create_user "$username" "$password" "$ssh_pubkey" "$with_sudo" "$groups"; then
        draw_msgbox "成功" "用户 $username 创建成功！"
        return 0
    else
        draw_msgbox "错误" "用户创建失败"
        return 1
    fi
}

# 创建用户
create_user() {
    local username="$1"
    local password="$2"
    local ssh_pubkey="$3"
    local with_sudo="$4"
    local groups="$5"

    log_info "创建用户: $username"

    # 创建用户
    useradd -m -s /bin/bash "$username"

    if [[ $? -ne 0 ]]; then
        log_error "创建用户失败"
        return 1
    fi

    # 设置密码
    if [[ -n "$password" ]]; then
        echo "${username}:${password}" | chpasswd
    fi

    # 配置 SSH 公钥
    if [[ -n "$ssh_pubkey" ]]; then
        local ssh_dir="/home/${username}/.ssh"
        mkdir -p "$ssh_dir"
        echo "$ssh_pubkey" > "${ssh_dir}/authorized_keys"
        chmod 700 "$ssh_dir"
        chmod 600 "${ssh_dir}/authorized_keys"
        chown -R "${username}:${username}" "$ssh_dir"
    fi

    # sudo 权限
    if $with_sudo; then
        usermod -aG sudo "$username"

        # 创建 sudoers 文件 (可选，更细粒度的控制)
        cat > "/etc/sudoers.d/${username}" << EOF
# 允许 ${username} 使用 sudo
${username} ALL=(ALL:ALL) ALL
EOF
        chmod 440 "/etc/sudoers.d/${username}"
    fi

    # 附加组
    if [[ -n "$groups" ]]; then
        IFS=',' read -ra group_array <<< "$groups"
        for group in "${group_array[@]}"; do
            group=$(echo "$group" | tr -d ' ')
            if [[ -n "$group" ]]; then
                # 确保组存在
                getent group "$group" &>/dev/null || groupadd "$group" 2>/dev/null
                usermod -aG "$group" "$username"
            fi
        done
    fi

    log_info "用户 $username 创建完成"
    return 0
}

# 修改现有用户
modify_user() {
    log_info "修改用户..."

    # 列出普通用户
    local users=()
    while IFS=: read -r username _ uid _ _ home _; do
        if [[ $uid -ge 1000 ]] && [[ $uid -lt 65534 ]] && [[ "$home" == /home/* ]]; then
            users+=("$username" "UID: $uid")
        fi
    done < /etc/passwd

    if [[ ${#users[@]} -eq 0 ]]; then
        draw_msgbox "提示" "没有找到普通用户"
        return 1
    fi

    local username
    username=$(whiptail --title "选择用户" --menu "选择要修改的用户:" \
        15 40 8 "${users[@]}" 3>&1 1>&2 2>&3)

    if [[ $? -ne 0 ]]; then
        return 1
    fi

    modify_specific_user "$username"
}

# 修改指定用户
modify_specific_user() {
    local username="$1"

    local modify_options=(
        "password" "修改密码" ""
        "shell" "修改 Shell" ""
        "groups" "修改用户组" ""
        "sudo" "配置 Sudo 权限" ""
        "delete" "删除用户" ""
    )

    local action
    action=$(whiptail --title "修改用户 $username" --menu "选择操作:" \
        14 40 6 "${modify_options[@]}" 3>&1 1>&2 2>&3)

    if [[ $? -ne 0 ]]; then
        return 1
    fi

    case "$action" in
        password)
            local password
            password=$(draw_passwordbox "新密码" "请输入新密码:")
            if [[ -n "$password" ]]; then
                echo "${username}:${password}" | chpasswd
                draw_msgbox "成功" "密码已更新"
            fi
            ;;
        shell)
            local shell
            shell=$(whiptail --title "选择 Shell" --radiolist "为 $username 选择默认 Shell:" \
                12 40 3 \
                "/bin/bash" "Bash" "ON" \
                "/bin/zsh" "Zsh" "OFF" \
                "/bin/sh" "Sh" "OFF" 3>&1 1>&2 2>&3)
            if [[ -n "$shell" ]]; then
                chsh -s "$shell" "$username"
                draw_msgbox "成功" "Shell 已更新为 $shell"
            fi
            ;;
        groups)
            local groups
            groups=$(draw_inputbox "用户组" "输入要添加的组 (逗号分隔):")
            if [[ -n "$groups" ]]; then
                IFS=',' read -ra group_array <<< "$groups"
                for group in "${group_array[@]}"; do
                    group=$(echo "$group" | tr -d ' ')
                    getent group "$group" &>/dev/null || groupadd "$group" 2>/dev/null
                    usermod -aG "$group" "$username"
                done
                draw_msgbox "成功" "用户组已更新"
            fi
            ;;
        sudo)
            if draw_yesno "Sudo 权限" "是否授予 $username sudo 权限？"; then
                usermod -aG sudo "$username"
                draw_msgbox "成功" "Sudo 权限已授予"
            else
                gpasswd -d "$username" sudo 2>/dev/null
                rm -f "/etc/sudoers.d/${username}"
                draw_msgbox "成功" "Sudo 权限已移除"
            fi
            ;;
        delete)
            if draw_yesno "确认删除" "确定要删除用户 $username 吗？\n\n此操作不可恢复！"; then
                userdel -r "$username" 2>/dev/null || userdel "$username"
                rm -f "/etc/sudoers.d/${username}"
                draw_msgbox "成功" "用户已删除"
            fi
            ;;
    esac
}

# 配置 sudo
configure_sudo() {
    log_info "配置 sudo..."

    # 安装 sudo
    if ! command_exists sudo; then
        apt-get install -y sudo
    fi

    local sudo_options=(
        "add" "添加用户到 sudo 组" ""
        "remove" "从 sudo 组移除用户" ""
        "nopasswd" "配置免密 sudo" ""
        "edit" "编辑 sudoers 文件" ""
    )

    local action
    action=$(whiptail --title "Sudo 配置" --menu "选择操作:" \
        14 45 5 "${sudo_options[@]}" 3>&1 1>&2 2>&3)

    if [[ $? -ne 0 ]]; then
        return 1
    fi

    case "$action" in
        add|remove)
            local users=()
            while IFS=: read -r username _ uid _ _ _ _; do
                if [[ $uid -ge 1000 ]] && [[ $uid -lt 65534 ]]; then
                    users+=("$username" "")
                fi
            done < /etc/passwd

            local username
            username=$(whiptail --title "选择用户" --menu "选择用户:" \
                15 40 8 "${users[@]}" 3>&1 1>&2 2>&3)

            if [[ $? -eq 0 ]]; then
                if [[ "$action" == "add" ]]; then
                    usermod -aG sudo "$username"
                    draw_msgbox "成功" "$username 已添加到 sudo 组"
                else
                    gpasswd -d "$username" sudo 2>/dev/null
                    draw_msgbox "成功" "$username 已从 sudo 组移除"
                fi
            fi
            ;;
        nopasswd)
            local users=()
            while IFS=: read -r username _ uid _ _ _ _; do
                if [[ $uid -ge 1000 ]] && [[ $uid -lt 65534 ]]; then
                    users+=("$username" "")
                fi
            done < /etc/passwd

            local username
            username=$(whiptail --title "选择用户" --menu "选择要配置免密 sudo 的用户:" \
                15 40 8 "${users[@]}" 3>&1 1>&2 2>&3)

            if [[ $? -eq 0 ]]; then
                cat > "/etc/sudoers.d/${username}-nopasswd" << EOF
${username} ALL=(ALL) NOPASSWD: ALL
EOF
                chmod 440 "/etc/sudoers.d/${username}-nopasswd"
                draw_msgbox "成功" "$username 已配置免密 sudo"
            fi
            ;;
        edit)
            export VISUAL=nano
            visudo
            ;;
    esac
}

# 列出用户
list_users() {
    local user_list=""
    user_list+="系统用户:\n\n"

    while IFS=: read -r username _ uid gid _ home shell; do
        if [[ $uid -ge 1000 ]] && [[ $uid -lt 65534 ]]; then
            local groups
            groups=$(groups "$username" | cut -d: -f2)
            user_list+="${username} (UID: $uid)\n"
            user_list+="  Shell: $shell\n"
            user_list+="  Home: $home\n"
            user_list+="  Groups: ${groups}\n\n"
        fi
    done < /etc/passwd

    draw_msgbox "用户列表" "$user_list"
}
