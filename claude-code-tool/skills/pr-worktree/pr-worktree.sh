#!/bin/bash
# 提交推送并创建/更新 PR
# Usage: pr-worktree.sh [--draft] [--title "xxx"] [--body "xxx"] [--base main]
# 前提: 当前在 worktree 目录中，变更已 commit
# 如果未提供 --title，从最新 commit message 提取
# 如果未提供 --body，从 commit message body 或 diff --stat 生成
set -euo pipefail

# --- 参数解析 ---
DRAFT=false
TITLE=""
BODY=""
BASE="main"
EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --draft)   DRAFT=true; shift ;;
        --title)   TITLE="$2"; shift 2 ;;
        --body)    BODY="$2"; shift 2 ;;
        --base)    BASE="$2"; shift 2 ;;
        --)        shift; EXTRA_ARGS+=("$@"); break ;;
        *)         EXTRA_ARGS+=("$1"); shift ;;
    esac
done

# --- 前置检查 ---
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || {
    echo "Error: 不在 git 仓库中。"; exit 1;
}

# 检查是否有未提交的变更
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
    echo "Warning: 有未提交的变更。请先 commit 或 stash。"
    git status --short
    exit 1
fi

echo "当前分支: $BRANCH"

# 检查 gh CLI
command -v gh >/dev/null 2>&1 || { echo "Error: gh CLI 未安装。"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Error: gh CLI 未登录，请运行 gh auth login。"; exit 1; }

# --- 提取 commit 信息 ---
if [[ -z "$TITLE" ]]; then
    TITLE=$(git log -1 --format="%s")
fi

if [[ -z "$BODY" ]]; then
    # 尝试从 commit body 获取
    COMMIT_BODY=$(git log -1 --format="%b")
    if [[ -n "$COMMIT_BODY" ]]; then
        BODY="$COMMIT_BODY"
    else
        # 从 diff stat 生成
        BODY=$(git diff --stat origin/"$BASE"...HEAD 2>/dev/null || git diff --stat HEAD~1..HEAD)
    fi
fi

# --- 推送 ---
echo ""
echo "=== 推送到远程 ==="
PUSH_ARGS=("-u" "origin" "$BRANCH")
if git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then
    # 已有上游分支
    PUSH_ARGS=("origin" "$BRANCH")
fi

if ! git push "${PUSH_ARGS[@]}" 2>&1; then
    echo ""
    echo "Error: 推送失败。可能远程有更新，尝试 pull --rebase..."
    if git pull --rebase origin "$BRANCH" 2>&1; then
        echo "Rebase 成功，重新推送..."
        git push -u origin "$BRANCH" 2>&1
    else
        echo "Error: rebase 失败，请手动解决冲突后重试。"
        exit 1
    fi
fi

# --- 检查已有 PR ---
echo ""
echo "=== 检查已有 PR ==="
EXISTING_PR=$(gh pr list --head "$BRANCH" --json number,title,state --jq '.[0]' 2>/dev/null || echo "")

if [[ "$EXISTING_PR" != "" ]] && [[ "$EXISTING_PR" != "null" ]] && [[ "$EXISTING_PR" != "{}" ]]; then
    PR_NUMBER=$(echo "$EXISTING_PR" | jq -r '.number')
    PR_STATE=$(echo "$EXISTING_PR" | jq -r '.state')
    echo "已有 PR #$PR_NUMBER (状态: $PR_STATE)，更新中..."

    gh pr edit "$PR_NUMBER" --title "$TITLE" --body "$BODY"

    PR_URL=$(gh pr view "$PR_NUMBER" --json url --jq '.url')
    echo ""
    echo "============================================"
    echo "PR 已更新!"
    echo "  PR: #$PR_NUMBER"
    echo "  URL: $PR_URL"
    echo "============================================"
else
    # --- 创建 PR ---
    echo "未找到已有 PR，创建新 PR..."

    PR_ARGS=("pr" "create" "--title" "$TITLE" "--body" "$BODY" "--base" "$BASE")
    $DRAFT && PR_ARGS+=("--draft")
    PR_ARGS+=("${EXTRA_ARGS[@]}")

    PR_URL=$(gh "${PR_ARGS[@]}" 2>&1 | tail -1)

    # 提取 PR number
    PR_NUMBER=$(echo "$PR_URL" | grep -oE '[0-9]+$' || echo "?")

    echo ""
    echo "============================================"
    echo "PR 已创建!"
    echo "  PR: #$PR_NUMBER"
    echo "  URL: $PR_URL"
    $DRAFT && echo "  类型: Draft"
    echo "============================================"
fi
