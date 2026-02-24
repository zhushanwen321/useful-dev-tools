#!/bin/bash
# 时区设置模块
# 配置系统时区和 NTP 同步

configure_timezone() {
    log_info "开始配置时区..."

    # 获取当前时区
    local current_timezone
    current_timezone=$(cat /etc/timezone 2>/dev/null || timedatectl show --property=Timezone --value 2>/dev/null || echo "Unknown")

    # 常用时区选项
    local timezone_options=(
        "Asia/Shanghai" "中国标准时间 (UTC+8)" "ON"
        "Asia/Hong_Kong" "香港时间 (UTC+8)" "OFF"
        "Asia/Taipei" "台北时间 (UTC+8)" "OFF"
        "Asia/Tokyo" "日本标准时间 (UTC+9)" "OFF"
        "Asia/Singapore" "新加坡时间 (UTC+8)" "OFF"
        "America/New_York" "美国东部时间" "OFF"
        "America/Los_Angeles" "美国太平洋时间" "OFF"
        "Europe/London" "伦敦时间 (UTC+0/+1)" "OFF"
        "UTC" "协调世界时 (UTC)" "OFF"
    )

    # 选择时区
    local selected_timezone
    selected_timezone=$(whiptail --title "时区配置" --radiolist \
        "当前时区: ${current_timezone}\n\n请选择系统时区:" \
        20 60 10 "${timezone_options[@]}" 3>&1 1>&2 2>&3)

    if [[ $? -ne 0 ]]; then
        log_info "用户取消时区配置"
        return 1
    fi

    # 询问是否配置 NTP
    local configure_ntp=false
    if draw_yesno "NTP 同步" "是否配置 NTP 时间同步？\n\nNTP 可以自动保持系统时间准确。"; then
        configure_ntp=true
    fi

    # 确认配置
    local confirm_msg="将进行以下时区配置:\n\n"
    confirm_msg+="时区: ${selected_timezone}\n"
    if $configure_ntp; then
        confirm_msg+="NTP 同步: 启用\n"
    else
        confirm_msg+="NTP 同步: 不修改\n"
    fi
    confirm_msg+="\n是否继续？"

    if ! draw_yesno "确认配置" "$confirm_msg"; then
        return 1
    fi

    # 备份
    backup_file "/etc/timezone" "时区配置"
    [[ -f "/etc/localtime" ]] && backup_file "/etc/localtime" "本地时间"

    # 设置时区
    if ! set_timezone "$selected_timezone"; then
        draw_msgbox "错误" "时区设置失败"
        return 1
    fi

    # 配置 NTP
    if $configure_ntp; then
        if ! configure_ntp_sync; then
            draw_msgbox "警告" "NTP 配置可能存在问题"
        fi
    fi

    # 验证
    local new_timezone
    new_timezone=$(cat /etc/timezone 2>/dev/null || echo "Unknown")

    draw_msgbox "成功" "时区配置完成！\n\n新时区: ${new_timezone}\n当前时间: $(date)"

    return 0
}

# 设置时区
set_timezone() {
    local timezone="$1"

    log_info "设置时区: $timezone"

    # 方法 1: 使用 timedatectl (systemd)
    if command_exists timedatectl; then
        if timedatectl set-timezone "$timezone"; then
            log_info "使用 timedatectl 设置时区成功"
            return 0
        fi
    fi

    # 方法 2: 直接修改文件
    echo "$timezone" > /etc/timezone

    # 更新 localtime 链接
    if [[ -f "/usr/share/zoneinfo/${timezone}" ]]; then
        ln -sf "/usr/share/zoneinfo/${timezone}" /etc/localtime
        log_info "时区设置成功: $timezone"
        return 0
    else
        log_error "时区文件不存在: $timezone"
        return 1
    fi
}

# 配置 NTP 同步
configure_ntp_sync() {
    log_info "配置 NTP 时间同步..."

    # NTP 服务器选项
    local ntp_options=(
        "default" "使用默认 NTP 服务器池" "ON"
        "china" "使用中国 NTP 服务器 (cn.pool.ntp.org)" "OFF"
        "aliyun" "使用阿里云 NTP (ntp.aliyun.com)" "OFF"
        "tencent" "使用腾讯云 NTP (time.tencent.com)" "OFF"
        "cloudflare" "使用 Cloudflare NTP (time.cloudflare.com)" "OFF"
    )

    local ntp_choice
    ntp_choice=$(whiptail --title "NTP 服务器" --radiolist \
        "选择 NTP 时间服务器:" \
        15 50 6 "${ntp_options[@]}" 3>&1 1>&2 2>&3)

    if [[ $? -ne 0 ]]; then
        ntp_choice="default"
    fi

    # 获取 NTP 服务器地址
    local ntp_servers
    case "$ntp_choice" in
        china)
            ntp_servers="cn.pool.ntp.org"
            ;;
        aliyun)
            ntp_servers="ntp.aliyun.com ntp1.aliyun.com ntp2.aliyun.com"
            ;;
        tencent)
            ntp_servers="time.tencent.com"
            ;;
        cloudflare)
            ntp_servers="time.cloudflare.com"
            ;;
        *)
            ntp_servers="pool.ntp.org"
            ;;
    esac

    # 安装并配置 systemd-timesyncd
    if command_exists timedatectl; then
        # 配置 timesyncd
        if [[ "$ntp_choice" != "default" ]]; then
            mkdir -p /etc/systemd/timesyncd.conf.d
            cat > /etc/systemd/timesyncd.conf.d/ntp.conf << EOF
[Time]
NTP=${ntp_servers}
FallbackNTP=pool.ntp.org
EOF
        fi

        # 启用 NTP 同步
        timedatectl set-ntp true
        systemctl enable --now systemd-timesyncd 2>/dev/null || true

        log_info "NTP 配置完成: $ntp_servers"
    else
        # 安装传统 ntp 包
        apt-get install -y ntp 2>/dev/null || {
            log_warn "无法安装 NTP 包"
            return 1
        }

        # 配置 ntp.conf
        backup_file "/etc/ntp.conf" "NTP 配置"
        sed -i "s/^server.*/server ${ntp_servers} iburst/" /etc/ntp.conf

        systemctl enable --now ntp 2>/dev/null || service ntp start 2>/dev/null
    fi

    return 0
}
