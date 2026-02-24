#!/bin/bash
# Docker 配置模块
# 安装和配置 Docker 及 Docker Compose

configure_docker() {
    log_info "开始配置 Docker..."

    # 检查是否已安装
    if command_exists docker; then
        local current_version
        current_version=$(docker --version 2>/dev/null || echo "未知")
        if draw_yesno "Docker 已安装" "检测到 ${current_version}\n\n是否重新配置 Docker？"; then
            configure_docker_options
        else
            return 0
        fi
    else
        if ! draw_yesno "安装 Docker" "是否安装 Docker？\n\nDocker 是流行的容器化平台。"; then
            return 0
        fi
        install_docker
    fi
}

# 安装 Docker
install_docker() {
    log_info "安装 Docker..."

    # 安装方式选择
    local install_options=(
        "official" "Docker 官方仓库 (推荐)" "ON"
        "script" "get.docker.com 脚本 (快速)" "OFF"
        "debian" "Debian 仓库 (旧版本)" "OFF"
    )

    local method
    method=$(whiptail --title "安装方式" --radiolist \
        "选择 Docker 安装方式:" \
        12 50 4 "${install_options[@]}" 3>&1 1>&2 2>&3)

    if [[ $? -ne 0 ]]; then
        method="official"
    fi

    case "$method" in
        official)
            install_docker_official
            ;;
        script)
            install_docker_script
            ;;
        debian)
            install_docker_debian
            ;;
    esac

    if [[ $? -ne 0 ]]; then
        draw_msgbox "错误" "Docker 安装失败"
        return 1
    fi

    # 配置 Docker
    configure_docker_options

    # 添加用户到 docker 组
    add_users_to_docker_group

    # 验证安装
    if docker run --rm hello-world &>/dev/null; then
        draw_msgbox "成功" "Docker 安装成功！\n\n版本: $(docker --version)"
        return 0
    else
        draw_msgbox "警告" "Docker 已安装，但测试运行失败\n\n请检查 Docker 服务状态"
        return 1
    fi
}

# 从官方仓库安装
install_docker_official() {
    log_info "从官方仓库安装 Docker..."

    # 安装依赖
    apt-get update
    apt-get install -y ca-certificates curl gnupg lsb-release

    # 添加 Docker GPG 密钥
    mkdir -p /etc/apt/keyrings

    # 使用国内镜像加速
    local key_url="https://mirrors.aliyun.com/docker-ce/linux/debian/gpg"
    curl -fsSL "$key_url" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null

    if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
        # 备用官方源
        curl -fsSL "https://download.docker.com/linux/debian/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    fi

    # 获取 Debian 版本
    source /etc/os-release
    local codename="${VERSION_CODENAME:-bookworm}"

    # 添加仓库
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://mirrors.aliyun.com/docker-ce/linux/debian \
        ${codename} stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    # 安装 Docker
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # 启动服务
    systemctl enable --now docker

    log_info "Docker 官方仓库安装完成"
}

# 使用脚本安装
install_docker_script() {
    log_info "使用脚本安装 Docker..."

    local script_url="https://get.docker.com"
    local mirror_url="https://get.daocloud.io/docker"

    # 尝试国内镜像
    if curl -fsSL "$mirror_url" | sh; then
        log_info "Docker 脚本安装完成 (国内镜像)"
        return 0
    fi

    # 备用官方脚本
    if curl -fsSL "$script_url" | sh; then
        log_info "Docker 脚本安装完成"
        return 0
    fi

    return 1
}

# 从 Debian 仓库安装
install_docker_debian() {
    log_info "从 Debian 仓库安装 Docker..."

    apt-get update
    apt-get install -y docker.io docker-compose

    systemctl enable --now docker

    log_info "Docker Debian 包安装完成"
}

# 配置 Docker 选项
configure_docker_options() {
    log_info "配置 Docker 选项..."

    # 选择配置项
    local config_options=(
        "mirror" "配置镜像加速器" "ON"
        "log" "配置日志限制" "ON"
        "user" "添加用户到 docker 组" "ON"
        "compose" "安装 Docker Compose" "OFF"
    )

    local selected
    selected=$(whiptail --title "Docker 配置" --checklist \
        "选择要配置的项目:" \
        14 45 5 "${config_options[@]}" 3>&1 1>&2 2>&3 | tr -d '"')

    if [[ $? -ne 0 ]] || [[ -z "$selected" ]]; then
        return 0
    fi

    # 备份配置
    [[ -f "/etc/docker/daemon.json" ]] && backup_file "/etc/docker/daemon.json" "Docker 配置"

    local daemon_json="{"
    local need_comma=false

    # 镜像加速器
    if [[ "$selected" == *"mirror"* ]]; then
        local mirror_options=(
            "163" "网易镜像 (hub-mirror.c.163.com)" "ON"
            "aliyun" "阿里云镜像 (<你的ID>.mirror.aliyuncs.com)" "OFF"
            "ustc" "中科大镜像 (docker.mirrors.ustc.edu.cn)" "OFF"
            "custom" "自定义镜像地址" "OFF"
        )

        local mirror_choice
        mirror_choice=$(whiptail --title "镜像加速器" --radiolist \
            "选择 Docker 镜像加速器:" \
            14 55 5 "${mirror_options[@]}" 3>&1 1>&2 2>&3)

        local mirror_url=""
        case "$mirror_choice" in
            163)
                mirror_url="https://hub-mirror.c.163.com"
                ;;
            aliyun)
                local aliyun_id
                aliyun_id=$(draw_inputbox "阿里云 ID" "请输入您的阿里云加速器 ID:")
                if [[ -n "$aliyun_id" ]]; then
                    mirror_url="https://${aliyun_id}.mirror.aliyuncs.com"
                fi
                ;;
            ustc)
                mirror_url="https://docker.mirrors.ustc.edu.cn"
                ;;
            custom)
                mirror_url=$(draw_inputbox "镜像地址" "请输入镜像加速器地址:")
                ;;
        esac

        if [[ -n "$mirror_url" ]]; then
            daemon_json+='"registry-mirrors": ["'"$mirror_url"'"]'
            need_comma=true
        fi
    fi

    # 日志配置
    if [[ "$selected" == *"log"* ]]; then
        local log_max_size
        log_max_size=$(draw_inputbox "日志大小限制" "请输入单个容器日志最大大小:" "100m")

        if [[ -n "$log_max_size" ]]; then
            if $need_comma; then
                daemon_json+=", "
            fi
            daemon_json+='"log-driver": "json-file", "log-opts": {"max-size": "'"$log_max_size"'", "max-file": "3"}'
            need_comma=true
        fi
    fi

    daemon_json+="}"

    # 写入配置
    if [[ "$daemon_json" != "{}" ]]; then
        mkdir -p /etc/docker
        echo "$daemon_json" | jq . > /etc/docker/daemon.json 2>/dev/null || echo "$daemon_json" > /etc/docker/daemon.json

        # 重启 Docker
        systemctl restart docker
        log_info "Docker 配置已更新"
    fi

    # 添加用户到 docker 组
    if [[ "$selected" == *"user"* ]]; then
        add_users_to_docker_group
    fi

    # 安装 Docker Compose
    if [[ "$selected" == *"compose"* ]]; then
        install_docker_compose_standalone
    fi
}

# 添加用户到 docker 组
add_users_to_docker_group() {
    log_info "添加用户到 docker 组..."

    # 确保 docker 组存在
    getent group docker &>/dev/null || groupadd docker

    # 列出普通用户
    local users=()
    while IFS=: read -r username _ uid _ _ _ _; do
        if [[ $uid -ge 1000 ]] && [[ $uid -lt 65534 ]]; then
            # 检查是否已在 docker 组
            if ! groups "$username" | grep -q '\bdocker\b'; then
                users+=("$username" "添加到 docker 组")
            fi
        fi
    done < /etc/passwd

    if [[ ${#users[@]} -eq 0 ]]; then
        log_info "没有需要添加的用户"
        return 0
    fi

    local selected_users
    selected_users=$(whiptail --title "选择用户" --checklist \
        "选择要添加到 docker 组的用户:" \
        15 45 6 "${users[@]}" 3>&1 1>&2 2>&3 | tr -d '"')

    for user in $selected_users; do
        usermod -aG docker "$user"
        log_info "用户 $user 已添加到 docker 组"
    done

    draw_msgbox "提示" "用户需要重新登录才能生效 docker 组权限"
}

# 安装独立版 Docker Compose
install_docker_compose_standalone() {
    log_info "安装 Docker Compose..."

    # Docker Compose 现在作为 Docker 插件安装
    # 但也提供独立版本

    local compose_version
    compose_version=$(curl -sL "https://api.github.com/repos/docker/compose/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/' 2>/dev/null || echo "v2.23.0")

    local arch
    arch=$(dpkg --print-architecture)

    local download_url="https://github.com/docker/compose/releases/download/${compose_version}/docker-compose-linux-${arch}"

    # 尝试下载
    if curl -SL "$download_url" -o /usr/local/bin/docker-compose 2>/dev/null; then
        chmod +x /usr/local/bin/docker-compose
        log_info "Docker Compose 安装成功: $(docker-compose --version)"
    else
        log_warn "Docker Compose 独立版下载失败，请使用 docker compose 命令"
    fi
}

# 显示 Docker 状态
show_docker_status() {
    local info="Docker 状态:\n\n"

    info+="版本: $(docker --version 2>/dev/null || echo '未安装')\n"

    if command_exists docker; then
        info+="服务状态: $(systemctl is-active docker 2>/dev/null || echo '未知')\n"
        info+="镜像数量: $(docker images -q 2>/dev/null | wc -l)\n"
        info+="容器数量: $(docker ps -q 2>/dev/null | wc -l)\n"
    fi

    draw_msgbox "Docker 信息" "$info"
}
