#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$SCRIPT_DIR"

BACKUP_DIR="$HOME/.claude/bak"
CLAUDE_HOME="$HOME/.claude"

ITEMS=("agents" "commands" "skills" "CLAUDE.md")

echo "=== Claude Code Tool 安装脚本 ==="
echo "项目路径: $CLAUDE_DIR"
echo "备份目录: $BACKUP_DIR"
echo ""

if [ ! -d "$CLAUDE_HOME" ]; then
    echo "错误: $CLAUDE_HOME 目录不存在"
    exit 1
fi

if [ ! -d "$BACKUP_DIR" ]; then
    echo "创建备份目录: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
fi

for ITEM in "${ITEMS[@]}"; do
    SRC="$CLAUDE_DIR/$ITEM"
    TARGET="$CLAUDE_HOME/$ITEM"
    BACKUP="$BACKUP_DIR/$ITEM"

    echo "处理: $ITEM"

    if [ -L "$TARGET" ]; then
        CURRENT_TARGET=$(readlink "$TARGET")
        if [ "$CURRENT_TARGET" = "$SRC" ]; then
            echo "  ✓ 已是软链接，指向正确路径，跳过"
            continue
        else
            echo "  - 移除旧的软链接: $TARGET -> $CURRENT_TARGET"
            rm "$TARGET"
        fi
    elif [ -e "$TARGET" ]; then
        if [ -d "$TARGET" ]; then
            if [ -d "$BACKUP" ]; then
                TIMESTAMP=$(date +%Y%m%d_%H%M%S)
                BACKUP="${BACKUP}_${TIMESTAMP}"
            fi
            echo "  - 备份目录: $TARGET -> $BACKUP"
            mv "$TARGET" "$BACKUP"
        elif [ -f "$TARGET" ]; then
            if [ -f "$BACKUP" ]; then
                TIMESTAMP=$(date +%Y%m%d_%H%M%S)
                BACKUP="${BACKUP}_${TIMESTAMP}"
            fi
            echo "  - 备份文件: $TARGET -> $BACKUP"
            mv "$TARGET" "$BACKUP"
        fi
    else
        echo "  - 目标不存在，跳过"
        continue
    fi

    echo "  + 创建软链接: $TARGET -> $SRC"
    ln -s "$SRC" "$TARGET"
done

echo ""
echo "=== 安装完成 ==="
echo ""
echo "当前软链接状态:"
for ITEM in "${ITEMS[@]}"; do
    TARGET="$CLAUDE_HOME/$ITEM"
    if [ -L "$TARGET" ]; then
        LINK_TARGET=$(readlink "$TARGET")
        echo "  $ITEM -> $LINK_TARGET"
    else
        echo "  $ITEM (非软链接)"
    fi
done

echo ""
echo "备份文件位置: $BACKUP_DIR"
