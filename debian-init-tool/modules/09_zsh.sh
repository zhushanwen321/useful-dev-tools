#!/bin/bash
# Zsh 配置模块
# 安装和配置 Zsh、Oh My Zsh 和插件

# Oh My Zsh 安装路径
OH_MY_ZSH_DIR="${OH_MY_ZSH_DIR:-/usr/share/oh-my-zsh}"
ZSH_CUSTOM="${ZSH_CUSTOM:-${OH_MY_ZSH_DIR}/custom}"

configure_zsh() {
    log_info "开始配置 Zsh..."

    # 1. 安装 Zsh
    if ! install_zsh; then
        return 1
    fi

    # 2. 选择目标用户
    local target_user
    target_user=$(select_zsh_target_user)

    if [[ -z "$target_user" ]]; then
        return 1
    fi

    local home_dir
    home_dir=$(getent passwd "$target_user" | cut -d: -f6)

    # 3. 安装 Oh My Zsh
    if ! install_oh_my_zsh "$target_user" "$home_dir"; then
        return 1
    fi

    # 4. 选择主题
    local theme
    theme=$(select_zsh_theme)

    # 5. 选择插件
    local plugins
    plugins=$(select_zsh_plugins)

    # 6. 确认配置
    local confirm_msg="将为用户 $target_user 配置 Zsh:\n\n"
    confirm_msg+="主题: ${theme}\n"
    confirm_msg+="插件: ${plugins:-无}\n\n"
    confirm_msg+="是否继续？"

    if ! draw_yesno "确认配置" "$confirm_msg"; then
        return 1
    fi

    # 7. 安装主题
    if ! install_zsh_theme "$theme" "$target_user" "$home_dir"; then
        log_warn "主题安装可能存在问题"
    fi

    # 8. 安装插件
    if [[ -n "$plugins" ]]; then
        install_zsh_plugins "$plugins" "$target_user" "$home_dir"
    fi

    # 9. 生成 .zshrc
    generate_zshrc "$target_user" "$home_dir" "$theme" "$plugins"

    # 10. 设置为默认 shell
    if draw_yesno "默认 Shell" "是否将 Zsh 设置为用户 $target_user 的默认 Shell？"; then
        chsh -s /bin/zsh "$target_user"
    fi

    # 11. 添加代理函数
    add_zsh_proxy_functions "$home_dir"

    # 设置权限
    chown -R "${target_user}:${target_user}" "${home_dir}/.zshrc" "${home_dir}/.oh-my-zsh" 2>/dev/null

    draw_msgbox "成功" "Zsh 配置完成！\n\n主题: ${theme}\n插件: ${plugins:-无}\n\n请用户 $target_user 重新登录或执行:\nzsh"

    return 0
}

# 安装 Zsh
install_zsh() {
    if command_exists zsh; then
        log_info "Zsh 已安装"
        return 0
    fi

    log_info "安装 Zsh..."
    apt-get update
    apt-get install -y zsh git curl

    if command_exists zsh; then
        log_info "Zsh 安装成功"
        return 0
    else
        log_error "Zsh 安装失败"
        return 1
    fi
}

# 选择目标用户
select_zsh_target_user() {
    local users=()

    while IFS=: read -r username _ uid _ _ _ _; do
        if [[ $uid -ge 1000 ]] && [[ $uid -lt 65534 ]]; then
            users+=("$username" "普通用户")
        fi
    done < /etc/passwd

    if [[ ${#users[@]} -eq 0 ]]; then
        draw_msgbox "错误" "没有找到普通用户，请先创建用户"
        return 1
    fi

    whiptail --title "选择用户" --menu "选择要配置 Zsh 的用户:" \
        15 40 8 "${users[@]}" 3>&1 1>&2 2>&3
}

# 安装 Oh My Zsh
install_oh_my_zsh() {
    local user="$1"
    local home_dir="$2"

    local omz_dir="${home_dir}/.oh-my-zsh"

    # 检查是否已安装
    if [[ -d "$omz_dir" ]]; then
        log_info "Oh My Zsh 已安装"
        return 0
    fi

    log_info "安装 Oh My Zsh..."

    # 从 Gitee 安装 (国内更快)
    local install_url="https://gitee.com/mirrors/oh-my-zsh/raw/master/tools/install.sh"

    # 备用 GitHub 源
    local fallback_url="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"

    # 尝试下载并执行安装脚本
    local install_script
    install_script=$(download_with_retry "$install_url" "" 3 true)

    if [[ -z "$install_script" ]]; then
        install_script=$(download_with_retry "$fallback_url" "" 3 true)
    fi

    if [[ -n "$install_script" ]]; then
        # 使用 RUNZSH=no 防止自动启动 zsh
        # 使用 CHSH=no 防止自动修改 shell
        RUNZSH=no CHSH=no sh -c "$install_script" "" --unattended

        if [[ $? -eq 0 ]] && [[ -d "$omz_dir" ]]; then
            log_info "Oh My Zsh 安装成功"
            chown -R "${user}:${user}" "$omz_dir"
            return 0
        fi
    fi

    # 手动安装
    log_info "使用手动方式安装 Oh My Zsh..."
    if manual_install_omz "$user" "$home_dir"; then
        return 0
    fi

    draw_msgbox "错误" "Oh My Zsh 安装失败"
    return 1
}

# 手动安装 Oh My Zsh
manual_install_omz() {
    local user="$1"
    local home_dir="$2"
    local omz_dir="${home_dir}/.oh-my-zsh"

    # 克隆仓库
    local repo_url="https://gitee.com/mirrors/oh-my-zsh.git"
    local fallback_url="https://github.com/ohmyzsh/ohmyzsh.git"

    if ! git clone --depth=1 "$repo_url" "$omz_dir" 2>/dev/null; then
        if ! git clone --depth=1 "$fallback_url" "$omz_dir" 2>/dev/null; then
            return 1
        fi
    fi

    # 复制模板配置
    if [[ -f "${omz_dir}/templates/zshrc.zsh-template" ]]; then
        cp "${omz_dir}/templates/zshrc.zsh-template" "${home_dir}/.zshrc"
    fi

    chown -R "${user}:${user}" "$omz_dir" "${home_dir}/.zshrc"
    return 0
}

# 选择主题
select_zsh_theme() {
    local themes=(
        "powerlevel10k" "Powerlevel10k (推荐，功能丰富)" "ON"
        "agnoster" "Agnoster (经典箭头主题)" "OFF"
        "robbyrussell" "Robbyrussell (Oh My Zsh 默认)" "OFF"
        "simple" "Simple (简洁)" "OFF"
    )

    local result
    result=$(whiptail --title "选择主题" --radiolist \
        "选择 Zsh 主题:" \
        14 55 5 "${themes[@]}" 3>&1 1>&2 2>&3)

    echo "${result:-robbyrussell}"
}

# 选择插件
select_zsh_plugins() {
    local builtin_plugins=(
        "git" "Git 别名和补全" "ON"
        "sudo" "双击 ESC 添加 sudo" "ON"
        "colored-man-pages" "彩色 man 页面" "ON"
        "colorize" "语法高亮 cat" "OFF"
        "copypath" "复制当前路径" "OFF"
        "copyfile" "复制文件内容" "OFF"
        "dirhistory" "目录历史导航" "OFF"
        "dotenv" "自动加载 .env" "OFF"
        "history" "历史命令别名" "OFF"
        "web-search" "命令行搜索" "OFF"
    )

    local third_party_plugins=(
        "zsh-autosuggestions" "命令自动建议" "ON"
        "zsh-syntax-highlighting" "命令语法高亮" "ON"
        "zsh-completions" "扩展补全" "OFF"
        "zsh-autopair" "括号自动配对" "OFF"
    )

    local all_plugins=("${builtin_plugins[@]}" "${third_party_plugins[@]}")

    local result
    result=$(whiptail --title "选择插件" --checklist \
        "选择要安装的 Zsh 插件:" \
        22 60 12 "${all_plugins[@]}" 3>&1 1>&2 2>&3 | tr -d '"')

    echo "$result"
}

# 安装主题
install_zsh_theme() {
    local theme="$1"
    local user="$2"
    local home_dir="$3"

    local omz_dir="${home_dir}/.oh-my-zsh"
    local custom_themes="${omz_dir}/custom/themes"

    mkdir -p "$custom_themes"

    case "$theme" in
        powerlevel10k)
            local p10k_dir="${custom_themes}/powerlevel10k"
            if [[ ! -d "$p10k_dir" ]]; then
                log_info "安装 Powerlevel10k 主题..."

                # 优先从 Gitee 克隆
                if ! git clone --depth=1 "https://gitee.com/romkatv/powerlevel10k.git" "$p10k_dir" 2>/dev/null; then
                    git clone --depth=1 "https://github.com/romkatv/powerlevel10k.git" "$p10k_dir" 2>/dev/null || true
                fi
            fi
            chown -R "${user}:${user}" "$p10k_dir" 2>/dev/null
            ;;
        agnoster|robbyrussell|simple)
            # 内置主题，无需安装
            ;;
    esac

    log_info "主题 $theme 已就绪"
}

# 安装插件
install_zsh_plugins() {
    local plugins="$1"
    local user="$2"
    local home_dir="$3"

    local omz_dir="${home_dir}/.oh-my-zsh"
    local custom_plugins="${omz_dir}/custom/plugins"

    mkdir -p "$custom_plugins"

    # 插件仓库映射
    declare -A plugin_repos=(
        ["zsh-autosuggestions"]="zsh-users/zsh-autosuggestions"
        ["zsh-syntax-highlighting"]="zsh-users/zsh-syntax-highlighting"
        ["zsh-completions"]="zsh-users/zsh-completions"
        ["zsh-autopair"]="hlissner/zsh-autopair"
    )

    for plugin in $plugins; do
        # 跳过内置插件
        if [[ -d "${omz_dir}/plugins/${plugin}" ]]; then
            log_debug "插件 $plugin 是内置插件，跳过"
            continue
        fi

        # 检查是否需要从外部安装
        if [[ -n "${plugin_repos[$plugin]}" ]]; then
            local plugin_dir="${custom_plugins}/${plugin}"

            if [[ -d "$plugin_dir" ]]; then
                log_debug "插件 $plugin 已安装，更新..."
                cd "$plugin_dir" && git pull 2>/dev/null
            else
                log_info "安装插件: $plugin..."

                local repo="${plugin_repos[$plugin]}"
                local gitee_url="https://gitee.com/${repo}.git"
                local github_url="https://github.com/${repo}.git"

                # 优先尝试 Gitee
                if ! git clone --depth=1 "$gitee_url" "$plugin_dir" 2>/dev/null; then
                    # 失败则尝试 GitHub
                    if ! git clone --depth=1 "$github_url" "$plugin_dir" 2>/dev/null; then
                        log_warn "插件 $plugin 安装失败"
                        continue
                    fi
                fi
            fi

            chown -R "${user}:${user}" "$plugin_dir" 2>/dev/null
        fi
    done

    log_info "插件安装完成"
}

# 生成 .zshrc
generate_zshrc() {
    local user="$1"
    local home_dir="$2"
    local theme="$3"
    local plugins="$4"

    local zshrc_file="${home_dir}/.zshrc"

    # 备份现有配置
    [[ -f "$zshrc_file" ]] && backup_file "$zshrc_file" "Zsh 配置"

    # 转换主题名称
    local theme_config="$theme"
    if [[ "$theme" == "powerlevel10k" ]]; then
        theme_config="powerlevel10k/powerlevel10k"
    fi

    # 格式化插件列表
    local plugins_config=""
    if [[ -n "$plugins" ]]; then
        plugins_config=$(echo "$plugins" | tr ' ' '\n' | sort -u | tr '\n' ' ' | sed 's/ $//')
    fi

    cat > "$zshrc_file" << EOF
# 由 debian-init-tool 自动生成
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')

# Oh My Zsh 路径
export ZSH="${home_dir}/.oh-my-zsh"

# 主题
ZSH_THEME="${theme_config}"

# 插件
plugins=(${plugins_config})

# Oh My Zsh 配置
source \$ZSH/oh-my-zsh.sh

# 用户配置
export LANG=en_US.UTF-8
export EDITOR=vim

# 历史配置
HISTSIZE=10000
SAVEHIST=10000
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE

# 自动补全
autoload -Uz compinit && compinit

# 别名
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias cls='clear'
alias ..='cd ..'
alias ...='cd ../..'

EOF

    # 添加代理函数
    local proxy_host="${PROXY_HOST:-127.0.0.1}"
    local proxy_port="${PROXY_PORT:-7890}"

    cat >> "$zshrc_file" << EOF

# 代理函数
proxy() {
    export http_proxy="http://${proxy_host}:${proxy_port}"
    export https_proxy="http://${proxy_host}:${proxy_port}"
    export all_proxy="socks5://${proxy_host}:${proxy_port}"
    export no_proxy="localhost,127.0.0.1,::1,.local"
    echo "代理已启用: ${proxy_host}:${proxy_port}"
}

noproxy() {
    unset http_proxy https_proxy all_proxy no_proxy
    echo "代理已关闭"
}

# IP 查询
myip() {
    curl -s --connect-timeout 5 ifconfig.me
}

EOF

    log_info ".zshrc 已生成"
}

# 添加代理函数到 zshrc
add_zsh_proxy_functions() {
    local home_dir="$1"
    local zshrc="${home_dir}/.zshrc"

    if [[ ! -f "$zshrc" ]]; then
        return
    fi

    # 检查是否已存在
    if grep -q "function proxy" "$zshrc" 2>/dev/null; then
        return
    fi

    # 代理配置已在 generate_zshrc 中添加
    log_debug "代理函数已配置"
}
