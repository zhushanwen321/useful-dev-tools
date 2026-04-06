#!/usr/bin/env bash
# lightmerge.sh - 多分支测试合并工具
# 用法见 SKILL.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_BASE_DIR="$HOME/.claude/lightmerge-data"

# ─── 工具函数 ────────────────────────────────────────────

get_config_path() {
    local project_name="$1"
    echo "${CONFIG_BASE_DIR}/${project_name}/lightmerge-branches.json"
}

ensure_config_dir() {
    local project_name="$1"
    local config_dir="${CONFIG_BASE_DIR}/${project_name}"
    mkdir -p "$config_dir"
}

read_config() {
    local config_path="$1"
    if [[ ! -f "$config_path" ]]; then
        echo "错误: 配置文件不存在: ${config_path}" >&2
        echo "请先运行 init 命令初始化。" >&2
        exit 1
    fi
    cat "$config_path"
}

write_config() {
    local config_path="$1"
    local config_content="$2"
    echo "$config_content" > "$config_path"
}

# 用 python3 解析 JSON（macOS 自带，无额外依赖）
json_get() {
    local config_path="$1"
    local key="$2"
    python3 -c "
import json, sys
with open('$config_path') as f:
    data = json.load(f)
result = data.get('$key', '')
if isinstance(result, list):
    print(json.dumps(result))
else:
    print(result)
"
}

json_set() {
    local config_path="$1"
    local key="$2"
    local value="$3"
    python3 -c "
import json
with open('$config_path') as f:
    data = json.load(f)
data['$key'] = $value
with open('$config_path', 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
print(json.dumps(data, indent=2, ensure_ascii=False))
"
}

json_array_append() {
    local config_path="$1"
    local key="$2"
    local new_item="$3"
    python3 -c "
import json
with open('$config_path') as f:
    data = json.load(f)
arr = data.get('$key', [])
if '$new_item' not in arr:
    arr.append('$new_item')
    data['$key'] = arr
    with open('$config_path', 'w') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    print(json.dumps(data, indent=2, ensure_ascii=False))
else:
    print('已存在: $new_item')
    print(json.dumps(data, indent=2, ensure_ascii=False))
"
}

json_array_remove() {
    local config_path="$1"
    local key="$2"
    local item="$3"
    python3 -c "
import json
with open('$config_path') as f:
    data = json.load(f)
arr = data.get('$key', [])
if '$item' in arr:
    arr.remove('$item')
    data['$key'] = arr
    with open('$config_path', 'w') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    print(json.dumps(data, indent=2, ensure_ascii=False))
else:
    print('不存在: $item')
    print(json.dumps(data, indent=2, ensure_ascii=False))
"
}

# ─── 获取项目名（git 仓库目录名）───

get_project_name() {
    basename "$(git rev-parse --show-toplevel 2>/dev/null || echo "unknown-project")"
}

# ─── 命令实现 ────────────────────────────────────────────

cmd_init() {
    local project_name="${1:-$(get_project_name)}"
    local base_branch="${2:-main}"
    local remote="${3:-origin}"
    local lm_branch="${4:-lightmerge}"
    local config_path

    config_path=$(get_config_path "$project_name")
    ensure_config_dir "$project_name"

    if [[ -f "$config_path" ]]; then
        echo "配置文件已存在: ${config_path}"
        echo "当前配置:"
        cat "$config_path"
        echo ""
        echo "如需重置，请手动删除配置文件后重新 init。"
        exit 0
    fi

    cat > "$config_path" << EOF
{
  "base_branch": "${base_branch}",
  "lightmerge_branch_name": "${lm_branch}",
  "remotes": ["${remote}"],
  "branches": []
}
EOF

    echo "初始化完成"
    echo "配置文件: ${config_path}"
    echo ""
    echo "当前配置:"
    cat "$config_path"
    echo ""
    echo "下一步: 使用 add <branch> 添加要合并的分支"
}

cmd_add() {
    local project_name="${1:-$(get_project_name)}"
    local branch_name="$2"
    local config_path

    if [[ -z "$branch_name" ]]; then
        echo "错误: 请指定要添加的分支名" >&2
        echo "用法: lightmerge.sh add <project-name> <branch-name>" >&2
        exit 1
    fi

    config_path=$(get_config_path "$project_name")

    echo "添加分支: ${branch_name}"
    json_array_append "$config_path" "branches" "$branch_name"

    echo ""
    cmd_rebuild "$project_name"
}

cmd_remove() {
    local project_name="${1:-$(get_project_name)}"
    local branch_name="$2"
    local config_path

    if [[ -z "$branch_name" ]]; then
        echo "错误: 请指定要移除的分支名" >&2
        echo "用法: lightmerge.sh remove <project-name> <branch-name>" >&2
        exit 1
    fi

    config_path=$(get_config_path "$project_name")

    echo "移除分支: ${branch_name}"
    json_array_remove "$config_path" "branches" "$branch_name"

    echo ""
    cmd_rebuild "$project_name"
}

cmd_rebuild() {
    local project_name="${1:-$(get_project_name)}"
    local config_path
    local base_branch
    local lm_branch
    local branches_json
    local remotes_json

    config_path=$(get_config_path "$project_name")

    # 读取配置
    base_branch=$(json_get "$config_path" "base_branch")
    lm_branch=$(json_get "$config_path" "lightmerge_branch_name")
    branches_json=$(json_get "$config_path" "branches")
    remotes_json=$(json_get "$config_path" "remotes")

    # 解析 branches 数组
    local branches=()
    while IFS= read -r line; do
        # 去除引号和空格
        line=$(echo "$line" | tr -d '"' | xargs)
        if [[ -n "$line" ]]; then
            branches+=("$line")
        fi
    done < <(echo "$branches_json" | python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
for item in data:
    print(item)
")

    # 解析 remotes 数组
    local remotes=()
    while IFS= read -r line; do
        line=$(echo "$line" | tr -d '"' | xargs)
        if [[ -n "$line" ]]; then
            remotes+=("$line")
        fi
    done < <(echo "$remotes_json" | python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
for item in data:
    print(item)
")

    echo "=== 重建 lightmerge 分支 ==="
    echo "Base branch: ${base_branch}"
    echo "Lightmerge branch: ${lm_branch}"
    echo "合并列表 (${#branches[@]} 个分支):"
    for i in "${!branches[@]}"; do
        echo "  $((i+1)). ${branches[$i]}"
    done
    echo ""

    # 保存当前分支，以便后续恢复
    local current_branch
    current_branch=$(git branch --show-current)

    # 拉取 base_branch 最新代码
    echo "更新 ${base_branch}..."
    git fetch origin "${base_branch}" 2>/dev/null || true
    git checkout "${base_branch}" 2>/dev/null || git checkout "origin/${base_branch}" -b "${base_branch}" 2>/dev/null
    git pull origin "${base_branch}" 2>/dev/null || true

    # 删除旧的 lightmerge 分支
    if git show-ref --verify --quiet "refs/heads/${lm_branch}"; then
        echo "删除旧的 ${lm_branch} 分支..."
        git branch -D "${lm_branch}"
    fi

    # 删除远端的 lightmerge 分支（所有 remote）
    for remote in "${remotes[@]}"; do
        if git show-ref --verify --quiet "refs/remotes/${remote}/${lm_branch}"; then
            echo "删除远端 ${remote}/${lm_branch}..."
            git push "${remote}" --delete "${lm_branch}" 2>/dev/null || true
        fi
    done

    # 从 base_branch 创建新的 lightmerge 分支
    echo "创建 ${lm_branch} 分支（基于 ${base_branch}）..."
    git checkout -b "${lm_branch}" "${base_branch}"

    # 逐个合并分支
    local success_count=0
    local fail_count=0
    local failed_branches=()

    for i in "${!branches[@]}"; do
        local branch="${branches[$i]}"
        echo ""
        echo "[$((i+1))/${#branches[@]}] 合并 ${branch}..."

        # 检查分支是否存在（本地或远端）
        if ! git show-ref --verify --quiet "refs/heads/${branch}" && \
           ! git show-ref --verify --quiet "refs/remotes/origin/${branch}"; then
            echo "  警告: 分支 ${branch} 不存在，跳过"
            failed_branches+=("${branch} (不存在)")
            fail_count=$((fail_count + 1))
            continue
        fi

        # 合并（不自动提交，以便检查冲突）
        if git merge --no-commit "${branch}" 2>/dev/null; then
            # 无冲突，提交合并
            git commit -m "lightmerge: 合并 ${branch}" 2>/dev/null || true
            echo "  成功"
            success_count=$((success_count + 1))
        else
            # 有冲突
            local conflict_files
            conflict_files=$(git diff --name-only --diff-filter=U 2>/dev/null || true)
            echo "  冲突! 以下文件有冲突:"
            echo "$conflict_files" | sed 's/^/    /'
            echo ""
            echo "  中止本次合并..."
            git merge --abort 2>/dev/null || true
            failed_branches+=("${branch} (合并冲突)")
            fail_count=$((fail_count + 1))
        fi
    done

    echo ""
    echo "=== 合并完成 ==="
    echo "成功: ${success_count} 个"
    echo "失败/跳过: ${fail_count} 个"
    if [[ ${#failed_branches[@]} -gt 0 ]]; then
        echo "失败分支:"
        for fb in "${failed_branches[@]}"; do
            echo "  - ${fb}"
        done
    fi

    # 推送到所有 remote
    if [[ ${success_count} -gt 0 ]]; then
        for remote in "${remotes[@]}"; do
            echo ""
            echo "推送到 ${remote}/${lm_branch}..."
            git push -u "${remote}" "${lm_branch}" 2>/dev/null && echo "推送成功" || echo "推送失败"
        done
    fi

    # 切回之前的分支
    if [[ -n "$current_branch" ]] && [[ "$current_branch" != "$lm_branch" ]]; then
        echo ""
        echo "切回原分支: ${current_branch}"
        git checkout "$current_branch" 2>/dev/null || true
    fi

    echo ""
    echo "=== lightmerge 完成 ==="
}

cmd_list() {
    local project_name="${1:-$(get_project_name)}"
    local config_path
    config_path=$(get_config_path "$project_name")

    if [[ ! -f "$config_path" ]]; then
        echo "尚未初始化。请先运行 init 命令。"
        exit 0
    fi

    echo "配置文件: ${config_path}"
    echo ""
    cat "$config_path"
    echo ""

    # 检查 lightmerge 分支状态
    local lm_branch
    lm_branch=$(json_get "$config_path" "lightmerge_branch_name")

    echo "分支状态:"
    if git show-ref --verify --quiet "refs/heads/${lm_branch}"; then
        echo "  本地: 存在"
    else
        echo "  本地: 不存在"
    fi

    local remotes_json
    remotes_json=$(json_get "$config_path" "remotes")
    while IFS= read -r remote; do
        remote=$(echo "$remote" | tr -d '"' | xargs)
        if [[ -n "$remote" ]]; then
            if git show-ref --verify --quiet "refs/remotes/${remote}/${lm_branch}"; then
                echo "  ${remote}: 存在"
            else
                echo "  ${remote}: 不存在"
            fi
        fi
    done < <(echo "$remotes_json" | python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
for item in data:
    print(item)
")
}

cmd_push() {
    local project_name="${1:-$(get_project_name)}"
    local config_path
    local lm_branch
    local remotes_json

    config_path=$(get_config_path "$project_name")
    lm_branch=$(json_get "$config_path" "lightmerge_branch_name")
    remotes_json=$(json_get "$config_path" "remotes")

    if ! git show-ref --verify --quiet "refs/heads/${lm_branch}"; then
        echo "错误: 本地不存在 ${lm_branch} 分支，请先 rebuild" >&2
        exit 1
    fi

    while IFS= read -r remote; do
        remote=$(echo "$remote" | tr -d '"' | xargs)
        if [[ -n "$remote" ]]; then
            echo "推送到 ${remote}/${lm_branch}..."
            git push -u "${remote}" "${lm_branch}" && echo "成功" || echo "失败"
        fi
    done < <(echo "$remotes_json" | python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
for item in data:
    print(item)
")
}

# ─── 主入口 ──────────────────────────────────────────────

usage() {
    echo "用法: lightmerge.sh <command> [args]"
    echo ""
    echo "命令:"
    echo "  init [project-name] [base-branch] [remote] [branch-name]  初始化配置"
    echo "  add <project-name> <branch>                 添加分支并重建"
    echo "  remove <project-name> <branch>              移除分支并重建"
    echo "  rebuild [project-name]                      重建 lightmerge 分支"
    echo "  list [project-name]                         查看当前配置"
    echo "  push [project-name]                         手动推送到远端"
    echo ""
    echo "默认 project-name 为当前 git 仓库目录名。"
}

main() {
    local command="${1:-}"
    shift || true

    case "$command" in
        init)
            cmd_init "$@"
            ;;
        add)
            cmd_add "$@"
            ;;
        remove)
            cmd_remove "$@"
            ;;
        rebuild)
            cmd_rebuild "$@"
            ;;
        list|"")
            cmd_list "$@"
            ;;
        push)
            cmd_push "$@"
            ;;
        -h|--help|help)
            usage
            ;;
        *)
            echo "未知命令: ${command}" >&2
            usage
            exit 1
            ;;
    esac
}

main "$@"
