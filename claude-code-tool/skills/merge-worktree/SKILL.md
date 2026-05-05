---
name: merge-worktree
description: >
  完成 worktree 的完整合并流程：本地验证 → PR CI → merge → post-merge CI
  → 发布 → 清理 → 同步。使用 git merge --no-ff 保留完整分支历史。
  触发词："合并worktree"、"merge-worktree"、"合并PR"、"发布"、"release"、"上线"。
---

# Merge Worktree

## 流程总览

```
阶段 0: 读 CLAUDE.md
   ↓
阶段 1: pre-merge-check.sh ← 强制，不可跳过
   ↓
阶段 2: PR CI 检查 + gh pr merge
   ↓
阶段 3: wait-for-ci.sh ← post-merge CI，不可跳过
   ↓
阶段 4: 发布（项目脚本 或 merge-worktree-release.sh）
   ↓
阶段 5: merge-worktree.sh ← 清理 + 同步
```

**核心原则：每步验证失败必须修复，绝不跳过。AI 不得"选择跳过"任何步骤。**

## 合并策略

- **合并时**：`git merge --no-ff`，**绝不 Squash**
- **同步时**：`git merge origin/main`（非 rebase），已解决的冲突不会重复弹出

## 脚本清单

| 脚本 | 用途 | 退出码 0 以外 |
|------|------|-------------|
| `pre-merge-check.sh` | 5 步强制验证（自动装依赖） | 1 = 有失败，AI 必须修复 |
| `wait-for-ci.sh` | 等待 GitHub Actions CI | 1 = CI 失败，2 = 超时 |
| `merge-worktree-release.sh` | PR 合并 + 版本升级 + tag + release | 各步骤报错退出 |
| `merge-worktree.sh` | 清理 worktree + 同步其他分支 | 冲突保留供 AI 处理 |

## 脚本 1: pre-merge-check.sh

自动检测项目结构（monorepo/单包/前后端分离），运行完整验证。

```bash
bash ~/.claude/skills/merge-worktree/pre-merge-check.sh [worktree-dir]
```

| 步骤 | 检查 | 失败处理 |
|------|------|---------|
| 0. 依赖 | 动态检测 workspaces，缺 node_modules 自动 `npm ci` | 安装失败 → 人工介入 |
| 1. TypeScript | 遍历 tsconfig.json，优先用 typecheck 脚本，否则 tsc --noEmit | **必须修复** |
| 2. Lint | 根 lint → 子项目 lint → eslint 配置检测 | **必须修复**（含非自己修改的文件） |
| 3. 测试 | `npm test`，检测默认占位符并跳过 | **必须修复** |
| 4. 构建 | 根 build + 独立 frontend build | **必须修复** |
| 5. Git | 未提交变更 + 未推送 commits | **必须 commit + push** |

## 脚本 2: wait-for-ci.sh

```bash
wait-for-ci.sh <commit-sha> [--timeout 600] [--workflow <name>]
```

| 退出码 | 含义 | AI 行为 |
|--------|------|---------|
| 0 | CI 全部通过 | 继续后续流程 |
| 1 | CI 失败 | **必须修复**（main 上直接修或 revert） |
| 2 | 超时 | 询问用户 |

## 脚本 3: merge-worktree-release.sh

```bash
merge-worktree-release.sh <pr-number-or-branch> [--version patch|minor|major] [--skip-ci] [--skip-release]
```

6 步自动化：CI 检查 → Merge --no-ff → 更新 main → 版本升级 → Tag + Push → GitHub Release。

## 脚本 4: merge-worktree.sh

```bash
merge-worktree.sh <branch-name>
```

先同步其他 worktree，最后删除目标 worktree（因为 AI 会话可能在该目录中运行）。

---

## AI 操作步骤

### 阶段 0: 读 CLAUDE.md（必须首先执行）

读取项目 CLAUDE.md（优先 main worktree，回退当前 worktree），搜索关键词：
`发布流程`、`release`、`npm publish`、`tag`、`scripts/`、`测试`、`构建`

**决策树：发布脚本选择**
```
CLAUDE.md 是否指定了项目发布脚本？
  ├─ 是（如 scripts/publish.sh）→ 用项目脚本（阶段 4A）
  └─ 否 → 用 skill 自带的 merge-worktree-release.sh（阶段 4B）
```

### 阶段 1: 本地验证（不可跳过）

```bash
cd <feature-worktree>
bash ~/.claude/skills/merge-worktree/pre-merge-check.sh
```

- **退出码非零 → 必须修复后重跑，绝不跳过**
- 即使不是你修改的代码导致的失败，也必须修复
- 修复后 commit + push，然后重新运行脚本

### 阶段 2: PR CI + Merge

**2A: 检查 PR CI（等待通过）**

```bash
# 获取 PR CI 状态
PR_NUMBER=<PR 编号>
gh pr view "$PR_NUMBER" --json statusCheckRollup --jq \
  '.statusCheckRollup[] | "\(.name): \(.conclusion // .status)"'
```

| CI 状态 | 行为 |
|---------|------|
| 全部 `success` | 继续 merge |
| 有 `pending`/`queued`/`in_progress` | **等待**：每 30s 重查，最多等 10 分钟 |
| 有 `failure`/`cancelled` | **修复**：分析日志 → 本地修 → push → 重查 |

**等待 PR CI 的循环命令：**
```bash
# 等待 PR CI 完成（poll until all conclusions are final）
until gh pr view "$PR_NUMBER" --json statusCheckRollup --jq -e '
  .statusCheckRollup | all(.conclusion != null and .conclusion != "" and .conclusion != "pending" and .conclusion != "queued" and .conclusion != "in_progress" and .conclusion != "expected")
' 2>/dev/null; do
  echo "等待 PR CI 完成..."
  sleep 30
done

# 确认全部通过
gh pr view "$PR_NUMBER" --json statusCheckRollup --jq '
  .statusCheckRollup | map(.conclusion) | unique
'
# 如果包含 failure → 修复后重试
# 如果全是 success → 继续
```

**2B: 合并 PR**

```bash
gh pr merge "$PR_NUMBER" --no-ff --delete-branch
```

### 阶段 3: Post-merge CI（不可跳过）

**合并后 push 到 main 会触发 ci.yml，必须等待通过后才能发布。**

```bash
# 获取 merge 后 main 的最新 commit SHA
cd <workspace-root>
git fetch origin main
MAIN_SHA=$(git -C .bare rev-parse origin/main 2>/dev/null || git rev-parse origin/main)

# 等待 CI
bash ~/.claude/skills/merge-worktree/wait-for-ci.sh "$MAIN_SHA" --workflow "CI & Docker Build"
```

**CI 失败时：**
1. 查看日志：`gh run view <run-id> --log-failed`
2. 在 main worktree 中修复 → push → 重新 wait-for-ci.sh
3. 如果无法修复 → revert 合并

### 阶段 4: 发布

**仅在 post-merge CI 通过后执行。**

**4A: 项目有 scripts/publish.sh（CLAUDE.md 指定）**
```bash
cd <main-worktree>
bash scripts/publish.sh patch  # 或 minor / major
```

**publish.sh 失败时：**
1. 查看 CI 失败日志（publish.sh 会自动显示 `--log-failed`）
2. 常见原因：NPM_TOKEN 过期、Docker 构建失败、TypeScript 编译错误
3. 如果是代码问题：修复 → push → 等 post-merge CI → 重新 publish.sh
4. 如果是配置问题（token 等）：需要用户在 GitHub 更新 secret

**4B: 项目无发布脚本（用 merge-worktree-release.sh）**
```bash
bash ~/.claude/skills/merge-worktree/merge-worktree-release.sh <pr-number>
```
此脚本已包含 CI 检查 → merge → 版本升级 → tag → release 全流程。

### 阶段 5: Cleanup + Sync

```bash
# 先 cd 到 workspace root（避免删除当前工作目录）
cd <workspace-root>
bash ~/.claude/skills/merge-worktree/merge-worktree.sh <branch-name>
```

冲突处理：
```bash
git diff --name-only --diff-filter=U      # 冲突文件
git log --oneline origin/main..HEAD       # 当前分支改动
git add . && git commit                    # 解决后提交
```

---

## CI 触发模式参考

| 触发模式 | tag push 触发 | release 创建触发 |
|---------|:---:|:---:|
| `on: push: tags: ['v*']` | ✅ | ❌ |
| `on: release: types: [published]` | ❌ | ✅ |

**务必读 CLAUDE.md 确认项目的 CI 触发模式。**

## 教训记录

### 2025-05-05: 本地验证不完整 + Post-merge CI 未检查

**事件**：AI 因 worktree 缺 node_modules 跳过 vue-tsc 和 lint；合并后不等 post-merge CI 直接 publish。

**根因**：手动逐项检查无强制门控 → AI "合理化"跳过；无 post-merge CI 等待 → 可能发布坏版本。

**修复**：✅ pre-merge-check.sh（自动装依赖 + 5 步强制）✅ wait-for-ci.sh（post-merge CI 等待）✅ SKILL.md 6 阶段流程
