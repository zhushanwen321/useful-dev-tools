#!/bin/bash

set -euo pipefail

DRY_RUN=false
if [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN=true
fi

# ======================== 模块注册表 ========================
# 格式: name|description|type|risk_level|dep_tools
# type: symlink(子项级), file(单文件), settings(配置修改), settings+deps(配置+依赖)
# dep_tools: 逗号分隔的工具名（如 bun,jq），不是模块依赖
MODULES=(
  "skills|Skills 技能集合|symlink|low|"
  "agents|Agent 子代理|symlink|low|"
  "commands|自定义命令|symlink|low|"
  "hooks|Hook 脚本|symlink|low|"
  "custom-tools|自定义工具|symlink|low|"
  "claude-md|CLAUDE.md 全局配置|file|medium|"
  "statusline|状态栏|settings|low|"
  "skill-inject|Skill 注入 Hook|settings|medium|"
  "knowledge-engine|知识引擎|settings+deps|high|bun,jq"
)

# 解析模块字段
parse_module_name()        { echo "$1" | cut -d'|' -f1; }
parse_module_description() { echo "$1" | cut -d'|' -f2; }
parse_module_type()        { echo "$1" | cut -d'|' -f3; }
parse_module_risk()        { echo "$1" | cut -d'|' -f4; }
parse_module_dep_tools()   { echo "$1" | cut -d'|' -f5; }

# 检查模块依赖的工具是否可用，返回缺失的工具列表（逗号分隔）
get_missing_tools() {
  local deps
  deps="$(parse_module_dep_tools "$1")"
  [ -z "$deps" ] && return
  local missing=""
  local dep
  for dep in $(echo "$deps" | tr ',' ' '); do
    if ! command -v "$dep" &>/dev/null; then
      missing="${missing:+$missing,}$dep"
    fi
  done
  [ -n "$missing" ] && echo "$missing" || true
}

# 获取缺失工具的安装提示
get_install_hint() {
  local tool="$1"
  case "$tool" in
    bun) echo "curl -fsSL https://bun.sh/install | bash" ;;
    jq)  echo "brew install jq (macOS) 或 apt install jq (Linux)" ;;
    *)   echo "请参考 $tool 官方文档" ;;
  esac
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$SCRIPT_DIR"

# 目录类型的 ITEM：安装其子项为 symlink（不改动目录本身）
DIR_ITEMS=("agents" "commands" "skills" "custom-tools" "hooks")
# 文件类型的 ITEM：直接作为 symlink 安装
FILE_ITEMS=("CLAUDE.md")
KNOWLEDGE_ENGINE_DIR="$CLAUDE_DIR/knowledge-engine"

CLAUDE_HOME="$HOME/.claude"
OPENCODE_HOME="$HOME/.opencode"

# ======================== 变更计划机制 ========================
# PLAN 数组格式: "type|arg1|arg2|arg3"
# 注意: 使用 | 作为分隔符，plan_symlink/plan_backup/plan_setting/plan_message 的参数中不得包含 | 字符
PLAN=()
PLAN_BACKUPS=()

plan_symlink() {
  # $1: 目标路径 $2: 源路径 $3: 描述
  PLAN+=("symlink|$1|$2|$3")
}

plan_backup() {
  # $1: 原文件路径 $2: 备份路径
  PLAN+=("backup|$1|$2|")
  PLAN_BACKUPS+=("$2")
}

plan_setting() {
  # $1: 描述 $2: 附加信息
  PLAN+=("setting|$1||$2")
}

plan_message() {
  # $1: 信息文本
  PLAN+=("info|$1||")
}

# 展示计划摘要（dry-run 用）
# bash 3.2 兼容: 使用 ${arr[@]+"${arr[@]}"} 防止空数组在 set -u 下崩溃
show_plan() {
  [ ${#PLAN[@]} -eq 0 ] && { echo "  无变更。"; return; }

  local SYMLINK_COUNT=0 BACKUP_COUNT=0 SETTING_COUNT=0

  echo ""
  echo "=== 变更计划 ==="
  echo ""

  local entry
  for entry in "${PLAN[@]+"${PLAN[@]}"}"; do
    local type arg1 arg2 arg3
    IFS='|' read -r type arg1 arg2 arg3 <<< "$entry"
    case "$type" in
      symlink)
        if [ ! -e "$arg1" ] 2>/dev/null || [ -L "$arg1" ]; then
          echo "  + $arg3"
        else
          echo "  + $arg3 (将备份已有文件)"
          ((BACKUP_COUNT++)) || true
        fi
        ((SYMLINK_COUNT++)) || true
        ;;
      backup)
        echo "  △ 备份: $(basename "$arg1") → $(basename "$arg2")"
        ((BACKUP_COUNT++)) || true
        ;;
      setting)
        echo "  * $arg1"
        ((SETTING_COUNT++)) || true
        ;;
      info)
        echo "  $arg1"
        ;;
    esac
  done

  echo ""
  echo "摘要: $SYMLINK_COUNT 个 symlink, $BACKUP_COUNT 个备份, $SETTING_COUNT 个配置修改"
}

# 执行计划（仅 symlink 和 backup 类型；settings 由 configure_* 函数处理）
execute_plan() {
  [ ${#PLAN[@]} -eq 0 ] && return

  local entry
  for entry in "${PLAN[@]+"${PLAN[@]}"}"; do
    local type arg1 arg2 arg3
    IFS='|' read -r type arg1 arg2 arg3 <<< "$entry"
    case "$type" in
      symlink)
        local TARGET="$arg1" SRC="$arg2"
        if [ -L "$TARGET" ]; then
          rm "$TARGET"
        elif [ -e "$TARGET" ]; then
          local TIMESTAMP BACKUP
          TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
          BACKUP="${BACKUP_DIR:-$CLAUDE_HOME/bak}/$(basename "$TARGET")_${TIMESTAMP}"
          mkdir -p "$(dirname "$BACKUP")"
          mv "$TARGET" "$BACKUP"
        fi
        mkdir -p "$(dirname "$TARGET")"
        ln -s "$SRC" "$TARGET"
        ;;
      backup)
        mkdir -p "$(dirname "$arg2")"
        mv "$arg1" "$arg2"
        ;;
      setting)
        # settings 的执行由各模块自己的 configure_* 函数处理
        ;;
      info)
        echo "  $arg1"
        ;;
    esac
  done
}

# settings.json 安全备份（修改前调用）
backup_settings() {
  local SETTINGS="$1"
  [ ! -f "$SETTINGS" ] && return
  local TIMESTAMP BACKUP
  TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
  BACKUP="$(dirname "$SETTINGS")/bak/settings.json_${TIMESTAMP}"
  mkdir -p "$(dirname "$BACKUP")"
  cp "$SETTINGS" "$BACKUP"
  echo "  备份 settings.json → bak/settings.json_${TIMESTAMP}"
}

# 记录变更日志
log_install() {
  local ACTION="$1"
  local DETAILS="$2"
  local LOG_FILE="$CLAUDE_HOME/bak/install.log"
  mkdir -p "$(dirname "$LOG_FILE")"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $ACTION: $DETAILS" >> "$LOG_FILE"
}

# ======================== 计划生成（不执行变更） ========================

plan_install_for_home() {
  local HOME_DIR="$1"
  local BACKUP_DIR="$HOME_DIR/bak"

  local MODULE
  for MODULE in "${MODULES[@]+"${MODULES[@]}"}"; do
    local NAME TYPE
    NAME="$(parse_module_name "$MODULE")"
    TYPE="$(parse_module_type "$MODULE")"

    if ! is_module_selected "$NAME"; then
      continue
    fi

    case "$TYPE" in
      symlink)
        local SRC_DIR="$CLAUDE_DIR/$NAME"
        if [ ! -d "$SRC_DIR" ]; then continue; fi
        # 目标子目录在 execute_plan 中创建，plan 阶段不执行 mkdir

        local CHILD
        for CHILD in "$SRC_DIR"/*; do
          [ -e "$CHILD" ] || continue
          local CHILD_NAME TARGET
          CHILD_NAME="$(basename "$CHILD")"
          TARGET="$HOME_DIR/$NAME/$CHILD_NAME"

          if [ -L "$TARGET" ]; then
            if is_our_symlink "$TARGET" "$CHILD"; then
              continue  # 已正确链接
            else
              plan_symlink "$TARGET" "$CHILD" "$NAME/$CHILD_NAME (替换外部链接)"
            fi
          elif [ -e "$TARGET" ]; then
            local TIMESTAMP BACKUP
            TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
            BACKUP="${BACKUP_DIR}/${CHILD_NAME}_${TIMESTAMP}"
            plan_backup "$TARGET" "$BACKUP"
            plan_symlink "$TARGET" "$CHILD" "$NAME/$CHILD_NAME"
          else
            plan_symlink "$TARGET" "$CHILD" "$NAME/$CHILD_NAME"
          fi
        done
        ;;

      file)
        local SRC TARGET
        case "$NAME" in
          claude-md)
            SRC="$CLAUDE_DIR/CLAUDE.md"
            TARGET="$HOME_DIR/CLAUDE.md"
            ;;
          *)
            continue
            ;;
        esac

        if [ ! -e "$SRC" ]; then continue; fi

        if [ -L "$TARGET" ]; then
          if is_our_symlink "$TARGET" "$SRC"; then
            continue
          fi
          plan_symlink "$TARGET" "$SRC" "$NAME (替换外部链接)"
        elif [ -e "$TARGET" ]; then
          # CLAUDE.md: 展示 diff 让用户了解差异
          if command -v diff &>/dev/null; then
            local DIFF_OUTPUT
            DIFF_OUTPUT=$(diff --color=never -u "$TARGET" "$SRC" 2>/dev/null || true)
            if [ -n "$DIFF_OUTPUT" ]; then
              plan_message "CLAUDE.md 与已有版本有差异:"
              while IFS= read -r line; do
                plan_message "  $line"
              done <<< "$DIFF_OUTPUT"
            fi
          fi
          local TIMESTAMP BACKUP
          TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
          BACKUP="${BACKUP_DIR}/${NAME}_${TIMESTAMP}"
          plan_backup "$TARGET" "$BACKUP"
          plan_symlink "$TARGET" "$SRC" "$NAME"
        else
          plan_symlink "$TARGET" "$SRC" "$NAME"
        fi
        ;;

      settings|settings+deps)
        case "$NAME" in
          statusline)
            plan_configure_statusline "$HOME_DIR"
            ;;
          skill-inject)
            plan_configure_skill_inject "$HOME_DIR"
            ;;
          knowledge-engine)
            plan_configure_knowledge_engine "$HOME_DIR"
            ;;
        esac
        ;;
    esac
  done
}

# settings 类模块的计划预检函数

plan_configure_statusline() {
  local HOME_DIR="$1"
  local SETTINGS="$HOME_DIR/settings.json"
  # statusline 脚本始终在 ~/.claude 下（由 symlink 安装），所以路径固定
  local COMMAND="\"\$HOME/.claude/custom-tools/statusline.sh\""

  if [ -f "$SETTINGS" ]; then
    local CURRENT
    CURRENT=$(jq -r '.statusLine.command // empty' "$SETTINGS" 2>/dev/null) || true
    if [ "$CURRENT" = "$COMMAND" ]; then
      plan_message "statusline 已配置，跳过"
      return
    fi
  fi

  plan_setting "settings.json: 配置 statusline" ""
}

plan_configure_skill_inject() {
  local HOME_DIR="$1"
  local SETTINGS="$HOME_DIR/settings.json"
  local HOOK_CMD="bash \"\$HOME/.claude/hooks/skill-inject.sh\""

  if [ -f "$SETTINGS" ]; then
    local HAS_HOOKS
    HAS_HOOKS=$(jq -r '[.hooks.PreToolUse // [] | .[] | .hooks // [] | .[] | select(.command == "'"$HOOK_CMD"'")] | length' "$SETTINGS" 2>/dev/null) || true
    if [ "${HAS_HOOKS:-0}" -gt 0 ] 2>/dev/null; then
      plan_message "Skill 注入 Hook 已配置，跳过"
      return
    fi
    local HAS_OTHER
    HAS_OTHER=$(jq -r '[.hooks.PreToolUse // [] | .[] | .hooks // [] | .[]] | length' "$SETTINGS" 2>/dev/null) || true
    if [ "${HAS_OTHER:-0}" -gt 0 ] 2>/dev/null; then
      plan_message "已有其他 PreToolUse hooks，将追加（不覆盖）"
    fi
  fi

  plan_setting "settings.json: 添加 PreToolUse hook (Skill matcher)" ""
}

plan_configure_knowledge_engine() {
  local HOME_DIR="$1"
  local ENGINE_SRC="$KNOWLEDGE_ENGINE_DIR/src/cli.ts"

  if [ ! -f "$ENGINE_SRC" ]; then
    plan_message "知识引擎源码不存在，跳过"
    return
  fi

  local MISSING
  MISSING="$(get_missing_tools "knowledge-engine|知识引擎|settings+deps|high|bun,jq")"
  if [ -n "$MISSING" ]; then
    plan_message "知识引擎: 缺少 $MISSING，跳过"
    for tool in $(echo "$MISSING" | tr ',' ' '); do
      plan_message "  安装 $tool: $(get_install_hint "$tool")"
    done
    return
  fi

  plan_setting "settings.json: 添加知识引擎 hooks (PostToolUse + Stop + SessionStart)" ""
  plan_setting "安装知识引擎依赖 (bun install)" ""
  plan_setting "创建知识库目录和默认配置" ""
}

# ======================== 模块选择交互 ========================

# bash 3.2 兼容: 不使用 declare -A，用 eval+命名约定变量追踪选择状态
# 变量命名: SELECTED_<module_name>=1/0

# 模块名转安全变量名: custom-tools → custom_tools
_safe_var_name() {
  echo "$1" | tr '-' '_'
}

# 重置所有选择
reset_selections() {
  local MODULE
  for MODULE in "${MODULES[@]+"${MODULES[@]}"}"; do
    local NAME
    NAME="$(parse_module_name "$MODULE")"
    local SAFE_NAME
    SAFE_NAME="$(_safe_var_name "$NAME")"
    eval "SELECTED_${SAFE_NAME}=0"
  done
}

# 标记模块为选中/未选中
set_selected() {
  local SAFE_NAME
  SAFE_NAME="$(_safe_var_name "$1")"
  eval "SELECTED_${SAFE_NAME}=${2:-1}"
}

# 检查模块是否被选中
is_module_selected() {
  local SAFE_NAME val
  SAFE_NAME="$(_safe_var_name "$1")"
  eval "val=\${SELECTED_${SAFE_NAME}:-0}"
  [ "$val" = "1" ]
}

# 展示模块 checklist 并获取用户选择
show_module_checklist() {
  echo ""
  echo "--- [2/4] 选择要安装的模块 ---"
  echo ""

  local IDX=0
  local DEFAULTS=()

  local MODULE
  for MODULE in "${MODULES[@]+"${MODULES[@]}"}"; do
    local NAME DESCRIPTION TYPE RISK
    NAME="$(parse_module_name "$MODULE")"
    DESCRIPTION="$(parse_module_description "$MODULE")"
    TYPE="$(parse_module_type "$MODULE")"
    RISK="$(parse_module_risk "$MODULE")"
    ((IDX++)) || true

    # 检查依赖工具
    local MISSING_TOOLS
    MISSING_TOOLS="$(get_missing_tools "$MODULE")"
    local STATUS_LINE=""
    if [ -n "$MISSING_TOOLS" ]; then
      STATUS_LINE=" [不可用: 需要 $MISSING_TOOLS]"
      DEFAULTS+=("off")
    elif [ "$RISK" = "low" ]; then
      DEFAULTS+=("on")
    elif [ "$RISK" = "medium" ]; then
      DEFAULTS+=("off")
    else
      DEFAULTS+=("off")
    fi

    local RISK_LABEL=""
    case "$RISK" in
      low)    RISK_LABEL="低风险" ;;
      medium) RISK_LABEL="中风险" ;;
      high)   RISK_LABEL="高风险" ;;
    esac

    echo "  $IDX) [$RISK_LABEL] $DESCRIPTION$STATUS_LINE"
  done

  echo ""
  echo "  默认已选中低风险模块。"
  echo "  输入编号切换选择（如: 6 8），直接回车使用默认值。"

  # 读取用户输入
  local INPUT
  read -p "  选择 (回车确认): " INPUT

  # 应用默认值
  reset_selections
  IDX=0
  for MODULE in "${MODULES[@]+"${MODULES[@]}"}"; do
    local NAME
    NAME="$(parse_module_name "$MODULE")"
    ((IDX++)) || true
    if [ "${DEFAULTS[$((IDX-1))]}" = "on" ]; then
      set_selected "$NAME" 1
    fi
  done

  # 处理用户输入（切换选择）
  if [ -n "$INPUT" ]; then
    for NUM in $INPUT; do
      if [[ "$NUM" =~ ^[0-9]+$ ]] && [ "$NUM" -ge 1 ] && [ "$NUM" -le "${#MODULES[@]}" ]; then
        local MODULE="${MODULES[$((NUM-1))]}"
        local NAME
        NAME="$(parse_module_name "$MODULE")"
        if is_module_selected "$NAME"; then
          set_selected "$NAME" 0
        else
          set_selected "$NAME" 1
        fi
      fi
    done
  fi

  # 展示最终选择
  echo ""
  echo "  已选择的模块:"
  for MODULE in "${MODULES[@]+"${MODULES[@]}"}"; do
    local NAME DESCRIPTION
    NAME="$(parse_module_name "$MODULE")"
    DESCRIPTION="$(parse_module_description "$MODULE")"
    if is_module_selected "$NAME"; then
      echo "    [x] $DESCRIPTION"
    else
      echo "    [ ] $DESCRIPTION"
    fi
  done
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
            # 跳过非 symlink 文件
            [ ! -L "$CHILD" ] && continue
            local CHILD_SRC="$SRC_DIR/$(basename "$CHILD")"
            if is_our_symlink "$CHILD" "$CHILD_SRC"; then
                echo "移除软链接: $CHILD"
                rm "$CHILD"
                ((UNINSTALLED_COUNT++))
            elif [ ! -e "$CHILD" ]; then
                # 断链(dangling symlink): 源仓库可能已移动，提示用户
                local LINK_TARGET
                LINK_TARGET="$(readlink "$CHILD")"
                if [[ "$LINK_TARGET" == *"$CLAUDE_DIR"* ]]; then
                    echo "移除断链(源已失效): $CHILD -> $LINK_TARGET"
                    rm "$CHILD"
                    ((UNINSTALLED_COUNT++))
                fi
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
    local _HOME="${1:-$CLAUDE_HOME}"
    local SETTINGS="$_HOME/settings.json"
    # statusline 脚本通过 symlink 安装到目标目录的 custom-tools/ 下
    local COMMAND="\"$_HOME/custom-tools/statusline.sh\""

    echo "--- 配置 statusline ---"

    if ! command -v jq &>/dev/null; then
        echo "  ! jq 未安装，跳过 statusline 配置"
        echo "  提示: 安装 jq 后重新运行此脚本"
        return
    fi

    if [ ! -f "$SETTINGS" ]; then
        echo "  + 创建 settings.json"
        echo "{\"statusLine\":{\"type\":\"command\",\"command\":$COMMAND}}" | jq . > "$SETTINGS"
        chmod 600 "$SETTINGS"
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
    local _HOME="${1:-$CLAUDE_HOME}"
    local SETTINGS="$_HOME/settings.json"
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
    local _HOME="${1:-$CLAUDE_HOME}"
    local SETTINGS="$_HOME/settings.json"
    local ENGINE_SRC="$KNOWLEDGE_ENGINE_DIR/src/cli.ts"
    local KNOWLEDGE_DIR="$_HOME/knowledge"

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
    (cd "$KNOWLEDGE_ENGINE_DIR" && bun install --frozen-lockfile 2>/dev/null || bun install --no-save) || {
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
    local _HOME="${1:-$CLAUDE_HOME}"
    local SETTINGS="$_HOME/settings.json"

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

# ======================== Skill 注入 Hook 配置 ========================

configure_skill_inject() {
    local _HOME="${1:-$CLAUDE_HOME}"
    local SETTINGS="$_HOME/settings.json"
    local HOOK_CMD="bash \"\$HOME/.claude/hooks/skill-inject.sh\""

    echo "--- 配置 Skill 注入 Hook ---"

    if ! command -v jq &>/dev/null; then
        echo "  ! jq 未安装，跳过 Skill 注入 Hook 配置"
        return 1
    fi

    if [ ! -f "$SETTINGS" ]; then
        echo "  + 创建 settings.json"
        echo "{\"hooks\":{\"PreToolUse\":[{\"matcher\":\"Skill\",\"hooks\":[{\"type\":\"command\",\"command\":$HOOK_CMD,\"timeout\":5}]}]}}" | jq . > "$SETTINGS"
        chmod 600 "$SETTINGS"
        return
    fi

    # 检查是否已配置
    local CURRENT
    CURRENT=$(jq -r '.hooks.PreToolUse // [] | .[] | select(.matcher == "Skill") | .hooks // [] | .[] | select(.command == "'"$HOOK_CMD"'") | .command // empty' "$SETTINGS" 2>/dev/null) || true

    if [ "$CURRENT" = "$HOOK_CMD" ]; then
        echo "  ✓ Skill 注入 Hook 已配置，跳过"
        return
    fi

    echo "  + 更新 PreToolUse hook 配置..."
    local TMP
    TMP=$(mktemp)

    jq --arg cmd "$HOOK_CMD" '
      .hooks = (.hooks // {}) |
      .hooks.PreToolUse = (.hooks.PreToolUse // []) |
      .hooks.PreToolUse = (
        [.hooks.PreToolUse[] | .hooks = [.hooks[] | select(.command != $cmd)] | select((.hooks // []) | length > 0)]
        + [{
          "matcher": "Skill",
          "hooks": [{
            "type": "command",
            "command": $cmd,
            "timeout": 5
          }]
        }]
      )
    ' "$SETTINGS" > "$TMP"

    if [ -s "$TMP" ]; then
        mv "$TMP" "$SETTINGS"
        echo "  ✓ Skill 注入 Hook 已配置 (PreToolUse:Skill)"
    else
        rm -f "$TMP"
        echo "  ! 更新 settings.json 失败，请手动配置"
        return 1
    fi

    return 0
}

unconfigure_skill_inject() {
    local _HOME="${1:-$CLAUDE_HOME}"
    local SETTINGS="$_HOME/settings.json"
    local HOOK_CMD="bash \"\$HOME/.claude/hooks/skill-inject.sh\""

    echo "--- 移除 Skill 注入 Hook ---"

    if [ ! -f "$SETTINGS" ]; then
        echo "  未找到 settings.json，跳过"
        return
    fi

    if ! command -v jq &>/dev/null; then
        echo "  ! jq 未安装，跳过"
        return
    fi

    local TMP
    TMP=$(mktemp)

    jq --arg cmd "$HOOK_CMD" '
      .hooks.PreToolUse = (.hooks.PreToolUse // []) |
      .hooks.PreToolUse = [.hooks.PreToolUse[] | .hooks = [.hooks[] | select(.command != $cmd)]] |
      .hooks.PreToolUse = [.hooks.PreToolUse[] | select((.hooks // []) | length > 0)]
    ' "$SETTINGS" > "$TMP"

    if [ -s "$TMP" ]; then
        mv "$TMP" "$SETTINGS"
        echo "  ✓ Skill 注入 Hook 已移除"
    else
        rm -f "$TMP"
        echo "  ! 移除失败"
    fi
}

# ======================== 新交互主流程 ========================

new_handle_install() {
  # [1/4] 选择目标平台
  echo ""
  echo "--- [1/4] 选择目标平台 ---"
  show_target_menu
  local target_choice
  target_choice=$(get_choice "请输入选项 (1-4): " 1 4)

  local TARGET_DIRS=()
  local TARGET_NAMES=()
  case "$target_choice" in
    1)
      TARGET_DIRS=("$CLAUDE_HOME")
      TARGET_NAMES=("~/.claude")
      ;;
    2)
      if [ ! -d "$OPENCODE_HOME" ]; then
        echo "未检测到 OpenCode 目录 (~/.opencode)"
        return
      fi
      TARGET_DIRS=("$OPENCODE_HOME")
      TARGET_NAMES=("~/.opencode")
      ;;
    3)
      TARGET_DIRS=("$CLAUDE_HOME")
      TARGET_NAMES=("~/.claude")
      if [ -d "$OPENCODE_HOME" ]; then
        TARGET_DIRS+=("$OPENCODE_HOME")
        TARGET_NAMES+=("~/.opencode")
      fi
      ;;
    4) return ;;
  esac

  # [2/4] 选择模块
  reset_selections
  show_module_checklist

  # 检查是否有模块被选中
  local HAS_SELECTION=false
  local MODULE
  for MODULE in "${MODULES[@]+"${MODULES[@]}"}"; do
    local NAME
    NAME="$(parse_module_name "$MODULE")"
    if is_module_selected "$NAME"; then
      HAS_SELECTION=true
      break
    fi
  done

  if [ "$HAS_SELECTION" = false ]; then
    echo "未选择任何模块。"
    return
  fi

  # [3/4] 生成变更计划
  PLAN=()
  PLAN_BACKUPS=()

  local i
  for i in "${!TARGET_DIRS[@]}"; do
    local HOME_DIR="${TARGET_DIRS[$i]}"
    mkdir -p "$HOME_DIR"
    plan_install_for_home "$HOME_DIR"
  done

  if [ ${#PLAN[@]} -eq 0 ]; then
    echo "无需变更，所有选中模块已是最新状态。"
    return
  fi

  show_plan

  # [4/4] 确认执行
  echo ""
  read -p "确认执行以上变更? [y/N]: " CONFIRM
  if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "已取消。"
    return
  fi

  # 执行
  echo ""
  for i in "${!TARGET_DIRS[@]}"; do
    local HOME_DIR="${TARGET_DIRS[$i]}"
    local HOME_NAME="${TARGET_NAMES[$i]}"
    echo "--- 安装到 $HOME_NAME ---"

    local MODULE
    for MODULE in "${MODULES[@]+"${MODULES[@]}"}"; do
      local NAME TYPE
      NAME="$(parse_module_name "$MODULE")"
      TYPE="$(parse_module_type "$MODULE")"
      if ! is_module_selected "$NAME"; then continue; fi

      case "$TYPE" in
        settings|settings+deps)
          backup_settings "$HOME_DIR/settings.json"
          case "$NAME" in
            statusline)
              configure_statusline "$HOME_DIR"
              ;;
            skill-inject)
              configure_skill_inject "$HOME_DIR"
              ;;
            knowledge-engine)
              configure_knowledge_engine "$HOME_DIR"
              ;;
          esac
          ;;
      esac
    done
  done

  # 执行 symlink/file 类变更
  for i in "${!TARGET_DIRS[@]+"${TARGET_DIRS[@]}"}"; do
    BACKUP_DIR="${TARGET_DIRS[$i]}/bak"
    execute_plan
  done

  # 回滚提示
  if [ ${#PLAN_BACKUPS[@]} -gt 0 ]; then
    echo ""
    echo "回滚指令 (如需撤销):"
    local BACKUP
    for BACKUP in "${PLAN_BACKUPS[@]+"${PLAN_BACKUPS[@]}"}"; do
      local ORIG
      ORIG="$(basename "$BACKUP" | sed -E 's/_[0-9]{8}_[0-9]{6}$//')"
      echo "  cp $BACKUP $CLAUDE_HOME/$ORIG"
    done
  fi

  echo ""
  echo "安装完成。"
}

new_handle_uninstall() {
  echo ""
  show_target_menu
  local target_choice
  target_choice=$(get_choice "请输入选项 (1-4): " 1 4)

  case "$target_choice" in
    1)
      uninstall_for_home "$CLAUDE_HOME" "~/.claude"
      unconfigure_statusline
      echo ""
      unconfigure_knowledge_engine
      echo ""
      unconfigure_skill_inject
      log_install "UNINSTALL from ~/.claude" "all"
      ;;
    2)
      if [ -d "$OPENCODE_HOME" ]; then
        uninstall_for_home "$OPENCODE_HOME" "~/.opencode"
        log_install "UNINSTALL from ~/.opencode" "all"
      else
        echo "未检测到 OpenCode 目录"
      fi
      ;;
    3)
      uninstall_for_home "$CLAUDE_HOME" "~/.claude"
      unconfigure_statusline
      echo ""
      unconfigure_knowledge_engine
      echo ""
      unconfigure_skill_inject
      if [ -d "$OPENCODE_HOME" ]; then
        uninstall_for_home "$OPENCODE_HOME" "~/.opencode"
      fi
      log_install "UNINSTALL all" "all"
      ;;
    4) return ;;
  esac

  echo "卸载完成。"
}

# ======================== 入口 ========================

if [ "$DRY_RUN" = true ]; then
  reset_selections
  for MODULE in "${MODULES[@]+"${MODULES[@]}"}"; do
    set_selected "$(parse_module_name "$MODULE")" 1
  done
  PLAN=()
  PLAN_BACKUPS=()
  mkdir -p "$CLAUDE_HOME"
  plan_install_for_home "$CLAUDE_HOME"
  show_plan
else
  while true; do
    echo ""
    echo "=== Claude Code Tool 管理脚本 ==="
    echo ""
    echo "请选择操作:"
    echo "  1) 安装"
    echo "  2) 卸载"
    echo "  3) 退出"
    echo ""
    main_choice=$(get_choice "请输入选项 (1-3): " 1 3)

    case "$main_choice" in
      1) new_handle_install ;;
      2) new_handle_uninstall ;;
      3) echo ""; echo "再见!"; exit 0 ;;
    esac
  done
fi
