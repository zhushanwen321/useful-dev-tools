#!/bin/bash
# 删除 bare repo + worktree 结构中的 worktree
# Usage: remove-worktree.sh <branch-name> [--delete-branch]
# Example: remove-worktree.sh feat/old-feature --delete-branch
set -euo pipefail

BRANCH_NAME="${1:?Usage: remove-worktree.sh <branch-name> [--delete-branch]}"
DELETE_BRANCH=false
[[ "${2:-}" == "--delete-branch" ]] && DELETE_BRANCH=true
DIR_NAME="${BRANCH_NAME//\//-}"

# 保护主分支
if [[ "$DIR_NAME" == "master" || "$DIR_NAME" == "main" ]]; then
    echo "Error: 不能删除主分支 worktree。"
    exit 1
fi

# 查找 workspace 根
find_workspace_root() {
    local dir="$1"
    while [[ "$dir" != "/" ]]; do
        [[ -d "$dir/.bare" ]] && { echo "$dir"; return 0; }
        dir="$(cd "$dir/.." && pwd)"
    done
    return 1
}

WORKSPACE_ROOT=$(find_workspace_root "$(pwd)") || {
    echo "Error: 未找到 workspace。"
    exit 1
}

WORKTREE_PATH="$WORKSPACE_ROOT/$DIR_NAME"

[[ ! -d "$WORKTREE_PATH" ]] && {
    echo "Error: worktree '$DIR_NAME' 不存在。"
    echo "现有 worktree:"
    git -C "$WORKSPACE_ROOT/.bare" worktree list --porcelain | grep "^worktree" | sed 's/worktree /  /'
    exit 1
}

# 检查未提交的更改
if ! git -C "$WORKTREE_PATH" diff --quiet 2>/dev/null || \
   ! git -C "$WORKTREE_PATH" diff --cached --quiet 2>/dev/null; then
    echo "Error: '$DIR_NAME' 有未提交的更改，请先提交或 stash 后再删除。"
    git -C "$WORKTREE_PATH" status --short
    exit 1
fi

# 检查未推送的提交
TRACKING=$(git -C "$WORKTREE_PATH" rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || true)
if [[ -n "$TRACKING" ]]; then
    UNPUSHED=$(git -C "$WORKTREE_PATH" log @{u}..HEAD --oneline 2>/dev/null || true)
    if [[ -n "$UNPUSHED" ]]; then
        echo "Warning: '$DIR_NAME' 有未推送的提交:"
        echo "$UNPUSHED" | sed 's/^/  /'
        if ! $DELETE_BRANCH; then
            echo "提示: 使用 --delete-branch 会同时删除本地分支，未推送的提交将丢失。"
            echo "建议: 先 push，或在删除前合并到其他分支。"
        fi
    fi
fi

# 删除 worktree
echo "删除 worktree '$DIR_NAME'..."
git -C "$WORKSPACE_ROOT/.bare" worktree remove "$WORKTREE_PATH"

# 可选删除分支
if $DELETE_BRANCH; then
    if git -C "$WORKSPACE_ROOT/.bare" rev-parse --verify "$BRANCH_NAME" >/dev/null 2>&1; then
        echo "删除本地分支 '$BRANCH_NAME'..."
        git -C "$WORKSPACE_ROOT/.bare" branch -d "$BRANCH_NAME" 2>/dev/null || \
            git -C "$WORKSPACE_ROOT/.bare" branch -D "$BRANCH_NAME"
    fi
fi

echo ""
echo "============================================"
echo "Worktree 已删除!"
echo "  分支: $BRANCH_NAME"
$DELETE_BRANCH && echo "  本地分支已删除" || echo "  本地分支保留 (如需删除: git -C .bare branch -d $BRANCH_NAME)"
echo "============================================"
