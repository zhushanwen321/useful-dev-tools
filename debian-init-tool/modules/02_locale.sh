#!/bin/bash
# Locale 设置模块
# 配置系统区域和语言设置

configure_locale() {
    log_info "开始配置 Locale..."

    # 可用的 locale 列表
    local available_locales=(
        "en_US.UTF-8" "英语 (美国) UTF-8" "ON"
        "zh_CN.UTF-8" "简体中文 UTF-8" "OFF"
        "zh_TW.UTF-8" "繁体中文 UTF-8" "OFF"
        "ja_JP.UTF-8" "日语 UTF-8" "OFF"
        "ko_KR.UTF-8" "韩语 UTF-8" "OFF"
        "de_DE.UTF-8" "德语 UTF-8" "OFF"
        "fr_FR.UTF-8" "法语 UTF-8" "OFF"
    )

    # 选择要生成的 locale
    local selected_locales
    selected_locales=$(whiptail --title "Locale 配置" --checklist \
        "选择要启用的区域设置:\n\n建议至少选择 en_US.UTF-8 和您的本地语言" \
        20 60 8 "${available_locales[@]}" 3>&1 1>&2 2>&3 | tr -d '"')

    if [[ $? -ne 0 ]] || [[ -z "$selected_locales" ]]; then
        log_info "用户取消或未选择任何 locale"
        return 1
    fi

    # 选择默认 locale
    local default_options=()
    for locale in $selected_locales; do
        default_options+=("$locale" "$locale")
    done

    local default_locale
    default_locale=$(whiptail --title "默认 Locale" --radiolist \
        "选择系统默认的区域设置:" \
        15 50 ${#default_options[@]} \
        "${default_options[@]}" 3>&1 1>&2 2>&3)

    if [[ $? -ne 0 ]]; then
        default_locale="en_US.UTF-8"
    fi

    # 确认配置
    local confirm_msg="将进行以下 Locale 配置:\n\n"
    confirm_msg+="启用的 locale:\n$(echo "$selected_locales" | tr ' ' '\n' | sed 's/^/  • /')\n\n"
    confirm_msg+="默认 locale: ${default_locale}\n\n"
    confirm_msg+="是否继续？"

    if ! draw_yesno "确认配置" "$confirm_msg"; then
        return 1
    fi

    # 备份现有配置
    backup_file "/etc/locale.gen" "Locale 生成配置"
    backup_file "/etc/default/locale" "默认 Locale"

    # 安装 locales 包
    if ! dpkg -l locales &>/dev/null | grep -q "^ii"; then
        log_info "安装 locales 包..."
        apt-get install -y locales
    fi

    # 配置 locale.gen
    configure_locale_gen "$selected_locales"

    # 生成 locale
    generate_locales

    # 设置默认 locale
    set_default_locale "$default_locale"

    # 验证配置
    if verify_locale "$default_locale"; then
        draw_msgbox "成功" "Locale 配置完成！\n\n默认语言: ${default_locale}"
        return 0
    else
        draw_msgbox "警告" "Locale 配置可能存在问题，请检查日志"
        return 1
    fi
}

# 配置 locale.gen 文件
configure_locale_gen() {
    local locales="$1"

    log_info "配置 /etc/locale.gen..."

    # 先禁用所有 locale
    sed -i 's/^[^#]/# &/' /etc/locale.gen

    # 启用选中的 locale
    for locale in $locales; do
        # 查找并取消注释对应的行
        local pattern
        pattern=$(echo "$locale" | sed 's/\./\\./g')
        sed -i "s|^# ${pattern} |${pattern} |" /etc/locale.gen
        sed -i "s|^#${pattern} |${pattern} |" /etc/locale.gen
    done
}

# 生成 locale
generate_locales() {
    log_info "生成 locale..."

    if locale-gen; then
        log_info "Locale 生成成功"
        return 0
    else
        log_error "Locale 生成失败"
        return 1
    fi
}

# 设置默认 locale
set_default_locale() {
    local default_locale="$1"

    log_info "设置默认 locale: $default_locale"

    # 更新 /etc/default/locale
    cat > /etc/default/locale << EOF
# 由 debian-init-tool 自动生成
LANG="${default_locale}"
LANGUAGE="${default_locale}"
LC_ALL="${default_locale}"
EOF

    # 使用 update-locale 命令
    update-locale LANG="$default_locale" LANGUAGE="$default_locale" LC_ALL="$default_locale" 2>/dev/null

    # 导出到当前环境
    export LANG="$default_locale"
    export LANGUAGE="$default_locale"
    export LC_ALL="$default_locale"
}

# 验证 locale 配置
verify_locale() {
    local expected_locale="$1"

    log_info "验证 locale 配置..."

    # 检查 locale 是否已生成
    if ! locale -a 2>/dev/null | grep -q "${expected_locale}"; then
        log_error "Locale $expected_locale 未成功生成"
        return 1
    fi

    # 检查当前设置
    local current_locale
    current_locale=$(echo "$LANG" | cut -d'.' -f1,2)

    if [[ "$current_locale" != "$expected_locale" ]]; then
        log_warn "当前会话的 locale 与预期不同 (需要重新登录)"
    fi

    log_info "Locale 验证通过"
    return 0
}

# 显示当前 locale 信息
show_locale_info() {
    local info="当前 Locale 设置:\n\n"
    info+="LANG: ${LANG:-未设置}\n"
    info+="LANGUAGE: ${LANGUAGE:-未设置}\n"
    info+="LC_ALL: ${LC_ALL:-未设置}\n\n"
    info+="已安装的 locale:\n"
    info+=$(locale -a 2>/dev/null | head -10 | sed 's/^/  /')

    draw_msgbox "Locale 信息" "$info"
}
