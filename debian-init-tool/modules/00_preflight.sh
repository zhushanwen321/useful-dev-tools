#!/bin/bash
# 前置检查模块
# 执行系统环境检查和初始化

configure_preflight() {
    log_info "开始前置检查..."

    # 1. 检查 root 权限
    if ! check_root_silent; then
        draw_msgbox "权限错误" "此工具需要 root 权限运行\n\n请使用: sudo debian-init.sh"
        return 1
    fi

    # 2. 检测系统版本
    local debian_version
    debian_version=$(check_debian_version 2>/dev/null)

    if [[ -z "$debian_version" ]]; then
        draw_msgbox "系统错误" "无法检测系统版本"
        return 1
    fi

    # 3. 检查必要工具
    local required_tools=(whiptail curl wget)
    local missing_tools=()

    for tool in "${required_tools[@]}"; do
        if ! command_exists "$tool"; then
            missing_tools+=("$tool")
        fi
    done

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        draw_msgbox "安装依赖" "正在安装必要工具: ${missing_tools[*]}"
        apt-get update
        apt-get install -y "${missing_tools[@]}"
    fi

    # 4. 检测网络连接
    draw_msgbox "网络检测" "正在检测网络连接..."

    if ! test_network_connection; then
        if draw_yesno "网络问题" "无法连接到网络。\n\n是否需要配置代理？"; then
            interactive_configure_proxy || return 1
        else
            draw_msgbox "警告" "网络连接异常，部分功能可能无法正常工作"
        fi
    else
        draw_msgbox "网络正常" "网络连接正常"
    fi

    # 5. 创建工作目录
    mkdir -p /etc/debian-init-tool
    mkdir -p "$BACKUP_ROOT"
    mkdir -p "$(dirname "$LOG_FILE")"

    # 6. 加载或创建持久化配置
    load_persistent_config

    # 7. 显示系统信息
    show_system_info

    log_info "前置检查完成"
    return 0
}

# 静默检查 root
check_root_silent() {
    [[ $EUID -eq 0 ]]
}

# 注意: check_debian_version 函数在 lib/common.sh 中定义

# 加载持久化配置
load_persistent_config() {
    local config_file="/etc/debian-init-tool/config.conf"

    if [[ -f "$config_file" ]]; then
        log_info "加载持久化配置"
        source "$config_file"
    else
        log_info "创建默认配置"
        create_default_config
    fi
}

# 创建默认配置文件
create_default_config() {
    local config_file="/etc/debian-init-tool/config.conf"
    local config_dir
    config_dir=$(dirname "$config_file")

    mkdir -p "$config_dir"

    # 确定项目根目录 (SCRIPT_DIR 来自 lib/common.sh，指向 lib 目录)
    local project_root="${SCRIPT_DIR}/.."

    # 从默认配置复制
    if [[ -f "${project_root}/config/defaults.conf" ]]; then
        cp "${project_root}/config/defaults.conf" "$config_file"
    else
        # 创建最小配置
        cat > "$config_file" << 'EOF'
# Debian Init Tool 配置文件

[proxy]
host =
port = 7890
type = http

[defaults]
mirror_preference = aliyun
backup_dir = /var/backups/debian-init-tool

[completed]
EOF
    fi

    log_info "配置文件已创建: $config_file"
}

# 保存配置到持久化文件
save_config() {
    local key="$1"
    local value="$2"
    local config_file="/etc/debian-init-tool/config.conf"

    # 简单的 key=value 更新
    if grep -q "^${key}=" "$config_file" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$config_file"
    else
        echo "${key}=${value}" >> "$config_file"
    fi
}

# 标记模块完成
mark_module_completed() {
    local module="$1"
    local timestamp
    timestamp=$(date '+%Y-%m-%dT%H:%M:%S')
    save_config "completed_${module}" "$timestamp"
}

# 显示系统信息
show_system_info() {
    local info=""
    info+="系统: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2 || echo 'Unknown')\n"
    info+="内核: $(uname -r)\n"
    info+="CPU: $(nproc) 核心\n"
    info+="内存: $(free -h | awk '/^Mem:/{print $2}')\n"
    info+="磁盘: $(df -h / | awk 'NR==2{print $4}') 可用\n"
    info+="主机: $(hostname)\n"
    info+="IP: $(hostname -I | awk '{print $1}')"

    draw_msgbox "系统信息" "$info"
}

# 交互式配置向导
run_config_wizard() {
    if draw_yesno "配置向导" "是否运行配置向导？\n\n向导将帮助您配置代理、镜像源等基础设置。"; then
        # 代理配置
        interactive_configure_proxy

        # 镜像源偏好
        local mirror
        mirror=$(draw_radiolist "镜像源" "选择偏好的 APT 镜像源:" "aliyun" \
            "aliyun" "阿里云 (国内推荐)" \
            "tsinghua" "清华大学 (教育网推荐)" \
            "ustc" "中国科学技术大学" \
            "official" "Debian 官方 (国外推荐)") && \
            save_config "DEFAULT_MIRROR" "$mirror"

        draw_msgbox "配置完成" "基础配置已保存"
    fi
}
