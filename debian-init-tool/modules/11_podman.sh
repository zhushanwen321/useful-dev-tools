#!/bin/bash
# Podman 配置模块
# 安装和配置 Podman 容器工具

configure_podman() {
    log_info "开始配置 Podman..."

    # 检查是否已安装
    if command_exists podman; then
        local current_version
        current_version=$(podman --version 2>/dev/null || echo "未知")
        if draw_yesno "Podman 已安装" "检测到 ${current_version}\n\n是否重新配置 Podman？"; then
            configure_podman_options
        else
            return 0
        fi
    else
        if ! draw_yesno "安装 Podman" "是否安装 Podman？\n\nPodman 是 Docker 的无守护进程替代品，更加安全。"; then
            return 0
        fi
        install_podman
    fi
}

# 安装 Podman
install_podman() {
    log_info "安装 Podman..."

    # 选择要安装的组件
    local component_options=(
        "podman" "Podman 核心组件" "ON"
        "podman-compose" "Podman Compose (兼容 docker-compose)" "ON"
        "buildah" "Buildah (容器构建工具)" "OFF"
        "skopeo" "Skopeo (镜像传输工具)" "OFF"
    )

    local selected
    selected=$(whiptail --title "组件选择" --checklist \
        "选择要安装的 Podman 组件:" \
        14 50 5 "${component_options[@]}" 3>&1 1>&2 2>&3 | tr -d '"')

    if [[ $? -ne 0 ]] || [[ -z "$selected" ]]; then
        selected="podman podman-compose"
    fi

    # 安装核心包
    apt-get update

    if [[ "$selected" == *"podman"* ]]; then
        apt-get install -y podman
    fi

    if [[ "$selected" == *"buildah"* ]]; then
        apt-get install -y buildah
    fi

    if [[ "$selected" == *"skopeo"* ]]; then
        apt-get install -y skopeo
    fi

    if [[ "$selected" == *"podman-compose"* ]]; then
        install_podman_compose
    fi

    # 验证安装
    if command_exists podman; then
        configure_podman_options
        draw_msgbox "成功" "Podman 安装成功！\n\n版本: $(podman --version)"
        return 0
    else
        draw_msgbox "错误" "Podman 安装失败"
        return 1
    fi
}

# 安装 podman-compose
install_podman_compose() {
    log_info "安装 podman-compose..."

    # 方法 1: pip 安装
    if command_exists pip3; then
        pip3 install podman-compose 2>/dev/null && return 0
    fi

    # 方法 2: pipx 安装
    if command_exists pipx; then
        pipx install podman-compose 2>/dev/null && return 0
    fi

    # 方法 3: 下载脚本
    local script_url="https://raw.githubusercontent.com/containers/podman-compose/main/podman_compose.py"
    local install_path="/usr/local/bin/podman-compose"

    if curl -sL "$script_url" -o "$install_path" 2>/dev/null; then
        chmod +x "$install_path"
        log_info "podman-compose 安装成功"
        return 0
    fi

    log_warn "podman-compose 安装失败"
    return 1
}

# 配置 Podman 选项
configure_podman_options() {
    log_info "配置 Podman 选项..."

    local config_options=(
        "mirror" "配置镜像加速器" "ON"
        "docker_alias" "配置 docker 命令别名" "OFF"
        "rootless" "配置无 root 模式" "OFF"
        "socket" "启用 Podman Socket" "OFF"
    )

    local selected
    selected=$(whiptail --title "Podman 配置" --checklist \
        "选择要配置的项目:" \
        14 45 5 "${config_options[@]}" 3>&1 1>&2 2>&3 | tr -d '"')

    if [[ $? -ne 0 ]]; then
        return 0
    fi

    # 镜像加速器
    if [[ "$selected" == *"mirror"* ]]; then
        configure_podman_mirror
    fi

    # Docker 别名
    if [[ "$selected" == *"docker_alias"* ]]; then
        configure_docker_alias
    fi

    # 无 root 模式
    if [[ "$selected" == *"rootless"* ]]; then
        configure_rootless_podman
    fi

    # Socket
    if [[ "$selected" == *"socket"* ]]; then
        enable_podman_socket
    fi
}

# 配置镜像加速器
configure_podman_mirror() {
    log_info "配置 Podman 镜像加速器..."

    local mirror_options=(
        "163" "网易镜像 (hub-mirror.c.163.com)" "ON"
        "ustc" "中科大镜像 (docker.mirrors.ustc.edu.cn)" "OFF"
        "custom" "自定义镜像地址" "OFF"
    )

    local mirror_choice
    mirror_choice=$(whiptail --title "镜像加速器" --radiolist \
        "选择 Podman 镜像加速器:" \
        12 50 4 "${mirror_options[@]}" 3>&1 1>&2 2>&3)

    local mirror_url=""
    case "$mirror_choice" in
        163)
            mirror_url="https://hub-mirror.c.163.com"
            ;;
        ustc)
            mirror_url="https://docker.mirrors.ustc.edu.cn"
            ;;
        custom)
            mirror_url=$(draw_inputbox "镜像地址" "请输入镜像加速器地址:")
            ;;
    esac

    if [[ -z "$mirror_url" ]]; then
        return 0
    fi

    # 创建配置目录
    mkdir -p /etc/containers

    # 备份现有配置
    if [[ -f "/etc/containers/registries.conf" ]]; then
        backup_file "/etc/containers/registries.conf" "Podman 镜像配置"
    fi

    # 生成或更新 registries.conf
    cat > /etc/containers/registries.conf << EOF
# 由 debian-init-tool 自动生成
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')

[registries.search]
registries = ['docker.io', 'quay.io', 'registry.access.redhat.com']

[registries.insecure]
registries = []

[[registry]]
prefix = "docker.io"
location = "docker.io"

[[registry.mirror]]
location = "${mirror_url}"

[[registry]]
prefix = "quay.io"
location = "quay.io"

[[registry.mirror]]
location = "${mirror_url}"
EOF

    log_info "Podman 镜像加速器已配置"
}

# 配置 Docker 别名
configure_docker_alias() {
    log_info "配置 docker 命令别名..."

    # 创建 docker 别名脚本
    mkdir -p /etc/profile.d

    cat > /etc/profile.d/docker-podman-alias.sh << 'EOF'
# Docker 兼容别名 (使用 Podman)
if command -v podman &>/dev/null; then
    alias docker=podman
    alias docker-compose=podman-compose
fi
EOF

    log_info "Docker 别名已配置 (添加到 /etc/profile.d/)"
}

# 配置无 root 模式
configure_rootless_podman() {
    log_info "配置 Podman 无 root 模式..."

    # 选择用户
    local users=()
    while IFS=: read -r username _ uid _ _ _ _; do
        if [[ $uid -ge 1000 ]] && [[ $uid -lt 65534 ]]; then
            users+=("$username" "")
        fi
    done < /etc/passwd

    if [[ ${#users[@]} -eq 0 ]]; then
        draw_msgbox "提示" "没有找到普通用户"
        return 1
    fi

    local target_user
    target_user=$(whiptail --title "选择用户" --menu \
        "选择要配置无 root 模式的用户:" \
        15 40 8 "${users[@]}" 3>&1 1>&2 2>&3)

    if [[ -z "$target_user" ]]; then
        return 1
    fi

    # 安装依赖
    apt-get install -y slirp4netns fuse-overlayfs

    # 配置 subuid/subgid
    if ! grep -q "^${target_user}:" /etc/subuid; then
        echo "${target_user}:100000:65536" >> /etc/subuid
    fi

    if ! grep -q "^${target_user}:" /etc/subgid; then
        echo "${target_user}:100000:65536" >> /etc/subgid
    fi

    # 启用 cgroup v2 (如果需要)
    if [[ ! -f /sys/fs/cgroup/cgroup.controllers ]]; then
        log_warn "系统可能需要启用 cgroup v2 才能使用无 root 模式"
    fi

    log_info "Podman 无 root 模式已为用户 $target_user 配置"

    draw_msgbox "配置完成" "无 root 模式已配置\n\n用户 $target_user 需要执行以下命令启用:\n\npodman system migrate"
}

# 启用 Podman Socket
enable_podman_socket() {
    log_info "启用 Podman Socket..."

    # 选择用户
    local socket_options=(
        "system" "系统级 Socket (root)" "ON"
        "user" "用户级 Socket" "OFF"
    )

    local choice
    choice=$(whiptail --title "Socket 类型" --radiolist \
        "选择要启用的 Socket 类型:" \
        10 45 3 "${socket_options[@]}" 3>&1 1>&2 2>&3)

    case "$choice" in
        system)
            systemctl enable --now podman.socket
            draw_msgbox "成功" "系统级 Podman Socket 已启用\n\nSocket 路径: /run/podman/podman.sock"
            ;;
        user)
            local users=()
            while IFS=: read -r username _ uid _ _ _ _; do
                if [[ $uid -ge 1000 ]] && [[ $uid -lt 65534 ]]; then
                    users+=("$username" "")
                fi
            done < /etc/passwd

            local target_user
            target_user=$(whiptail --title "选择用户" --menu \
                "选择要启用 Socket 的用户:" \
                15 40 8 "${users[@]}" 3>&1 1>&2 2>&3)

            if [[ -n "$target_user" ]]; then
                loginctl enable-linger "$target_user"
                draw_msgbox "成功" "用户级 Podman Socket 已启用\n\n用户需要执行:\nsystemctl --user enable --now podman.socket"
            fi
            ;;
    esac
}

# 显示 Podman 状态
show_podman_status() {
    local info="Podman 状态:\n\n"

    info+="版本: $(podman --version 2>/dev/null || echo '未安装')\n"

    if command_exists podman; then
        info+="镜像数量: $(podman images -q 2>/dev/null | wc -l)\n"
        info+="容器数量: $(podman ps -q 2>/dev/null | wc -l)\n"

        if command_exists podman-compose; then
            info+="Compose: 已安装\n"
        fi

        if command_exists buildah; then
            info+="Buildah: 已安装\n"
        fi

        if command_exists skopeo; then
            info+="Skopeo: 已安装\n"
        fi
    fi

    draw_msgbox "Podman 信息" "$info"
}
