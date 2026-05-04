#!/bin/bash
# GitHub CLI (gh) 配置模块
# 通过 GitHub 官方 APT 仓库安装 gh

configure_gh() {
    log_info "开始配置 GitHub CLI..."

    # 检查是否已安装
    if command_exists gh; then
        local current_version
        current_version=$(gh --version 2>/dev/null | head -n1 || echo "未知")
        if draw_yesno "GitHub CLI 已安装" "检测到 ${current_version}\n\n是否重新安装/升级？"; then
            uninstall_gh
            install_gh
        else
            show_gh_status
            return 0
        fi
    else
        if ! draw_yesno "安装 GitHub CLI" "是否安装 GitHub CLI (gh)？\n\ngh 是 GitHub 官方命令行工具，可用于管理仓库、Issue、PR 等。"; then
            return 0
        fi
        install_gh
    fi
}

# 卸载已有 GitHub CLI
uninstall_gh() {
    log_info "清理已有 GitHub CLI 安装..."

    # 移除软件包
    apt-get remove -y gh 2>/dev/null || true
    apt-get autoremove -y 2>/dev/null || true

    # 移除仓库配置和密钥
    rm -f /etc/apt/sources.list.d/github-cli.list
    rm -f /etc/apt/keyrings/githubcli-archive-keyring.gpg

    log_info "清理完成"
}

# 安装 GitHub CLI
install_gh() {
    log_info "安装 GitHub CLI..."

    # 选择安装方式
    local install_options=(
        "official" "GitHub 官方 APT 仓库 (推荐)" "ON"
        "debian"   "Debian 官方仓库 (版本较旧)" "OFF"
    )

    local method
    method=$(whiptail --title "安装方式" --radiolist \
        "选择 GitHub CLI 安装方式:" \
        10 50 3 "${install_options[@]}" 3>&1 1>&2 2>&3)

    if [[ $? -ne 0 ]] || [[ -z "$method" ]]; then
        method="official"
    fi

    case "$method" in
        official)
            install_gh_official
            ;;
        debian)
            install_gh_debian
            ;;
    esac

    if [[ $? -ne 0 ]]; then
        draw_msgbox "错误" "GitHub CLI 安装失败"
        return 1
    fi

    # 验证安装
    if command_exists gh; then
        local gh_version
        gh_version=$(gh --version 2>/dev/null | head -n1)
        log_info "GitHub CLI 安装成功: ${gh_version}"
        draw_msgbox "成功" "GitHub CLI 安装完成！\n\n${gh_version}"

        # 可选：配置 gh 自动完成并登录
        configure_gh_completion
        prompt_gh_auth

        return 0
    else
        draw_msgbox "错误" "GitHub CLI 安装验证失败"
        return 1
    fi
}

# 从 GitHub 官方 APT 仓库安装
install_gh_official() {
    log_info "从 GitHub 官方 APT 仓库安装..."

    # 安装依赖
    apt-get update
    apt-get install -y ca-certificates curl wget gpg

    # 创建 keyrings 目录
    mkdir -p -m 755 /etc/apt/keyrings

    # 下载 GitHub CLI GPG 密钥
    log_info "下载 GitHub CLI GPG 密钥..."
    local gpg_keyring="/etc/apt/keyrings/githubcli-archive-keyring.gpg"
    local tmp_file
    tmp_file=$(mktemp)

    # 尝试官方源
    if wget -nv -O "$tmp_file" "https://cli.github.com/packages/githubcli-archive-keyring.gpg" 2>/dev/null; then
        cat "$tmp_file" | tee "$gpg_keyring" > /dev/null
        chmod go+r "$gpg_keyring"
        rm -f "$tmp_file"
    else
        rm -f "$tmp_file"
        log_error "无法下载 GitHub CLI GPG 密钥"
        return 1
    fi

    # 添加 APT 仓库
    local arch
    arch=$(dpkg --print-architecture)
    echo "deb [arch=${arch} signed-by=${gpg_keyring}] https://cli.github.com/packages stable main" \
        | tee /etc/apt/sources.list.d/github-cli.list > /dev/null

    # 更新索引并安装
    log_info "更新软件包索引..."
    apt-get update

    log_info "安装 gh..."
    apt-get install -y gh

    log_info "GitHub CLI 官方仓库安装完成"
}

# 从 Debian 官方仓库安装
install_gh_debian() {
    log_info "从 Debian 官方仓库安装..."

    apt-get update
    apt-get install -y gh

    log_info "GitHub CLI Debian 包安装完成"
}

# 配置 gh 自动完成
configure_gh_completion() {
    if ! draw_yesno "gh 自动完成" "是否为所有普通用户配置 gh 命令自动完成？"; then
        return 0
    fi

    # 为用户配置自动完成
    while IFS=: read -r username _ uid _ _ _ shell; do
        if [[ $uid -ge 1000 ]] && [[ $uid -lt 65534 ]]; then
            local home_dir
            home_dir=$(getent passwd "$username" | cut -d: -f6)

            # 检测 shell 类型
            case "$(basename "$shell")" in
                bash)
                    local bashrc="${home_dir}/.bashrc"
                    if [[ -f "$bashrc" ]] && ! grep -qF 'gh completion' "$bashrc" 2>/dev/null; then
                        echo "" >> "$bashrc"
                        echo "# GitHub CLI 自动完成" >> "$bashrc"
                        echo 'eval "$(gh completion -s bash)"' >> "$bashrc"
                        chown "$username:$username" "$bashrc"
                        log_info "已为 $username (bash) 配置 gh 自动完成"
                    fi
                    ;;
                zsh)
                    local zshrc="${home_dir}/.zshrc"
                    if [[ -f "$zshrc" ]] && ! grep -qF 'gh completion' "$zshrc" 2>/dev/null; then
                        echo "" >> "$zshrc"
                        echo "# GitHub CLI 自动完成" >> "$zshrc"
                        echo 'eval "$(gh completion -s zsh)"' >> "$zshrc"
                        chown "$username:$username" "$zshrc"
                        log_info "已为 $username (zsh) 配置 gh 自动完成"
                    fi
                    ;;
            esac
        fi
    done < /etc/passwd

    draw_msgbox "提示" "gh 自动完成已配置，重新登录后生效"
}

# 提示 gh 认证登录
prompt_gh_auth() {
    if draw_yesno "GitHub 认证" "是否现在登录 GitHub？\n\n如果跳过，后续可执行 gh auth login 手动登录。"; then
        log_info "启动 gh auth login..."
        gh auth login
    fi
}

# 显示 GitHub CLI 状态
show_gh_status() {
    local info="GitHub CLI 状态:\n\n"

    if command_exists gh; then
        info+="版本: $(gh --version 2>/dev/null | head -n1)\n"
        info+="安装来源: $(dpkg -S "$(which gh)" 2>/dev/null | head -n1 || echo '未知')\n"

        # 检查认证状态
        if gh auth status 2>/dev/null; then
            local gh_user
            gh_user=$(gh api user --jq '.login' 2>/dev/null || echo "未知")
            info+="认证状态: 已登录 (${gh_user})\n"
        else
            info+="认证状态: 未登录\n"
        fi
    else
        info+="未安装\n"
    fi

    draw_msgbox "GitHub CLI 信息" "$info"
}
