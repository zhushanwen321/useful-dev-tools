#!/bin/bash
# pi coding agent 配置模块
# 安装 @mariozechner/pi-coding-agent

configure_pi() {
    log_info "开始配置 pi coding agent..."

    # 检查是否已安装
    if command_exists pi; then
        local current_version
        current_version=$(pi --version 2>/dev/null || echo "未知")
        if draw_yesno "pi 已安装" "检测到 ${current_version}\n\n是否重新安装/升级？"; then
            # 通过 npm 重新安装
            install_pi
        else
            show_pi_status
            return 0
        fi
    else
        if ! draw_yesno "安装 pi" "是否安装 pi coding agent？\n\npi 是一个 AI 编码助手，提供代码补全、重构、解释等功能。\n\n需要 Node.js (将自动安装缺失的依赖)。"; then
            return 0
        fi
        install_pi
    fi
}

# 确保 Node.js/npm 可用
ensure_nodejs() {
    if ! command_exists node || ! command_exists npm; then
        log_info "Node.js/npm 未安装，准备安装..."

        if ! draw_yesno "安装 Node.js" "pi 需要 Node.js 和 npm\n\n是否自动安装 Node.js LTS 版本？"; then
            return 1
        fi

        # 调用 nodejs 模块的安装函数
        if declare -f configure_nodejs &>/dev/null; then
            # 先加载 nodejs 模块
            local nodejs_module
            nodejs_module="$(_get_script_dir)/../modules/12_nodejs.sh"
            if [[ -f "$nodejs_module" ]]; then
                source "$nodejs_module"
            fi

            if declare -f install_nodejs &>/dev/null; then
                install_nodejs
            else
                # 手动安装
                install_nodejs_standalone
            fi
        else
            install_nodejs_standalone
        fi

        # 验证安装
        if ! command_exists node || ! command_exists npm; then
            log_error "Node.js 安装失败"
            return 1
        fi
    fi
    return 0
}

# 独立安装 Node.js（当 nodejs 模块不可用时）
install_nodejs_standalone() {
    log_info "独立安装 Node.js..."

    apt-get update
    apt-get install -y ca-certificates curl gnupg

    mkdir -p /etc/apt/keyrings

    # 下载 NodeSource GPG 密钥
    curl -fsSL "https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key" \
        | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg 2>/dev/null

    if [[ ! -f /etc/apt/keyrings/nodesource.gpg ]]; then
        log_error "无法下载 NodeSource GPG 密钥"
        return 1
    fi

    local arch
    arch=$(dpkg --print-architecture)
    echo "deb [arch=${arch} signed-by=/etc/apt/keyrings/nodesource.gpg] \
https://deb.nodesource.com/node_22.x nodistro main" \
        | tee /etc/apt/sources.list.d/nodesource.list > /dev/null

    apt-get update
    apt-get install -y nodejs

    if command_exists node && command_exists npm; then
        log_info "Node.js 安装成功: $(node -v), npm $(npm -v)"
        return 0
    fi
    return 1
}

# 安装 pi coding agent
install_pi() {
    # 确保 Node.js/npm 可用
    if ! ensure_nodejs; then
        draw_msgbox "错误" "Node.js/npm 不可用，无法安装 pi"
        return 1
    fi

    log_info "安装 pi coding agent..."

    # 查找普通用户（以用户身份安装，避免 sudo）
    local target_user=""
    while IFS=: read -r username _ uid _ _ _ _; do
        if [[ $uid -ge 1000 ]] && [[ $uid -lt 65534 ]]; then
            target_user="$username"
            break
        fi
    done < /etc/passwd

    local install_cmd
    local install_desc

    if [[ -n "$target_user" ]] && draw_yesno "用户选择" "是否以用户 ${target_user} 身份安装 pi？\n\n选择「是」安装到用户目录 (~/.npm-global)\n选择「否」安装到系统路径 (npm -g)"; then
        # 配置用户级 npm prefix（如果尚未配置）
        local home_dir
        home_dir=$(getent passwd "$target_user" | cut -d: -f6)

        # 检查是否已配置 prefix
        local current_prefix
        current_prefix=$(su - "$target_user" -c "npm config get prefix" 2>/dev/null)

        if [[ "$current_prefix" != "${home_dir}/.npm-global" ]]; then
            su - "$target_user" -c "mkdir -p ~/.npm-global"
            su - "$target_user" -c "npm config set prefix ~/.npm-global"

            # 添加到 PATH
            local profile="${home_dir}/.profile"
            local npm_path_line='export PATH="$HOME/.npm-global/bin:$PATH"'
            if ! grep -qF '.npm-global/bin' "$profile" 2>/dev/null; then
                echo "" >> "$profile"
                echo "# npm 全局模块" >> "$profile"
                echo "$npm_path_line" >> "$profile"
            fi
            local zshrc="${home_dir}/.zshrc"
            if [[ -f "$zshrc" ]] && ! grep -qF '.npm-global/bin' "$zshrc" 2>/dev/null; then
                echo "" >> "$zshrc"
                echo "# npm 全局模块" >> "$zshrc"
                echo "$npm_path_line" >> "$zshrc"
                chown "$target_user:$target_user" "$zshrc"
            fi
            chown -R "$target_user:$target_user" "${home_dir}/.npm-global"
        fi

        # 以用户身份安装
        su - "$target_user" -c "npm install -g @mariozechner/pi-coding-agent"
        install_desc="用户 ${target_user}"
    else
        # 系统级安装
        npm install -g @mariozechner/pi-coding-agent
        install_desc="系统路径"
    fi

    # 验证安装
    if command_exists pi; then
        local pi_version
        pi_version=$(pi --version 2>/dev/null)
        log_info "pi coding agent 安装成功 (${install_desc}): ${pi_version}"
        draw_msgbox "成功" "pi coding agent 安装完成！\n\n${pi_version}\n安装位置: ${install_desc}"

        # 可选：配置自动完成
        configure_pi_completion

        return 0
    else
        # 检查是否安装在用户目录但 root 看不到
        if [[ -n "$target_user" ]]; then
            local user_pi_path
            user_pi_path=$(su - "$target_user" -c "which pi 2>/dev/null || npm config get prefix 2>/dev/null")
            if [[ -n "$user_pi_path" ]]; then
                log_info "pi 已为用户 ${target_user} 安装 (${user_pi_path})"
                draw_msgbox "成功" "pi coding agent 已为用户 ${target_user} 安装\n\n路径: ${user_pi_path}/bin/pi\n用户重新登录后即可使用"
                return 0
            fi
        fi

        draw_msgbox "错误" "pi coding agent 安装失败"
        return 1
    fi
}

# 配置 pi 自动完成
configure_pi_completion() {
    if ! draw_yesno "pi 自动完成" "是否为所有普通用户配置 pi 命令自动完成？"; then
        return 0
    fi

    while IFS=: read -r username _ uid _ _ _ shell; do
        if [[ $uid -ge 1000 ]] && [[ $uid -lt 65534 ]]; then
            local rc_file=""
            case "$(basename "$shell")" in
                bash) rc_file="${home_dir}/.bashrc" ;;
                zsh)  rc_file="${home_dir}/.zshrc" ;;
                *)    continue ;;
            esac

            local home_dir
            home_dir=$(getent passwd "$username" | cut -d: -f6)
            rc_file="${home_dir}/${rc_file##*/}"

            if [[ -f "$rc_file" ]] && ! grep -qF 'pi completion' "$rc_file" 2>/dev/null; then
                echo "" >> "$rc_file"
                echo "# pi coding agent 自动完成" >> "$rc_file"
                echo 'eval "$(pi completion)"' >> "$rc_file"
                chown "$username:$username" "$rc_file"
                log_info "已为 $username ($(basename "$shell")) 配置 pi 自动完成"
            fi
        fi
    done < /etc/passwd

    draw_msgbox "提示" "pi 自动完成已配置，重新登录后生效"
}

# 获取脚本目录
_get_script_dir() {
    echo "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
}

# 显示 pi 状态
show_pi_status() {
    local info="pi coding agent 状态:\n\n"

    if command_exists pi; then
        info+="系统版本: $(pi --version 2>/dev/null)\n"
        info+="路径: $(which pi 2>/dev/null)\n"

        # 检查各用户的安装情况
        info+="\n用户安装情况:\n"
        while IFS=: read -r username _ uid _ _ _ _; do
            if [[ $uid -ge 1000 ]] && [[ $uid -lt 65534 ]]; then
                local user_pi
                user_pi=$(su - "$username" -c "which pi 2>/dev/null || echo '未安装'" 2>/dev/null)
                info+="  ${username}: ${user_pi}\n"
            fi
        done < /etc/passwd
    else
        info+="未安装\n"
        # 检查 npm 是否可用
        if command_exists npm; then
            info+="npm 已就绪，可安装\n"
        else
            info+="需要 Node.js/npm\n"
        fi
    fi

    draw_msgbox "pi 信息" "$info"
}
