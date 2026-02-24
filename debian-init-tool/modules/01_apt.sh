#!/bin/bash
# APT 源配置模块
# 配置 Debian APT 软件源

# 镜像源定义
declare -A MIRRORS=(
    ["aliyun"]="mirrors.aliyun.com"
    ["tsinghua"]="mirrors.tuna.tsinghua.edu.cn"
    ["ustc"]="mirrors.ustc.edu.cn"
    ["huawei"]="mirrors.huawei.com"
    ["tencent"]="mirrors.tencent.com"
    ["official"]="deb.debian.org"
)

# 仓库组件
declare -A COMPONENTS=(
    ["main"]="main"
    ["main_contrib"]="main contrib"
    ["main_contrib_nonfree"]="main contrib non-free non-free-firmware"
)

configure_apt() {
    log_info "开始配置 APT 源..."

    # 获取 Debian 版本信息
    source /etc/os-release
    local codename="${VERSION_CODENAME:-bookworm}"
    local debian_version="${VERSION_ID:-12}"

    # 选择镜像源
    local mirror
    mirror=$(select_mirror) || return 1

    # 选择组件
    local component
    component=$(select_components) || return 1

    # 确认配置
    local confirm_msg="将配置以下 APT 源:\n\n"
    confirm_msg+="镜像: ${mirror}\n"
    confirm_msg+="组件: ${COMPONENTS[$component]}\n"
    confirm_msg+="版本: ${codename}\n\n"
    confirm_msg+="是否继续？"

    if ! draw_yesno "确认配置" "$confirm_msg"; then
        log_info "用户取消配置"
        return 1
    fi

    # 备份原有配置
    backup_apt_sources

    # 生成新的 sources.list
    generate_sources_list "$mirror" "$codename" "$component"

    # 如果代理已配置，为 APT 配置代理
    if [[ -n "$PROXY_HOST" ]]; then
        configure_apt_proxy "$PROXY_HOST" "$PROXY_PORT"
    fi

    # 更新软件包列表
    if update_apt; then
        draw_msgbox "成功" "APT 源配置完成！\n\n镜像: ${mirror}"
        return 0
    else
        draw_msgbox "错误" "apt update 失败，正在恢复备份..."
        restore_apt_backup
        return 1
    fi
}

# 选择镜像源
select_mirror() {
    local options=(
        "aliyun" "阿里云镜像 (国内推荐)" "ON"
        "tsinghua" "清华大学镜像 (教育网推荐)" "OFF"
        "ustc" "中国科学技术大学镜像" "OFF"
        "huawei" "华为云镜像" "OFF"
        "tencent" "腾讯云镜像" "OFF"
        "official" "Debian 官方源 (国外推荐)" "OFF"
    )

    # 检查是否有保存的偏好
    local saved_mirror="${DEFAULT_MIRROR:-aliyun}"
    # 更新默认选中项
    for i in $(seq 0 3 ${#options[@]}); do
        if [[ "${options[$i]}" == "$saved_mirror" ]]; then
            options[$((i+2))]="ON"
        else
            options[$((i+2))]="OFF"
        fi
    done

    local result
    result=$(whiptail --title "选择镜像源" --radiolist \
        "请选择 APT 软件源镜像:" \
        20 60 8 "${options[@]}" 3>&1 1>&2 2>&3)

    if [[ $? -eq 0 ]]; then
        echo "$result"
        return 0
    else
        return 1
    fi
}

# 选择仓库组件
select_components() {
    local options=(
        "main_contrib_nonfree" "完整版 (main + contrib + non-free)" "ON"
        "main_contrib" "标准版 (main + contrib)" "OFF"
        "main" "纯净版 (仅 main)" "OFF"
    )

    local result
    result=$(whiptail --title "选择仓库组件" --radiolist \
        "请选择要启用的软件仓库组件:\n\nmain: 官方支持的自由软件\ncontrib: 依赖非自由软件的自由软件\nnon-free: 非自由软件" \
        18 65 5 "${options[@]}" 3>&1 1>&2 2>&3)

    if [[ $? -eq 0 ]]; then
        echo "$result"
        return 0
    else
        return 1
    fi
}

# 注意: backup_apt_sources 函数在 lib/backup.sh 中定义

# 生成 sources.list 文件
generate_sources_list() {
    local mirror_name="$1"
    local codename="$2"
    local component_key="$3"

    local mirror_url="${MIRRORS[$mirror_name]}"
    local components="${COMPONENTS[$component_key]}"

    log_info "生成 sources.list: ${mirror_url}, ${codename}, ${components}"

    # 主源文件
    cat > /etc/apt/sources.list << EOF
# 由 debian-init-tool 自动生成
# 镜像: ${mirror_name}
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')

# Debian ${codename} 主仓库
deb http://${mirror_url}/debian ${codename} ${components}
deb-src http://${mirror_url}/debian ${codename} ${components}

# Debian ${codename} 更新
deb http://${mirror_url}/debian ${codename}-updates ${components}
deb-src http://${mirror_url}/debian ${codename}-updates ${components}

# 安全更新
deb http://security.debian.org/debian-security ${codename}-security ${components}
deb-src http://security.debian.org/debian-security ${codename}-security ${components}
EOF

    # Debian 12+ 使用新的安全源格式
    if [[ "$codename" == "bookworm" || "$codename" == "trixie" ]]; then
        sed -i "s|security.debian.org/debian-security|security.debian.org/debian-security|g" /etc/apt/sources.list
    fi

    log_info "sources.list 已更新"
}

# 更新 APT
update_apt() {
    log_info "正在更新软件包列表..."

    # 显示进度
    {
        apt-get update 2>&1 | while read -r line; do
            log_debug "$line"
        done
    }

    if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
        log_info "软件包列表更新成功"
        return 0
    else
        log_error "软件包列表更新失败"
        return 1
    fi
}

# 恢复 APT 备份
restore_apt_backup() {
    local backup_dir="${CURRENT_BACKUP_DIR}"
    local sources_backup="${backup_dir}/etc/apt/sources.list"*

    # 找到最新的备份
    local latest_backup
    latest_backup=$(ls -t ${sources_backup} 2>/dev/null | head -1)

    if [[ -n "$latest_backup" && -f "$latest_backup" ]]; then
        cp "$latest_backup" /etc/apt/sources.list
        log_info "已恢复 APT 源配置"
    fi
}

# 配置 APT 代理
configure_apt_proxy_if_needed() {
    if [[ -n "$PROXY_HOST" ]]; then
        configure_apt_proxy "$PROXY_HOST" "$PROXY_PORT"
    fi
}

# 安装基础工具
install_base_packages() {
    local packages=(
        "curl"
        "wget"
        "git"
        "vim"
        "htop"
        "tmux"
        "tree"
        "lsof"
        "net-tools"
        "ca-certificates"
        "gnupg"
        "lsb-release"
    )

    log_info "安装基础工具包..."

    if draw_yesno "基础工具" "是否安装常用的基础工具包？\n\n包括: curl, wget, git, vim, htop 等"; then
        install_packages "${packages[@]}"
    fi
}
