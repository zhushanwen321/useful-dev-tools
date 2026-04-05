#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$SCRIPT_DIR"

# 目录类型的 ITEM：安装其子项为 symlink（不改动目录本身）
DIR_ITEMS=("agents" "commands" "skills" "custom-tools")
# 文件类型的 ITEM：直接作为 symlink 安装
FILE_ITEMS=("CLAUDE.md")
KNOWLEDGE_ENGINE_DIR="$CLAUDE_DIR/knowledge-engine"

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

# 迁移老安装方式：如果目标是目录级 symlink，移除它
migrate_legacy_symlinks() {
    local HOME_DIR="$1"
    local HOME_NAME="$2"
    local MIGRATED=0

    for ITEM in "${DIR_ITEMS[@]}"; do
        local TARGET="$HOME_DIR/$ITEM"

        # 检测是否为目录级 symlink（老安装方式）
        if [ -L "$TARGET" ] && [ -d "$TARGET" ]; then
            local CURRENT_TARGET
            CURRENT_TARGET="$(readlink "$TARGET")"
            echo "  迁移老安装: $ITEM (目录级 symlink -> $CURRENT_TARGET)"
            rm "$TARGET"
            # 创建目录作为容器
            mkdir -p "$TARGET"
            # 把旧 symlink 的内容重新安装为子项级 symlink
            for CHILD in "$CLAUDE_DIR/$ITEM"/*; do
                [ -e "$CHILD" ] || continue
                local CHILD_NAME
                CHILD_NAME="$(basename "$CHILD")"
                ln -s "$CHILD" "$TARGET/$CHILD_NAME"
            done
            ((MIGRATED++))
        fi
    done

    if [ "$MIGRATED" -gt 0 ]; then
        echo "  已迁移 $MIGRATED 个目录从老安装方式到新方式"
    fi
    return 0
}

# 为单个子项创建 symlink，处理冲突
install_symlink() {
    local SRC="$1"
    local TARGET="$2"
    local ITEM_NAME="$3"
    local BACKUP_DIR="$4"

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
                return 0  # 已正确链接
            else
                rm "$TARGET"  # 失效 symlink
            fi
        else
            echo "    - 替换旧链接: $ITEM_NAME ($CURRENT_TARGET)"
            rm "$TARGET"
        fi
    elif [ -e "$TARGET" ]; then
        local TIMESTAMP BACKUP
        TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
        BACKUP="${BACKUP_DIR}/${ITEM_NAME}_${TIMESTAMP}"
        echo "    - 备份: $ITEM_NAME -> $(basename "$BACKUP")"
        mv "$TARGET" "$BACKUP"
    fi

    ln -s "$SRC" "$TARGET" 2>/dev/null
}

install_for_home() {
    local HOME_DIR="$1"
    local HOME_NAME="$2"
    local BACKUP_DIR="$HOME_DIR/bak"

    echo "--- 安装到 $HOME_NAME ---"
    mkdir -p "$BACKUP_DIR"

    # 先迁移老安装方式
    migrate_legacy_symlinks "$HOME_DIR" "$HOME_NAME"

    # 安装目录类型 ITEM 的子项
    for ITEM in "${DIR_ITEMS[@]}"; do
        local SRC_DIR="$CLAUDE_DIR/$ITEM"
        local TARGET_DIR="$HOME_DIR/$ITEM"

        if [ ! -d "$SRC_DIR" ]; then
            continue
        fi

        echo "处理目录: $ITEM/"
        mkdir -p "$TARGET_DIR"

        for CHILD in "$SRC_DIR"/*; do
            [ -e "$CHILD" ] || continue
            local CHILD_NAME
            CHILD_NAME="$(basename "$CHILD")"
            install_symlink "$CHILD" "$TARGET_DIR/$CHILD_NAME" "$ITEM/$CHILD_NAME" "$BACKUP_DIR"
        done
    done

    # 安装文件类型 ITEM
    for ITEM in "${FILE_ITEMS[@]}"; do
        local SRC="$CLAUDE_DIR/$ITEM"
        local TARGET="$HOME_DIR/$ITEM"

        if [ ! -e "$SRC" ]; then
            continue
        fi

        echo "处理文件: $ITEM"
        install_symlink "$SRC" "$TARGET" "$ITEM" "$BACKUP_DIR"
    done

    echo ""
    echo "当前状态:"
    for ITEM in "${DIR_ITEMS[@]}"; do
        local TARGET_DIR="$HOME_DIR/$ITEM"
        if [ -d "$TARGET_DIR" ]; then
            local COUNT=0
            for CHILD in "$TARGET_DIR"/*; do
                if [ -L "$CHILD" ]; then
                    ((COUNT++))
                fi
            done
            echo "  $ITEM/ ($COUNT 个 symlink)"
        fi
    done
    for ITEM in "${FILE_ITEMS[@]}"; do
        local TARGET="$HOME_DIR/$ITEM"
        if [ -L "$TARGET" ]; then
            echo "  $ITEM -> $(readlink "$TARGET")"
        fi
    done
}

uninstall_for_home() {
    local HOME_DIR="$1"
    local HOME_NAME="$2"

    echo "--- 从 $HOME_NAME 卸载 ---"

    local UNINSTALLED_COUNT=0

    # 卸载目录类型的子项 symlink
    for ITEM in "${DIR_ITEMS[@]}"; do
        local SRC_DIR="$CLAUDE_DIR/$ITEM"
        local TARGET_DIR="$HOME_DIR/$ITEM"

        # 兼容老安装方式：如果是目录级 symlink 直接移除
        if [ -L "$TARGET_DIR" ] && [ -d "$TARGET_DIR" ]; then
            echo "移除目录级软链接(老安装): $TARGET_DIR"
            rm "$TARGET_DIR"
            ((UNINSTALLED_COUNT++))
            continue
        fi

        if [ ! -d "$TARGET_DIR" ]; then
            continue
        fi

        for CHILD in "$TARGET_DIR"/*; do
            [ -e "$CHILD" ] || continue
            local CHILD_SRC="$SRC_DIR/$(basename "$CHILD")"
            if is_our_symlink "$CHILD" "$CHILD_SRC"; then
                echo "移除软链接: $CHILD"
                rm "$CHILD"
                ((UNINSTALLED_COUNT++))
            fi
        done
    done

    # 卸载文件类型
    for ITEM in "${FILE_ITEMS[@]}"; do
        local SRC="$CLAUDE_DIR/$ITEM"
        local TARGET="$HOME_DIR/$ITEM"

        if is_our_symlink "$TARGET" "$SRC"; then
            echo "移除软链接: $TARGET"
            rm "$TARGET"
            ((UNINSTALLED_COUNT++))
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

# ======================== 知识引擎配置 ========================

configure_knowledge_engine() {
    local SETTINGS="$CLAUDE_HOME/settings.json"
    local ENGINE_SRC="$KNOWLEDGE_ENGINE_DIR/src/cli.ts"
    local KNOWLEDGE_DIR="$CLAUDE_HOME/knowledge"

    echo "--- 配置知识引擎 (Knowledge Engine) ---"

    # 前置检查
    if ! command -v bun &>/dev/null; then
        echo "  ! bun 未安装，跳过知识引擎配置"
        echo "  提示: curl -fsSL https://bun.sh/install | bash"
        return 1
    fi

    if [ ! -f "$ENGINE_SRC" ]; then
        echo "  ! 知识引擎源码不存在: $ENGINE_SRC"
        return 1
    fi

    if ! command -v jq &>/dev/null; then
        echo "  ! jq 未安装，跳过知识引擎配置"
        return 1
    fi

    # 安装依赖
    echo "  + 安装知识引擎依赖..."
    (cd "$KNOWLEDGE_ENGINE_DIR" && bun install --frozen-lockfile 2>/dev/null || bun install) || {
        echo "  ! 依赖安装失败"
        return 1
    }

    # 创建知识库目录和默认配置
    mkdir -p "$KNOWLEDGE_DIR"
    if [ ! -f "$KNOWLEDGE_DIR/config.json" ]; then
        echo '{
  "categories": ["architecture", "patterns", "domain", "troubleshooting"],
  "consolidateThreshold": 3,
  "excludePatterns": ["**/*.lock", "**/node_modules/**", ".env*"]
}' > "$KNOWLEDGE_DIR/config.json"
        echo "  + 创建知识库全局配置: $KNOWLEDGE_DIR/config.json"
    else
        echo "  ✓ 知识库全局配置已存在，跳过"
    fi

    # 计算 cli.ts 的绝对路径
    local CLI_PATH
    CLI_PATH="$(cd "$KNOWLEDGE_ENGINE_DIR" && pwd)/src/cli.ts"

    # 定义 hook 命令（每个命令都包含完整路径）
    local RECORD_CMD="bun \"$CLI_PATH\" record"
    local PROCESS_CMD="bun \"$CLI_PATH\" process"
    local INJECT_CMD="bun \"$CLI_PATH\" inject-index"

    # 用 jq 更新 settings.json 中的 hooks
    echo "  + 更新 hooks 配置..."

    local TMP
    TMP=$(mktemp)

    # 构建新的 hooks 配置，保留已有的非知识引擎 hook
    jq --arg record "$RECORD_CMD" \
       --arg process "$PROCESS_CMD" \
       --arg inject "$INJECT_CMD" '
      # PostToolUse: 添加知识引擎记录 hook
      .hooks = (.hooks // {}) |
      .hooks.PostToolUse = (.hooks.PostToolUse // []) |
      .hooks.PostToolUse = (
        [.hooks.PostToolUse[] | select(.hooks // [] | all(.command != $record))]
        + [{
          "matcher": "Write|Edit",
          "hooks": [{
            "type": "command",
            "command": $record,
            "async": true,
            "timeout": 5
          }]
        }]
      ) |

      # Stop: 添加知识引擎处理 hook（保留已有的 Stop hook）
      .hooks.Stop = (.hooks.Stop // []) |
      .hooks.Stop = (
        [.hooks.Stop[] | .hooks = [.hooks[] | select(.command != $process)]]
        + [{
          "hooks": [{
            "type": "command",
            "command": $process,
            "async": true,
            "timeout": 120
          }]
        }]
      ) |

      # SessionStart: 添加知识引擎索引注入
      .hooks.SessionStart = (.hooks.SessionStart // []) |
      .hooks.SessionStart = (
        [.hooks.SessionStart[] | .hooks = [.hooks[] | select(.command != $inject)]]
        + [{
          "hooks": [{
            "type": "command",
            "command": $inject,
            "timeout": 5
          }]
        }]
      )
    ' "$SETTINGS" > "$TMP"

    if [ -s "$TMP" ]; then
        mv "$TMP" "$SETTINGS"
        echo "  ✓ hooks 已更新 (PostToolUse + Stop + SessionStart)"
    else
        rm -f "$TMP"
        echo "  ! hooks 更新失败，请手动配置"
        return 1
    fi

    # 配置 crontab（可选）
    local CRON_SCRIPT="$KNOWLEDGE_ENGINE_DIR/scripts/cron-maintenance.sh"
    local CRON_ENTRY="0 23 * * * $CRON_SCRIPT"

    echo ""
    echo "  可选: 添加定时维护任务"
    echo "  运行以下命令添加 crontab:"
    echo "    (crontab -l 2>/dev/null; echo '$CRON_ENTRY') | crontab -"

    return 0
}

unconfigure_knowledge_engine() {
    local SETTINGS="$CLAUDE_HOME/settings.json"

    echo "--- 移除知识引擎配置 ---"

    if [ ! -f "$SETTINGS" ]; then
        echo "  未找到 settings.json，跳过"
        return
    fi

    if ! command -v jq &>/dev/null; then
        echo "  ! jq 未安装，跳过"
        return
    fi

    local CLI_PATH
    CLI_PATH="$(cd "$KNOWLEDGE_ENGINE_DIR" 2>/dev/null && pwd)/src/cli.ts" || {
        echo "  知识引擎目录不存在，跳过"
        return
    }

    local RECORD_CMD="bun \"$CLI_PATH\" record"
    local PROCESS_CMD="bun \"$CLI_PATH\" process"
    local INJECT_CMD="bun \"$CLI_PATH\" inject-index"

    local TMP
    TMP=$(mktemp)

    jq --arg record "$RECORD_CMD" \
       --arg process "$PROCESS_CMD" \
       --arg inject "$INJECT_CMD" '
      # 移除 PostToolUse 中的知识引擎 hook
      .hooks.PostToolUse = (.hooks.PostToolUse // []) |
      .hooks.PostToolUse = [.hooks.PostToolUse[] | .hooks = [.hooks[] | select(.command != $record)]] |
      .hooks.PostToolUse = [.hooks.PostToolUse[] | select((.hooks // []) | length > 0)] |

      # 移除 Stop 中的知识引擎 hook
      .hooks.Stop = (.hooks.Stop // []) |
      .hooks.Stop = [.hooks.Stop[] | .hooks = [.hooks[] | select(.command != $process)]] |
      .hooks.Stop = [.hooks.Stop[] | select((.hooks // []) | length > 0)] |

      # 移除 SessionStart 中的知识引擎 hook
      .hooks.SessionStart = (.hooks.SessionStart // []) |
      .hooks.SessionStart = [.hooks.SessionStart[] | .hooks = [.hooks[] | select(.command != $inject)]] |
      .hooks.SessionStart = [.hooks.SessionStart[] | select((.hooks // []) | length > 0)]
    ' "$SETTINGS" > "$TMP"

    if [ -s "$TMP" ]; then
        mv "$TMP" "$SETTINGS"
        echo "  ✓ 知识引擎 hooks 已移除"
    else
        rm -f "$TMP"
        echo "  ! 移除失败"
    fi

    echo "  注意: 知识库数据 ($CLAUDE_HOME/knowledge/) 未删除，如需手动删除"
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
            echo ""
            configure_knowledge_engine
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
            configure_knowledge_engine
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
            unconfigure_knowledge_engine
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
            unconfigure_knowledge_engine
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
