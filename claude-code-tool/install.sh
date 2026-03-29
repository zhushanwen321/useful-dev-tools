#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$SCRIPT_DIR"

ITEMS=("agents" "commands" "skills" "custom-tools" "CLAUDE.md")

echo "=== Claude Code Tool 安装脚本 ==="
echo "项目路径: $CLAUDE_DIR"
echo ""

# 预检查：验证源目录/文件是否存在
MISSING=false
for ITEM in "${ITEMS[@]}"; do
    if [ ! -e "$CLAUDE_DIR/$ITEM" ]; then
        echo "警告: 源不存在 $CLAUDE_DIR/$ITEM"
        MISSING=true
    fi
done
if [ "$MISSING" = true ]; then
    echo "以上项目将被跳过"
    echo ""
fi

CLAUDE_HOME="$HOME/.claude"
OPENCODE_HOME="$HOME/.opencode"

# 规范化路径，处理 macOS readlink 不解析相对路径的限制
resolve_path() {
    local path="$1"
    local dir base
    dir="$(cd "$(dirname "$path")" 2>/dev/null && pwd)" || return 1
    base="$(basename "$path")"
    echo "$dir/$base"
}

install_for_home() {
    local HOME_DIR="$1"
    local HOME_NAME="$2"
    local BACKUP_DIR="$HOME_DIR/bak"

    echo "--- 处理 $HOME_NAME ---"
    mkdir -p "$BACKUP_DIR"

    for ITEM in "${ITEMS[@]}"; do
        local SRC="$CLAUDE_DIR/$ITEM"
        local TARGET="$HOME_DIR/$ITEM"

        echo "处理: $ITEM"

        # 源不存在，跳过
        if [ ! -e "$SRC" ]; then
            echo "  ! 源不存在，跳过"
            continue
        fi

        if [ -L "$TARGET" ]; then
            local CURRENT_TARGET
            CURRENT_TARGET="$(readlink "$TARGET")"

            # 规范化比较：处理相对路径/绝对路径不一致
            local RESOLVED_SRC RESOLVED_CURRENT
            RESOLVED_SRC="$(resolve_path "$SRC")" || RESOLVED_SRC="$SRC"
            if [[ "$CURRENT_TARGET" != /* ]]; then
                # 相对路径：基于 TARGET 所在目录解析
                RESOLVED_CURRENT="$(cd "$(dirname "$TARGET")" 2>/dev/null && cd "$(dirname "$CURRENT_TARGET")" 2>/dev/null && pwd)/$(basename "$CURRENT_TARGET")" || RESOLVED_CURRENT="$CURRENT_TARGET"
            else
                RESOLVED_CURRENT="$CURRENT_TARGET"
            fi

            if [ "$RESOLVED_CURRENT" = "$RESOLVED_SRC" ] || [ "$CURRENT_TARGET" = "$SRC" ]; then
                if [ -e "$TARGET" ]; then
                    echo "  ✓ 已是软链接，指向正确路径，跳过"
                    continue
                else
                    # 悬挂链接：源已失效，需要重新创建
                    echo "  - 软链接已失效（源不存在），重新创建"
                    rm "$TARGET"
                fi
            else
                echo "  - 移除旧的软链接: $TARGET -> $CURRENT_TARGET"
                rm "$TARGET"
            fi

        elif [ -e "$TARGET" ]; then
            # 备份已有的目录或文件（统一处理）
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

# 安装主流程
mkdir -p "$CLAUDE_HOME"
install_for_home "$CLAUDE_HOME" "~/.claude"
configure_statusline

if [ -d "$OPENCODE_HOME" ]; then
    install_for_home "$OPENCODE_HOME" "~/.opencode"
fi

echo ""
echo "=== 安装完成 ==="
