#!/bin/bash
# 在 bare repo + worktree 结构中创建新 worktree
# Usage: create-worktree.sh <branch-name> [base-branch]
# Example: create-worktree.sh feat/new-feature master
set -euo pipefail

BRANCH_NAME="${1:?Usage: create-worktree.sh <branch-name> [base-branch]}"
BASE_BRANCH="${2:-master}"
# 分支名转目录名: feature/xxx -> feature-xxx
DIR_NAME="${BRANCH_NAME//\//-}"

# 从当前目录向上查找 workspace 根（包含 .bare/ 的目录）
find_workspace_root() {
    local dir="$1"
    while [[ "$dir" != "/" ]]; do
        if [[ -d "$dir/.bare" ]]; then
            echo "$dir"
            return 0
        fi
        dir="$(cd "$dir/.." && pwd)"
    done
    return 1
}

WORKSPACE_ROOT=$(find_workspace_root "$(pwd)") || {
    echo "Error: 未找到 workspace。当前目录及其父目录中没有 .bare/。"
    exit 1
}
echo "Workspace: $WORKSPACE_ROOT"
cd "$WORKSPACE_ROOT"

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
    # 优先用 bare repo 本地分支（worktree 工作流中最新的），回退到远程跟踪引用
    BASE_REF="$BASE_BRANCH"
    if ! git -C .bare rev-parse --verify "$BASE_REF" >/dev/null 2>&1; then
        BASE_REF="origin/$BASE_BRANCH"
    fi
    echo "创建分支 '$BRANCH_NAME' (基于 $BASE_REF)..."
    git -C .bare worktree add "$WORKSPACE_ROOT/$DIR_NAME" -b "$BRANCH_NAME" "$BASE_REF"
fi

WORKTREE_PATH="$WORKSPACE_ROOT/$DIR_NAME"

# 从 master worktree 复制 .claude 本地配置
if [[ -f "$WORKSPACE_ROOT/master/.claude/settings.local.json" ]] && [[ -d "$WORKTREE_PATH/.claude" ]]; then
    cp "$WORKSPACE_ROOT/master/.claude/settings.local.json" "$WORKTREE_PATH/.claude/"
    echo "已复制 .claude/settings.local.json"
fi

cd "$WORKTREE_PATH"

# 自动检测并安装依赖
[[ -f "backend/pyproject.toml" ]] && { echo "安装后端依赖..."; (cd backend && uv sync 2>&1 | tail -1); }
[[ -f "frontend/package.json" ]] && { echo "安装前端依赖..."; (cd frontend && pnpm install 2>&1 | tail -1); }

# 安装 git hooks（worktree 兼容：从 master worktree 复制已安装的 hooks）
install_hooks() {
    local master_hooks="$WORKSPACE_ROOT/master/.git"
    if [[ -f "$master_hooks" ]]; then
        master_hooks=$(cd "$WORKSPACE_ROOT/master" && git rev-parse --git-dir 2>/dev/null)/hooks
    elif [[ -d "$master_hooks" ]]; then
        master_hooks="$master_hooks/hooks"
    else
        return
    fi

    local worktree_hooks
    worktree_hooks=$(git rev-parse --git-dir 2>/dev/null)/hooks

    if [[ -f "$master_hooks/pre-commit" ]]; then
        mkdir -p "$worktree_hooks"
        cp "$master_hooks/pre-commit" "$worktree_hooks/"
        chmod +x "$worktree_hooks/pre-commit"
        echo "已安装 git hooks (从 master worktree 复制)"
    fi
}
install_hooks

echo ""
echo "============================================"
echo "Worktree 创建完成!"
echo "  分支: $BRANCH_NAME"
echo "  路径: $WORKTREE_PATH"
echo "============================================"
