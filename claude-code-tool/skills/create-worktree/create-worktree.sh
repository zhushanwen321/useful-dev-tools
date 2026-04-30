#!/bin/bash
# 在 bare repo + worktree 结构中创建新 worktree
# Usage: create-worktree.sh <branch-name> [base-branch]
# Example: create-worktree.sh feat/new-feature main
set -euo pipefail

# Source shared library
# Resolve to physical path (pwd -P follows directory symlinks)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/../_lib/workspace.sh"

BRANCH_NAME="${1:?Usage: create-worktree.sh <branch-name> [base-branch]}"
DIR_NAME="${BRANCH_NAME//\//-}"

WORKSPACE_ROOT=$(find_workspace_root "$(pwd)") || {
    echo "Error: 未找到 workspace。当前目录及其父目录中没有 .bare/。"
    exit 1
}
echo "Workspace: $WORKSPACE_ROOT"
cd "$WORKSPACE_ROOT"

# 自动检测基础分支：用户指定 > 远程 HEAD > 兜底 main
if [[ -n "${2:-}" ]]; then
    BASE_BRANCH="$2"
else
    BASE_BRANCH=$(git -C .bare remote show origin 2>/dev/null | grep 'HEAD branch' | awk '{print $NF}') || true
    BASE_BRANCH="${BASE_BRANCH:-main}"
fi
echo "基础分支: $BASE_BRANCH"

git -C .bare rev-parse --is-bare-repository >/dev/null 2>&1 || {
    echo "Error: .bare/ 不是一个有效的 bare git 仓库。"
    exit 1
}

[[ -d "$DIR_NAME" ]] && {
    echo "Error: 目录 '$DIR_NAME' 已存在。"
    exit 1
}

echo "Fetching from remote..."
git -C .bare fetch origin --prune

if git -C .bare rev-parse --verify "$BRANCH_NAME" >/dev/null 2>&1; then
    echo "分支 '$BRANCH_NAME' 已存在，直接检出..."
    git -C .bare worktree add "$WORKSPACE_ROOT/$DIR_NAME" "$BRANCH_NAME"
else
    BASE_REF="$BASE_BRANCH"
    if ! git -C .bare rev-parse --verify "$BASE_REF" >/dev/null 2>&1; then
        BASE_REF="origin/$BASE_BRANCH"
    fi
    echo "创建分支 '$BRANCH_NAME' (基于 $BASE_REF)..."
    git -C .bare worktree add "$WORKSPACE_ROOT/$DIR_NAME" -b "$BRANCH_NAME" "$BASE_REF"
fi

WORKTREE_PATH="$WORKSPACE_ROOT/$DIR_NAME"

# 从 main/master worktree 复制 .claude 本地配置
for main_wt in main master; do
    if [[ -f "$WORKSPACE_ROOT/$main_wt/.claude/settings.local.json" ]] && [[ -d "$WORKTREE_PATH/.claude" ]]; then
        cp "$WORKSPACE_ROOT/$main_wt/.claude/settings.local.json" "$WORKTREE_PATH/.claude/"
        echo "已复制 .claude/settings.local.json (from $main_wt)"
        break
    fi
done

cd "$WORKTREE_PATH"

# 自动检测并安装依赖
[[ -f "frontend/package.json" ]] && { echo "安装前端依赖..."; (cd frontend && pnpm install 2>&1 | tail -1) || (cd frontend && npm install 2>&1 | tail -1); }
[[ -f "package.json" ]] && [[ ! -d "frontend" ]] && { npm install 2>&1 | tail -1; }
[[ -f "backend/pyproject.toml" ]] && { echo "安装后端依赖..."; (cd backend && uv sync 2>&1 | tail -1); }

# 安装 git hooks（从已安装的 worktree 复制）
install_hooks() {
    local hooks_source=""
    for wt in main master; do
        local git_dir
        git_dir="$WORKSPACE_ROOT/$wt/.git"
        if [[ -f "$git_dir" ]]; then
            git_dir=$(cd "$WORKSPACE_ROOT/$wt" && git rev-parse --git-dir 2>/dev/null)/hooks
            [[ -f "$git_dir/pre-commit" ]] && { hooks_source="$git_dir"; break; }
        fi
    done

    if [[ -n "$hooks_source" ]]; then
        local worktree_hooks
        worktree_hooks=$(git rev-parse --git-dir 2>/dev/null)/hooks
        mkdir -p "$worktree_hooks"
        cp "$hooks_source/pre-commit" "$worktree_hooks/"
        chmod +x "$worktree_hooks/pre-commit"
        echo "已安装 git hooks"
    fi
}
install_hooks

echo ""
echo "============================================"
echo "Worktree 创建完成!"
echo "  分支: $BRANCH_NAME"
echo "  路径: $WORKTREE_PATH"
echo "============================================"
