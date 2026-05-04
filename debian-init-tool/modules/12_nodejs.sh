#!/bin/bash
# Node.js / npm 配置模块
# 通过 NodeSource PPA 安装指定版本的 Node.js (含 npm)

# Node.js 版本选项
NODE_VERSION_OPTIONS=(
    "22" "Node.js 22.x LTS (推荐)" "ON"
    "20" "Node.js 20.x LTS"        "OFF"
    "18" "Node.js 18.x LTS"        "OFF"
    "23" "Node.js 23.x Current"    "OFF"
)

configure_nodejs() {
    log_info "开始配置 Node.js..."

    # 检查是否已安装
    if command_exists node; then
        local current_version
        current_version=$(node -v 2>/dev/null || echo "未知")
        if draw_yesno "Node.js 已安装" "检测到 ${current_version}\n\n是否重新安装/切换版本？"; then
            uninstall_nodejs
            install_nodejs
        else
            show_nodejs_status
            return 0
        fi
    else
        if ! draw_yesno "安装 Node.js" "是否通过 NodeSource 安装 Node.js 和 npm？\n\nNode.js 是 JavaScript 运行时，npm 是包管理器。"; then
            return 0
        fi
        install_nodejs
    fi
}

# 卸载已有 Node.js
uninstall_nodejs() {
    log_info "清理已有 Node.js 安装..."

    # 移除 NodeSource 仓库
    rm -f /etc/apt/sources.list.d/nodesource.list
    rm -f /etc/apt/keyrings/nodesource.gpg
    rm -f /etc/apt/keyrings/nodesource

    apt-get remove -y nodejs 2>/dev/null || true
    apt-get autoremove -y 2>/dev/null || true

    log_info "清理完成"
}

# 安装 Node.js
install_nodejs() {
    # 选择版本
    local node_version
    node_version=$(whiptail --title "Node.js 版本" --radiolist \
        "选择要安装的 Node.js 版本:" \
        14 55 4 "${NODE_VERSION_OPTIONS[@]}" 3>&1 1>&2 2>&3)

    if [[ $? -ne 0 ]] || [[ -z "$node_version" ]]; then
        node_version="22"
    fi

    log_info "将安装 Node.js ${node_version}.x"

    # 安装依赖
    apt-get update
    apt-get install -y ca-certificates curl gnupg

    # 1. 创建 keyrings 目录
    mkdir -p /etc/apt/keyrings

    # 2. 下载 NodeSource GPG 密钥
    log_info "下载 NodeSource GPG 密钥..."
    curl -fsSL "https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key" \
        | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg 2>/dev/null

    if [[ ! -f /etc/apt/keyrings/nodesource.gpg ]]; then
        draw_msgbox "错误" "无法下载 NodeSource GPG 密钥，请检查网络连接"
        return 1
    fi

    # 3. 添加 NodeSource APT 仓库
    local arch
    arch=$(dpkg --print-architecture)
    echo "deb [arch=${arch} signed-by=/etc/apt/keyrings/nodesource.gpg] \
https://deb.nodesource.com/node_${node_version}.x nodistro main" \
        | tee /etc/apt/sources.list.d/nodesource.list > /dev/null

    # 4. 更新索引并安装
    log_info "更新软件包索引..."
    apt-get update

    log_info "安装 Node.js ${node_version}.x..."
    apt-get install -y nodejs

    # 5. 验证安装
    if command_exists node && command_exists npm; then
        local node_v npm_v
        node_v=$(node -v)
        npm_v=$(npm -v)

        log_info "Node.js 安装成功: node ${node_v}, npm ${npm_v}"
        draw_msgbox "成功" "Node.js 安装完成！\n\nnode: ${node_v}\nnpm:  ${npm_v}"

        # 可选：配置 npm 全局模块路径（避免 sudo）
        configure_npm_global_prefix

        # 可选：安装 pi-coding-agent
        install_pi_coding_agent
    else
        draw_msgbox "错误" "Node.js 安装失败"
        return 1
    fi
}

# 配置 npm 全局模块路径（可选，避免 npm install -g 需要 sudo）
configure_npm_global_prefix() {
    # 查找普通用户
    local target_user=""
    while IFS=: read -r username _ uid _ _ home _; do
        if [[ $uid -ge 1000 ]] && [[ $uid -lt 65534 ]]; then
            target_user="$username"
            break
        fi
    done < /etc/passwd

    [[ -z "$target_user" ]] && return 0

    local home_dir
    home_dir=$(getent passwd "$target_user" | cut -d: -f6)

    if draw_yesno "npm 全局配置" "是否为用户 ${target_user} 配置 npm 全局安装路径？\n\n配置后可免 sudo 执行 npm install -g\n路径: ${home_dir}/.npm-global"; then
        # 创建全局目录
        su - "$target_user" -c "mkdir -p ~/.npm-global"

        # 设置 npm prefix
        su - "$target_user" -c "npm config set prefix ~/.npm-global"

        # 写入 PATH 到 .profile (幂等)
        local profile="${home_dir}/.profile"
        local npm_path_line='export PATH="$HOME/.npm-global/bin:$PATH"'

        if ! grep -qF '.npm-global/bin' "$profile" 2>/dev/null; then
            echo "" >> "$profile"
            echo "# npm 全局模块" >> "$profile"
            echo "$npm_path_line" >> "$profile"
        fi

        # 同步到 .zshrc (如果存在且使用了 oh-my-zsh)
        local zshrc="${home_dir}/.zshrc"
        if [[ -f "$zshrc" ]] && ! grep -qF '.npm-global/bin' "$zshrc"; then
            echo "" >> "$zshrc"
            echo "# npm 全局模块" >> "$zshrc"
            echo "$npm_path_line" >> "$zshrc"
            chown "$target_user:$target_user" "$zshrc"
        fi

        chown "$target_user:$target_user" "$profile"
        chown -R "$target_user:$target_user" "${home_dir}/.npm-global"

        log_info "npm 全局路径已配置: ${home_dir}/.npm-global"
        draw_msgbox "提示" "用户 ${target_user} 需重新登录后生效\n\n或执行: source ~/.profile"
    fi
}

# 显示 Node.js 状态
show_nodejs_status() {
    local info="Node.js 状态:\n\n"

    if command_exists node; then
        info+="node: $(node -v 2>/dev/null)\n"
        info+="npm:  $(npm -v 2>/dev/null)\n"
        info+="npx:  $(npx --version 2>/dev/null)\n"
        info+="prefix: $(npm config get prefix 2>/dev/null)\n"
    else
        info+="未安装\n"
    fi

    draw_msgbox "Node.js 信息" "$info"
}
