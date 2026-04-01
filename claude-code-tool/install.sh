#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$SCRIPT_DIR"

ITEMS=("agents" "commands" "skills" "custom-tools" "CLAUDE.md")

CLAUDE_HOME="$HOME/.claude"
OPENCODE_HOME="$HOME/.opencode"

# 显示菜单并获取选择
show_menu() {
    echo ""
    echo "=== Claude Code Tool 管理脚本 ==="
    echo ""
    echo "请选择操作:"
    echo "  1) 安装"
    echo "  2) 卸载"
    echo "  3) 退出"
    echo ""
}

show_target_menu() {
    echo ""
    echo "请选择目标:"
    echo "  1) Claude Code (~/.claude)"
    echo "  2) OpenCode (~/.opencode)"
    echo "  3) 全部"
    echo "  4) 返回上级"
    echo ""
}

get_choice() {
    local prompt="$1"
    local min="$2"
    local max="$3"
    local choice

    while true; do
        read -p "$prompt" choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge "$min" ] && [ "$choice" -le "$max" ]; then
            echo "$choice"
            return
        else
            echo "无效输入，请输入 $min-$max 之间的数字" >&2
        fi
    done
}

# 规范化路径，处理 macOS readlink 不解析相对路径的限制
resolve_path() {
    local path="$1"
    local dir base
    dir="$(cd "$(dirname "$path")" 2>/dev/null && pwd)" || return 1
    base="$(basename "$path")"
    echo "$dir/$base"
}

# 检查软链接是否指向我们的源
is_our_symlink() {
    local target="$1"
    local src="$2"

    if [ ! -L "$target" ]; then
        return 1
    fi

    local current_target
    current_target="$(readlink "$target")"

    local resolved_src resolved_current
    resolved_src="$(resolve_path "$src")" || resolved_src="$src"

    if [[ "$current_target" != /* ]]; then
        resolved_current="$(cd "$(dirname "$target")" 2>/dev/null && cd "$(dirname "$current_target")" 2>/dev/null && pwd)/$(basename "$current_target")" || resolved_current="$current_target"
    else
        resolved_current="$current_target"
    fi

    [ "$resolved_current" = "$resolved_src" ] || [ "$current_target" = "$src" ]
}

install_for_home() {
    local HOME_DIR="$1"
    local HOME_NAME="$2"
    local BACKUP_DIR="$HOME_DIR/bak"

    echo "--- 安装到 $HOME_NAME ---"
    mkdir -p "$BACKUP_DIR"

    for ITEM in "${ITEMS[@]}"; do
        local SRC="$CLAUDE_DIR/$ITEM"
        local TARGET="$HOME_DIR/$ITEM"

        echo "处理: $ITEM"

        if [ ! -e "$SRC" ]; then
            echo "  ! 源不存在，跳过"
            continue
        fi

        if [ -L "$TARGET" ]; then
            local CURRENT_TARGET
            CURRENT_TARGET="$(readlink "$TARGET")"

            local RESOLVED_SRC RESOLVED_CURRENT
            RESOLVED_SRC="$(resolve_path "$SRC")" || RESOLVED_SRC="$SRC"
            if [[ "$CURRENT_TARGET" != /* ]]; then
                RESOLVED_CURRENT="$(cd "$(dirname "$TARGET")" 2>/dev/null && cd "$(dirname "$CURRENT_TARGET")" 2>/dev/null && pwd)/$(basename "$CURRENT_TARGET")" || RESOLVED_CURRENT="$CURRENT_TARGET"
            else
                RESOLVED_CURRENT="$CURRENT_TARGET"
            fi

            if [ "$RESOLVED_CURRENT" = "$RESOLVED_SRC" ] || [ "$CURRENT_TARGET" = "$SRC" ]; then
                if [ -e "$TARGET" ]; then
                    echo "  ✓ 已是软链接，指向正确路径，跳过"
                    continue
                else
                    echo "  - 软链接已失效（源不存在），重新创建"
                    rm "$TARGET"
                fi
            else
                echo "  - 移除旧的软链接: $TARGET -> $CURRENT_TARGET"
                rm "$TARGET"
            fi

        elif [ -e "$TARGET" ]; then
            local TIMESTAMP BACKUP
            TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
            BACKUP="${BACKUP_DIR}/${ITEM}_${TIMESTAMP}"
            echo "  - 备份: $TARGET -> $BACKUP"
            mv "$TARGET" "$BACKUP"
        fi

        echo "  + 创建软链接: $TARGET -> $SRC"
        if ! ln -s "$SRC" "$TARGET" 2>/dev/null; then
            echo "  ! 创建软链接失败: $TARGET"
            continue
        fi
    done

    echo ""
    echo "当前软链接状态:"
    for ITEM in "${ITEMS[@]}"; do
        local TARGET="$HOME_DIR/$ITEM"
        if [ -L "$TARGET" ]; then
            local LINK_TARGET
            LINK_TARGET="$(readlink "$TARGET")"
            if [ -e "$TARGET" ]; then
                echo "  $ITEM -> $LINK_TARGET"
            else
                echo "  $ITEM -> $LINK_TARGET (链接失效!)"
            fi
        else
            echo "  $ITEM (非软链接)"
        fi
    done
    echo ""
    echo "备份文件位置: $BACKUP_DIR"
}

uninstall_for_home() {
    local HOME_DIR="$1"
    local HOME_NAME="$2"

    echo "--- 从 $HOME_NAME 卸载 ---"

    local UNINSTALLED_COUNT=0

    for ITEM in "${ITEMS[@]}"; do
        local SRC="$CLAUDE_DIR/$ITEM"
        local TARGET="$HOME_DIR/$ITEM"

        if is_our_symlink "$TARGET" "$SRC"; then
            echo "移除软链接: $TARGET"
            rm "$TARGET"
            ((UNINSTALLED_COUNT++))
        else
            if [ -e "$TARGET" ]; then
                echo "跳过 (非本工具创建的软链接): $ITEM"
            fi
        fi
    done

    if [ "$UNINSTALLED_COUNT" -eq 0 ]; then
        echo "没有需要卸载的项目"
    else
        echo "已卸载 $UNINSTALLED_COUNT 个项目"
    fi
}

configure_statusline() {
    local SETTINGS="$CLAUDE_HOME/settings.json"
    local COMMAND="\"\$HOME/.claude/custom-tools/statusline.sh\""

    echo "--- 配置 statusline ---"

    if ! command -v jq &>/dev/null; then
        echo "  ! jq 未安装，跳过 statusline 配置"
        echo "  提示: 安装 jq 后重新运行此脚本"
        return
    fi

    if [ ! -f "$SETTINGS" ]; then
        echo "  + 创建 settings.json"
        echo "{\"statusLine\":{\"type\":\"command\",\"command\":$COMMAND}}" | jq . > "$SETTINGS"
        return
    fi

    local CURRENT
    CURRENT=$(jq -r '.statusLine.command // empty' "$SETTINGS" 2>/dev/null) || true

    if [ "$CURRENT" = "$COMMAND" ]; then
        echo "  ✓ statusline 已配置，跳过"
        return
    fi

    echo "  + 更新 statusline 配置: $COMMAND"
    local TMP
    TMP=$(mktemp)
    if jq --arg cmd "$COMMAND" '.statusLine = {"type": "command", "command": $cmd}' "$SETTINGS" > "$TMP"; then
        mv "$TMP" "$SETTINGS"
    else
        rm -f "$TMP"
        echo "  ! 更新 settings.json 失败，请手动配置"
    fi
}

unconfigure_statusline() {
    local SETTINGS="$CLAUDE_HOME/settings.json"
    local COMMAND="\"\$HOME/.claude/custom-tools/statusline.sh\""

    echo "--- 移除 statusline 配置 ---"

    if [ ! -f "$SETTINGS" ]; then
        echo "  未找到 settings.json，跳过"
        return
    fi

    if ! command -v jq &>/dev/null; then
        echo "  ! jq 未安装，跳过 statusline 配置移除"
        return
    fi

    local CURRENT
    CURRENT=$(jq -r '.statusLine.command // empty' "$SETTINGS" 2>/dev/null) || true

    if [ "$CURRENT" = "$COMMAND" ]; then
        echo "  - 移除 statusline 配置"
        local TMP
        TMP=$(mktemp)
        if jq 'del(.statusLine)' "$SETTINGS" > "$TMP"; then
            mv "$TMP" "$SETTINGS"
        else
            rm -f "$TMP"
            echo "  ! 更新 settings.json 失败，请手动配置"
        fi
    else
        echo "  statusline 不是本工具配置，跳过"
    fi
}

handle_install() {
    show_target_menu
    local choice
    choice=$(get_choice "请输入选项 (1-4): " 1 4)

    case "$choice" in
        1)
            mkdir -p "$CLAUDE_HOME"
            install_for_home "$CLAUDE_HOME" "~/.claude"
            configure_statusline
            ;;
        2)
            if [ -d "$OPENCODE_HOME" ]; then
                install_for_home "$OPENCODE_HOME" "~/.opencode"
            else
                echo "未检测到 OpenCode 目录 (~/.opencode)"
            fi
            ;;
        3)
            mkdir -p "$CLAUDE_HOME"
            install_for_home "$CLAUDE_HOME" "~/.claude"
            configure_statusline
            echo ""
            if [ -d "$OPENCODE_HOME" ]; then
                install_for_home "$OPENCODE_HOME" "~/.opencode"
            else
                echo "未检测到 OpenCode 目录 (~/.opencode)，跳过"
            fi
            ;;
        4)
            return
            ;;
    esac
}

handle_uninstall() {
    show_target_menu
    local choice
    choice=$(get_choice "请输入选项 (1-4): " 1 4)

    case "$choice" in
        1)
            uninstall_for_home "$CLAUDE_HOME" "~/.claude"
            unconfigure_statusline
            ;;
        2)
            if [ -d "$OPENCODE_HOME" ]; then
                uninstall_for_home "$OPENCODE_HOME" "~/.opencode"
            else
                echo "未检测到 OpenCode 目录 (~/.opencode)"
            fi
            ;;
        3)
            uninstall_for_home "$CLAUDE_HOME" "~/.claude"
            unconfigure_statusline
            echo ""
            if [ -d "$OPENCODE_HOME" ]; then
                uninstall_for_home "$OPENCODE_HOME" "~/.opencode"
            else
                echo "未检测到 OpenCode 目录 (~/.opencode)，跳过"
            fi
            ;;
        4)
            return
            ;;
    esac
}

# 主循环
while true; do
    show_menu
    main_choice=$(get_choice "请输入选项 (1-3): " 1 3)

    case "$main_choice" in
        1)
            handle_install
            ;;
        2)
            handle_uninstall
            ;;
        3)
            echo ""
            echo "再见!"
            exit 0
            ;;
    esac

done
