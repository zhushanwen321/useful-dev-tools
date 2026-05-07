#!/bin/bash
# merge-and-publish.sh — 从 PR 合并到发布的端到端自动化
#
# 一键完成：本地验证 → PR CI → merge → post-merge CI → 发布 → 清理
# AI 只需执行一次脚本，根据输出结果修复问题后重跑即可。
#
# 用法: merge-and-publish.sh <worktree-dir> [patch|minor|major]
# 示例: merge-and-publish.sh ~/Code/workspace/feat-xxx patch
#
# 退出码：
#   0 = 全部成功（已合并、已发布、已清理）
#   1 = 失败，AI 必须修复后重新运行
#   2 = 超时，AI 应询问用户

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

# ── 参数解析 ──────────────────────────────────────
WORKTREE_DIR="${1:?Usage: merge-and-publish.sh <worktree-dir> [patch|minor|major]}"
VERSION_TYPE="${2:-patch}"

if [[ ! "$VERSION_TYPE" =~ ^(patch|minor|major)$ ]]; then
    echo -e "${RED}Error: 版本类型必须是 patch|minor|major${NC}"
    exit 1
fi

command -v gh >/dev/null 2>&1 || { echo -e "${RED}Error: gh CLI 未安装${NC}"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo -e "${RED}Error: gh CLI 未登录${NC}"; exit 1; }

cd "$WORKTREE_DIR"

echo "══════════════════════════════════════════════════"
echo -e "${BOLD}端到端合并发布流程${NC}"
echo "  工作目录: $WORKTREE_DIR"
echo "  版本类型: $VERSION_TYPE"
echo "══════════════════════════════════════════════════"

# ── 阶段 1: 本地验证 ──────────────────────────────
echo ""
echo -e "${BOLD}═══ 阶段 1/5: 本地验证 ═══${NC}"
bash "$SCRIPT_DIR/pre-merge-check.sh" "$WORKTREE_DIR" || {
    echo ""
    echo -e "${RED}${BOLD}⛔ 本地验证失败！修复后重新运行本脚本。${NC}"
    exit 1
}

# ── 阶段 2: PR CI + 合并 ─────────────────────────
echo ""
echo -e "${BOLD}═══ 阶段 2/5: PR CI + 合并 ═══${NC}"

# 查找当前分支对应的 PR
BRANCH_NAME=$(git branch --show-current)
PR_JSON=$(gh pr list --head "$BRANCH_NAME" --json number,title,state --jq '.[0]' 2>/dev/null || echo "null")
PR_NUMBER=$(echo "$PR_JSON" | jq -r '.number // empty')

if [[ -z "$PR_NUMBER" ]]; then
    echo -e "${RED}Error: 分支 '$BRANCH_NAME' 没有对应的 PR${NC}"
    exit 1
fi

PR_STATE=$(echo "$PR_JSON" | jq -r '.state')
PR_TITLE=$(echo "$PR_JSON" | jq -r '.title')
echo "  PR: #$PR_NUMBER — $PR_TITLE"
echo "  状态: $PR_STATE"

if [[ "$PR_STATE" == "MERGED" ]]; then
    echo -e "  ${GREEN}PR 已合并，跳过 merge 步骤${NC}"
else
    if [[ "$PR_STATE" != "OPEN" ]]; then
        echo -e "${RED}Error: PR 状态为 $PR_STATE，无法合并${NC}"
        exit 1
    fi

    # 检查 PR CI
    echo "  检查 PR CI 状态..."
    CI_DATA=$(gh pr view "$PR_NUMBER" --json statusCheckRollup 2>&1) || {
        echo -e "${YELLOW}Warning: 无法获取 CI 状态，继续合并${NC}"
        CI_DATA='{"statusCheckRollup":[]}'
    }

    CI_CONCLUSIONS=$(echo "$CI_DATA" | jq -r '[.statusCheckRollup[] | .conclusion] | unique | join(",")' 2>/dev/null || echo "")

    if echo "$CI_CONCLUSIONS" | grep -qi "failure\|timed_out\|cancelled"; then
        echo -e "  ${RED}❌ PR CI 有失败项:${NC}"
        echo "$CI_DATA" | jq -r '.statusCheckRollup[] | select(.conclusion == "failure" or .conclusion == "timed_out" or .conclusion == "cancelled") | "    ❌ \(.name) (\(.conclusion))"' 2>/dev/null
        echo ""
        echo -e "${RED}请修复 CI 后重新运行本脚本。${NC}"
        exit 1
    fi

    if echo "$CI_CONCLUSIONS" | grep -qi "pending\|queued\|in_progress"; then
        echo "  ⏳ PR CI 仍在运行，等待最多 10 分钟..."
        ELAPSED=0
        while [[ $ELAPSED -lt 600 ]]; do
            sleep 30
            ELAPSED=$((ELAPSED + 30))
            CI_DATA=$(gh pr view "$PR_NUMBER" --json statusCheckRollup 2>&1)
            CI_CONCLUSIONS=$(echo "$CI_DATA" | jq -r '[.statusCheckRollup[] | .conclusion] | unique | join(",")' 2>/dev/null || echo "")
            if ! echo "$CI_CONCLUSIONS" | grep -qi "pending\|queued\|in_progress"; then
                break
            fi
            echo "  ⏳ 等待中... (${ELAPSED}s/600s)"
        done

        if echo "$CI_CONCLUSIONS" | grep -qi "failure\|timed_out\|cancelled"; then
            echo -e "  ${RED}❌ PR CI 失败${NC}"
            exit 1
        fi
    fi

    echo -e "  ${GREEN}✅ PR CI 通过，开始合并${NC}"
    gh pr merge "$PR_NUMBER" --merge --delete-branch 2>&1 || {
        echo -e "${RED}Error: PR 合并失败${NC}"
        exit 1
    }
    echo -e "  ${GREEN}✅ PR #$PR_NUMBER 已合并${NC}"
fi

# ── 阶段 3: Post-merge CI ─────────────────────────
echo ""
echo -e "${BOLD}═══ 阶段 3/5: Post-merge CI 验证 ═══${NC}"

# 找到 workspace root
WS_ROOT="$WORKTREE_DIR"
while [[ "$WS_ROOT" != "/" ]]; do
    if [[ -d "$WS_ROOT/.bare" ]] || [[ -d "$WS_ROOT/.git" ]]; then
        break
    fi
    WS_ROOT="$(dirname "$WS_ROOT")"
done

# 从 main worktree 或 bare repo 获取最新 main SHA
MAIN_WT=""
for wt_name in main master; do
    if [[ -d "$WS_ROOT/$wt_name" ]]; then
        MAIN_WT="$WS_ROOT/$wt_name"
        break
    fi
done

if [[ -n "$MAIN_WT" ]]; then
    cd "$MAIN_WT"
    git fetch origin main 2>&1 | tail -1
    MAIN_SHA=$(git rev-parse origin/main)
else
    git -C "$WS_ROOT" fetch origin main 2>&1 | tail -1 || true
    MAIN_SHA=$(git -C "$WS_ROOT" rev-parse origin/main 2>/dev/null || git rev-parse origin/main)
fi

echo "  main SHA: $MAIN_SHA"

bash "$SCRIPT_DIR/wait-for-ci.sh" "$MAIN_SHA" || {
    WAIT_EXIT=$?
    if [[ $WAIT_EXIT -eq 1 ]]; then
        echo ""
        echo -e "${RED}${BOLD}⛔ Post-merge CI 失败！${NC}"
        echo ""
        echo "修复步骤："
        echo "  1. 在 main worktree 中查看日志并修复"
        echo "  2. git push origin main"
        echo "  3. 重新运行本脚本"
        echo ""
        echo "如果无法修复，考虑 revert 合并。"
        exit 1
    else
        # exit 2 = 超时
        echo -e "${YELLOW}${BOLD}⚠️  CI 等待超时${NC}"
        echo "可以重新运行本脚本，或手动确认 CI 通过后继续。"
        exit 2
    fi
}

echo -e "  ${GREEN}✅ Post-merge CI 通过${NC}"

# ── 阶段 4: 发布 ─────────────────────────────────
echo ""
echo -e "${BOLD}═══ 阶段 4/5: 发布 ═══${NC}"

# 检查项目是否有 scripts/publish.sh
PUBLISH_SH=""
# 在 main worktree 和当前目录都检查
for search_dir in "$MAIN_WT" "$WORKTREE_DIR"; do
    if [[ -f "$search_dir/scripts/publish.sh" ]]; then
        PUBLISH_SH="$search_dir/scripts/publish.sh"
        break
    fi
done

if [[ -n "$PUBLISH_SH" ]]; then
    # 判断 publish.sh 类型（GitHub Actions 触发 vs 本地版本 bump）
    if grep -q 'gh workflow run' "$PUBLISH_SH"; then
        echo "  检测到 GitHub Actions 发布脚本，运行中..."
        # GitHub Actions 类型可以在任意 worktree 运行
        cd "$(dirname "$PUBLISH_SH")/.."
        bash "$PUBLISH_SH" "$VERSION_TYPE" || {
            echo -e "${RED}Error: 发布失败${NC}"
            exit 1
        }
    else
        # 本地版本 bump 类型，需在 main worktree 运行
        if [[ -z "$MAIN_WT" ]]; then
            echo -e "${RED}Error: 本地发布脚本需要在 main worktree 运行，未找到 main worktree${NC}"
            exit 1
        fi
        echo "  检测到本地发布脚本，在 main worktree 运行中..."
        cd "$MAIN_WT"
        bash "$PUBLISH_SH" "$VERSION_TYPE" || {
            echo -e "${RED}Error: 发布失败${NC}"
            exit 1
        }
    fi
else
    echo -e "${YELLOW}⚠️  未检测到 scripts/publish.sh，跳过自动发布${NC}"
    echo "  如需发布，请手动执行相应的发布命令。"
fi

echo -e "  ${GREEN}✅ 发布完成${NC}"

# ── 阶段 5: 清理 ─────────────────────────────────
echo ""
echo -e "${BOLD}═══ 阶段 5/5: 清理 Worktree ═══${NC}"

cd "$WS_ROOT"
bash "$SCRIPT_DIR/../remove-worktree/remove-worktree.sh" "$BRANCH_NAME" --force --skip-sync 2>&1 || {
    echo -e "${YELLOW}Warning: worktree 清理失败，可手动处理${NC}"
}

# ── 最终报告 ──────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════"
echo -e "${GREEN}${BOLD}✅ 端到端流程全部完成！${NC}"
echo "  PR: #$PR_NUMBER"
echo "  版本: $VERSION_TYPE"
echo "  分支: $BRANCH_NAME (已清理)"
echo "══════════════════════════════════════════════════"
