---
name: merge-worktree
description: >
  完成 worktree 的完整合并流程：检查 CI → 修复问题 → merge --no-ff PR → 升级版本号 →
  打 tag → release → 清理 worktree → 同步其他 worktree 到最新 main。
  合并策略：使用 git merge --no-ff 保留完整分支历史，绝不 Squash。
  同步策略：使用 git merge origin/main 而非 rebase，保留真实开发轨迹，
  已解决的冲突不会重复弹出。
  当用户说"合并worktree"、"merge-worktree"、"合并PR"、"发布版本"、"release"、
  "上线"、"合并分支"、"发布"时使用此 skill。
---

# Merge Worktree

完成 worktree 从开发到发布的完整流程。分为两个阶段：
1. **Release**（脚本化）：CI 检查 → merge --no-ff → 版本升级 → tag → release
2. **Cleanup + Sync**（脚本 + AI）：清理 worktree → 同步其他 worktree（冲突时 AI 介入）

## 合并策略（模式 B：保留合并提交）

本项目采用 **模式 B** 合并策略：
- **合并时**：使用 `git merge --no-ff` 将分支合入 main，**绝不 Squash**
- **同步时**：使用 `git merge origin/main` 而非 rebase

**原因**：
1. 保留完整的分支拓扑，历史图有分叉是真实的开发轨迹
2. `git merge origin/main` 解决的冲突被永久记录在合并提交中，以后不会再弹出相同冲突
3. 对长期并行的复杂项目非常友好
4. 已解决的冲突不会重复弹出

## 脚本 1: merge-worktree-release.sh

合并 PR 并执行发布流程。**CI 失败之外的步骤全部自动化。**

```bash
merge-worktree-release.sh <pr-number-or-branch> [--version patch|minor|major] [--skip-ci] [--skip-release]
```

### 参数

| 参数 | 位置/标志 | 必填 | 说明 |
|------|----------|------|------|
| `pr-number-or-branch` | $1 | 是 | PR 编号（数字）或分支名（如 `feat/new-feature`） |
| `--version` | flag | 否 | 版本升级类型：`patch`（默认）/ `minor` / `major` / `prerelease` |
| `--skip-ci` | flag | 否 | 跳过 CI 检查（已确认通过时使用） |
| `--skip-release` | flag | 否 | 跳过 GitHub Release 创建 |

### 用法示例

```bash
# 基本用法：合并 PR #42，patch 版本升级，自动创建 release
bash ~/.claude/skills/merge-worktree/merge-worktree-release.sh 42

# 用分支名代替 PR 编号
bash ~/.claude/skills/merge-worktree/merge-worktree-release.sh feat/new-feature

# minor 版本升级
bash ~/.claude/skills/merge-worktree/merge-worktree-release.sh 42 --version minor

# CI 已确认通过，跳过检查
bash ~/.claude/skills/merge-worktree/merge-worktree-release.sh 42 --skip-ci

# 只合并和升级版本，不创建 GitHub Release
bash ~/.claude/skills/merge-worktree/merge-worktree-release.sh 42 --skip-release
```

### 脚本行为（6 步自动化流程）

| 步骤 | 操作 | 失败处理 |
|------|------|---------|
| 1. CI 检查 | `gh pr view --json statusCheckRollup` 检查所有检查项状态 | 有失败时报错退出，列出失败项 |
| 2. Merge --no-ff | `git merge --no-ff` 保留完整分支历史 | — |
| 3. 更新 main | 在 main worktree 中 `git pull`，无 worktree 时用 `git -C .bare branch -f main` | — |
| 4. 版本升级 | 幂等检查：最新 commit 含 "bump version" 则跳过。否则 `npm version <type> --no-git-tag-version` | 非 npm 项目跳过 |
| 5. Tag + Push | `git add && git commit && git tag && git push origin main --tags` | — |
| 6. GitHub Release | `gh release create` ，notes 从 PR title+body 生成 | Tag 已有 release 时 warn |

### 输出

```
Workspace: /path/to/project-workspace
PR: #42

=== 步骤 1: 检查 CI ===
CI 状态: SUCCESS, SKIPPED
CI 检查通过。

=== 步骤 2: Merge --no-ff PR #42 ===
标题: feat: add dark mode
分支: feat/new-feature
PR 已合并（保留完整分支历史）。

=== 步骤 3: 更新 main 分支 ===
使用 main worktree: /path/to/project-workspace/main

=== 步骤 4: 版本升级 ===
版本升级: 0.6.5 -> 0.6.6

=== 步骤 5: 提交版本变更、打 tag、推送 ===
Tag: v0.6.6

=== 步骤 6: 创建 GitHub Release ===
Release: https://github.com/xxx/releases/tag/v0.6.6

============================================
Release 完成!
  PR: #42
  版本: v0.6.6
  Tag: v0.6.6
  Release: https://github.com/xxx/releases/tag/v0.6.6
============================================

下一步: 运行 merge-worktree.sh feat/new-feature 清理 worktree 并同步其他分支
```

### 错误场景

| 输出 | 原因 | 解决 |
|------|------|------|
| `CI 有失败的检查项` | CI 未全部通过 | 修复 CI 问题后重试，或 `--skip-ci` 跳过 |
| `找不到分支对应的 PR` | 分支名无对应 PR | 使用 PR 编号代替分支名 |
| `gh CLI 未登录` | gh 未认证 | `gh auth login` |
| `版本升级已包含` | 最新 commit 已 bump | 脚本自动跳过，使用现有版本 |
| `Tag 已存在` | 版本号重复 | 检查是否重复发布 |
| `Merge 冲突` | main 和分支有冲突 | 手动解决后 `git add . && git commit` |

## 脚本 2: merge-worktree.sh

清理已合并的 worktree 并同步其他 worktree 到最新 main。

```bash
merge-worktree.sh <branch-name>
```

### 参数

| 参数 | 位置 | 必填 | 说明 |
|------|------|------|------|
| `branch-name` | $1 | 是 | 要清理的分支名（已合并） |

### 用法示例

```bash
# 清理 worktree 并同步其他分支
bash ~/.claude/skills/merge-worktree/merge-worktree.sh feat/new-feature
```

### 脚本行为

**执行顺序：先同步、后删除。** 因为 AI 会话可能在被清理的 worktree 目录中运行，如果先删除目录，bash 工具会因工作目录不存在而全部失败。

1. 立即 `cd` 到 workspace root（离开可能被删除的 worktree 目录）
2. 遍历其他所有 worktree，`git fetch origin main && git merge origin/main`
3. 冲突时不 abort，保留冲突状态供 AI 处理
4. **最后**才删除目标 worktree 和本地分支

### 输出

无冲突：
```
=== 步骤 1: 清理 worktree feat/new-feature ===
删除 worktree 'feat-new-feature'...
删除本地分支 'feat/new-feature'...

=== 步骤 2: 同步其他 worktree 到 origin/main ===
同步 feat-other (feat/other)...
  OK: feat-other 已同步到最新 main

============================================
Merge cleanup 完成!
  已删除: feat/new-feature
  已同步: 1 个 worktree
  冲突: 0
============================================
```

有冲突：
```
=== 步骤 2: 同步其他 worktree 到 origin/main ===
同步 feat-conflict (feat/conflict)...
  CONFLICT: feat-conflict merge 冲突:
    - src/proxy/handler.ts
    - src/types.ts

============================================
Merge cleanup 完成!
  已删除: feat/new-feature
  已同步: 0 个 worktree
  冲突: 1 个 worktree（需处理）:
    - feat-conflict
============================================
```

## 从 CLAUDE.md 读取发布配置

merge-worktree 在执行 release 前，**必须先读取项目的 CLAUDE.md**（从 main worktree 目录或当前 worktree 目录），查找是否有发布相关配置（如 `## npm 发布流程` 或 `### 版本与发布规则` 段落）。

### 读取逻辑

1. 定位 CLAUDE.md：优先从 main worktree 目录读取，回退到当前 worktree 目录
2. 搜索关键词：`发布流程`、`release`、`npm publish`、`tag`
3. 根据读取到的信息决定 release 行为

### 关键知识点

**GitHub Actions release workflow 的触发条件**因项目而异：

| 触发模式 | CI 配置 | tag push 是否触发 | release 创建是否触发 |
|---------|---------|------------------|---------------------|
| `on: push: tags: ['v*']` | tag push 触发 | ✅ 是 | ❌ 否 |
| `on: release: types: [published]` | release 创建触发 | ❌ 否 | ✅ 是 |

本项目的 `release.yml` 使用 `on: release: types: [published]`，因此：

- **仅推送 tag 不会触发 npm 发布**
- **必须创建 GitHub Release** (`gh release create`) 才会触发 CI 流水线
- merge-worktree-release.sh 的步骤 6 已自动化此操作，确保执行

### 非 merge 场景的独立发布

当用户已完成 merge 和版本升级（如手动修改了 `package.json`），只需要打 tag 并发布时：

```bash
# 1. 在 main worktree 中确认版本号
CD ~/Code/project-workspace/main
node -p "require('./package.json').version"  # 确认版本

# 2. 提交版本变更（如有未提交的修改）
git add package.json package-lock.json
git commit -m "chore: bump version to x.y.z"

# 3. 打 tag 并推送
git tag vx.y.z
git push origin main --tags

# 4. 创建 GitHub Release（触发 CI 发布）
gh release create vx.y.z --title "vx.y.z" --target main --notes "## vx.y.z"
```

**关键**：第 4 步的 `gh release create` 不可省略，否则 CI 不会触发 npm publish。

## AI 操作步骤

### 阶段 0: 读取发布配置

1. 从项目的 CLAUDE.md 中读取发布相关配置
2. 确认 CI 触发模式（tag push vs release published）
3. 据此调整 release 步骤（是否需要创建 GitHub Release）

### 阶段 1: 收集上下文 + Release

1. 收集 PR 信息和分支改动摘要（用于后续冲突处理）
2. 运行 release 脚本：
   ```bash
   bash ~/.claude/skills/merge-worktree/merge-worktree-release.sh <pr-number>
   ```
3. 如果 CI 失败：
   - 分析失败原因，判断复杂度
   - 简单：直接修复 → push → 重跑脚本
   - 中等：用 `code-fixer` subagent → push → 重跑脚本
   - 复杂：先 `code-reviewer` 分析，再 `code-fixer` 修复

### 阶段 2: Cleanup + Sync

1. **先 cd 到 workspace 根目录**（避免后续删除当前工作目录导致 bash 失败）：
   ```bash
   cd <workspace-root>  # 例如 cd /Users/xxx/project-workspace
   ```
2. 运行清理脚本：
   ```bash
   bash ~/.claude/skills/merge-worktree/merge-worktree.sh <branch-name>
   ```
   脚本会先同步其他 worktree，最后才删除目标 worktree。
2. 如果有 merge 冲突，收集冲突上下文并分派 `merge-conflict-resolver` agent：
   - 冲突文件列表：`git diff --name-only --diff-filter=U`
   - 当前分支改动：`git log --oneline origin/main..HEAD`
   - main 改动：`git log --oneline HEAD..origin/main`
3. 冲突解决后 `git add . && git commit`
4. 输出完整报告

### Subagent 使用

| 子任务 | Agent | 使用条件 |
|--------|-------|---------|
| CI 失败分析 | `code-reviewer` | 失败原因不明 |
| CI 失败修复 | `code-fixer` | 失败原因明确 |
| Merge 冲突解决 | `merge-conflict-resolver` | 有冲突时 |

每个 subagent 必须收到：当前分支改动摘要、main 改动摘要、冲突文件 diff、工作目录路径。

**先斩后奏**：冲突难以判断时，agent 做出最佳选择并在报告中标注，由用户最终确认。
