#!/bin/bash
# 备份恢复函数库
# 提供配置文件备份和恢复功能

# 获取脚本目录
_BACKUP_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载依赖
if [[ -z "${_LOG_SH_LOADED:-}" ]]; then
    source "${_BACKUP_SCRIPT_DIR}/log.sh"
fi
if [[ -z "${_COMMON_SH_LOADED:-}" ]]; then
    source "${_BACKUP_SCRIPT_DIR}/common.sh"
fi

# 备份根目录
BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/debian-init-tool}"

# 当前备份目录 (每次运行时创建)
CURRENT_BACKUP_DIR=""

# 最大保留备份数
MAX_BACKUPS="${MAX_BACKUPS:-5}"

# 初始化备份目录
init_backup() {
    CURRENT_BACKUP_DIR="${BACKUP_ROOT}/$(date '+%Y-%m-%d_%H-%M-%S')"

    if ! mkdir -p "$CURRENT_BACKUP_DIR"; then
        log_error "无法创建备份目录: $CURRENT_BACKUP_DIR"
        return 1
    fi

    # 创建元数据文件
    cat > "${CURRENT_BACKUP_DIR}/.metadata" << EOF
# debian-init-tool 备份
created=$(date '+%Y-%m-%d %H:%M:%S')
hostname=$(hostname)
session_id=${SESSION_ID}
EOF

    # 更新 latest 链接
    ln -sfn "$CURRENT_BACKUP_DIR" "${BACKUP_ROOT}/latest"

    log_info "备份目录已创建: $CURRENT_BACKUP_DIR"
}

# 备份单个文件
backup_file() {
    local filepath="$1"
    local description="${2:-}"

    if [[ ! -f "$filepath" ]]; then
        log_debug "文件不存在，跳过备份: $filepath"
        return 0
    fi

    # 确保备份目录已初始化
    if [[ -z "$CURRENT_BACKUP_DIR" ]]; then
        init_backup
    fi

    # 保持目录结构
    local backup_path="${CURRENT_BACKUP_DIR}${filepath}"
    local backup_dir
    backup_dir=$(dirname "$backup_path")

    mkdir -p "$backup_dir"

    # 复制文件，添加时间戳后缀
    local timestamp
    timestamp=$(date '+%H%M%S')
    local backup_file="${backup_path}.bak.${timestamp}"

    if cp -p "$filepath" "$backup_file"; then
        log_info "已备份: $filepath → $backup_file"

        # 记录备份信息
        echo "file:${filepath}:${backup_file}:${description}" >> "${CURRENT_BACKUP_DIR}/.backup_list"

        return 0
    else
        log_error "备份失败: $filepath"
        return 1
    fi
}

# 备份目录
backup_dir() {
    local dirpath="$1"
    local description="${2:-}"

    if [[ ! -d "$dirpath" ]]; then
        log_debug "目录不存在，跳过备份: $dirpath"
        return 0
    fi

    # 确保备份目录已初始化
    if [[ -z "$CURRENT_BACKUP_DIR" ]]; then
        init_backup
    fi

    # 保持目录结构
    local backup_path="${CURRENT_BACKUP_DIR}${dirpath}"
    local timestamp
    timestamp=$(date '+%H%M%S')

    if cp -rp "$dirpath" "${backup_path}.${timestamp}"; then
        log_info "已备份目录: $dirpath"

        # 记录备份信息
        echo "dir:${dirpath}:${backup_path}.${timestamp}:${description}" >> "${CURRENT_BACKUP_DIR}/.backup_list"

        return 0
    else
        log_error "目录备份失败: $dirpath"
        return 1
    fi
}

# 恢复单个文件
restore_file() {
    local backup_file="$1"
    local original_path="$2"

    if [[ ! -f "$backup_file" ]]; then
        log_error "备份文件不存在: $backup_file"
        return 1
    fi

    # 备份当前文件（如果存在）
    if [[ -f "$original_path" ]]; then
        mv "$original_path" "${original_path}.current"
    fi

    # 恢复文件
    if cp -p "$backup_file" "$original_path"; then
        log_info "已恢复: $original_path"

        # 清理临时文件
        [[ -f "${original_path}.current" ]] && rm -f "${original_path}.current"

        return 0
    else
        log_error "恢复失败: $original_path"

        # 尝试恢复当前版本
        if [[ -f "${original_path}.current" ]]; then
            mv "${original_path}.current" "$original_path"
        fi

        return 1
    fi
}

# 恢复整个备份
restore_backup() {
    local backup_name="$1"
    local backup_dir="${BACKUP_ROOT}/${backup_name}"

    if [[ ! -d "$backup_dir" ]]; then
        log_error "备份不存在: $backup_name"
        return 1
    fi

    local backup_list="${backup_dir}/.backup_list"

    if [[ ! -f "$backup_list" ]]; then
        log_error "备份列表文件不存在"
        return 1
    fi

    log_info "开始恢复备份: $backup_name"

    local restored=0
    local failed=0

    while IFS=: read -r type original backup_file description; do
        case "$type" in
            file)
                if restore_file "$backup_file" "$original"; then
                    ((restored++))
                else
                    ((failed++))
                fi
                ;;
            dir)
                if [[ -d "$backup_file" ]]; then
                    rm -rf "$original"
                    if cp -rp "$backup_file" "$original"; then
                        log_info "已恢复目录: $original"
                        ((restored++))
                    else
                        log_error "目录恢复失败: $original"
                        ((failed++))
                    fi
                fi
                ;;
        esac
    done < "$backup_list"

    log_info "恢复完成: 成功 $restored, 失败 $failed"

    # 返回值: 0 表示全部成功，1 表示有失败项 (避免返回值超过 255)
    if [[ $failed -gt 0 ]]; then
        return 1
    fi
    return 0
}

# 列出所有备份
list_backups() {
    if [[ ! -d "$BACKUP_ROOT" ]]; then
        return 0
    fi

    # 列出备份目录，按时间倒序
    find "$BACKUP_ROOT" -maxdepth 1 -type d -name "20*" | sort -r | while read -r dir; do
        basename "$dir"
    done
}

# 清理旧备份
cleanup_old_backups() {
    local keep="${1:-$MAX_BACKUPS}"

    if [[ ! -d "$BACKUP_ROOT" ]]; then
        return 0
    fi

    local count
    count=$(find "$BACKUP_ROOT" -maxdepth 1 -type d -name "20*" | wc -l)

    if [[ $count -gt $keep ]]; then
        local to_delete=$((count - keep))

        log_info "清理 $to_delete 个旧备份..."

        find "$BACKUP_ROOT" -maxdepth 1 -type d -name "20*" | sort | head -n "$to_delete" | while read -r dir; do
            log_debug "删除旧备份: $dir"
            rm -rf "$dir"
        done
    fi
}

# 获取备份信息
get_backup_info() {
    local backup_name="$1"
    local backup_dir="${BACKUP_ROOT}/${backup_name}"
    local metadata="${backup_dir}/.metadata"

    if [[ -f "$metadata" ]]; then
        cat "$metadata"
    else
        echo "备份信息不可用"
    fi
}

# 备份 APT 源配置
backup_apt_sources() {
    backup_file "/etc/apt/sources.list" "APT 源列表"

    # 备份 sources.list.d 目录
    if [[ -d "/etc/apt/sources.list.d" ]]; then
        backup_dir "/etc/apt/sources.list.d" "APT 源目录"
    fi
}

# 备份 SSH 配置
backup_ssh_config() {
    backup_file "/etc/ssh/sshd_config" "SSH 服务器配置"

    if [[ -d "/etc/ssh/sshd_config.d" ]]; then
        backup_dir "/etc/ssh/sshd_config.d" "SSH 配置目录"
    fi
}

# 备份用户配置
backup_user_config() {
    local username="$1"
    local home_dir
    home_dir=$(getent passwd "$username" | cut -d: -f6)

    if [[ -n "$home_dir" && -d "$home_dir" ]]; then
        # 备份 shell 配置文件
        for rcfile in ".bashrc" ".zshrc" ".bash_profile" ".profile"; do
            if [[ -f "${home_dir}/${rcfile}" ]]; then
                backup_file "${home_dir}/${rcfile}" "用户 $username 的 $rcfile"
            fi
        done
    fi
}

# 创建完整备份
create_full_backup() {
    log_info "创建完整系统配置备份..."

    init_backup

    # 系统配置
    backup_file "/etc/hostname" "主机名"
    backup_file "/etc/timezone" "时区"
    backup_file "/etc/locale.gen" "Locale 配置"
    backup_file "/etc/default/locale" "默认 Locale"

    # APT
    backup_apt_sources

    # SSH
    backup_ssh_config

    # 防火墙
    if command_exists ufw; then
        backup_file "/etc/default/ufw" "UFW 配置"
        if [[ -d "/etc/ufw" ]]; then
            backup_dir "/etc/ufw" "UFW 规则目录"
        fi
    fi

    # Fail2ban
    if [[ -f "/etc/fail2ban/jail.local" ]]; then
        backup_file "/etc/fail2ban/jail.local" "Fail2ban 配置"
    fi

    # Docker
    if [[ -f "/etc/docker/daemon.json" ]]; then
        backup_file "/etc/docker/daemon.json" "Docker 配置"
    fi

    log_info "完整备份已创建: $CURRENT_BACKUP_DIR"

    # 清理旧备份
    cleanup_old_backups
}

# 标记库已加载
_BACKUP_SH_LOADED=true
