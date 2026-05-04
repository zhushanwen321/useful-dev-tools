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
| `--skip-ci` | flag | 否 | ⚠️ 仅限 AI 已人工确认 CI 全部通过时使用。**禁止随意跳过** |
| `--skip-release` | flag | 否 | 跳过 GitHub Release 创建 |

### 用法示例

```bash
# 基本用法：合并 PR #42，patch 版本升级，自动创建 release
bash ~/.claude/skills/merge-worktree/merge-worktree-release.sh 42

# 用分支名代替 PR 编号
bash ~/.claude/skills/merge-worktree/merge-worktree-release.sh feat/new-feature

# minor 版本升级
bash ~/.claude/skills/merge-worktree/merge-worktree-release.sh 42 --version minor

# CI 已确认通过，跳过检查（仅限人工确认后）
bash ~/.claude/skills/merge-worktree/merge-worktree-release.sh 42 --skip-ci

# 只合并和升级版本，不创建 GitHub Release
bash ~/.claude/skills/merge-worktree/merge-worktree-release.sh 42 --skip-release
```

### 脚本行为（6 步自动化流程）

| 步骤 | 操作 | 失败处理 |
|------|------|---------|
| 1. CI 检查 | `gh pr view --json statusCheckRollup` 获取所有检查项结论。**拒绝 pending/queued（未完成）、拒绝 failure/cancelled/action_required（失败）**。`gh` 本身失败也报错退出 | 任何失败都报错退出，列出具体失败项。等待修复后重试 |
| 2. Merge --no-ff | `git merge --no-ff` 保留完整分支历史 | — |
| 3. 更新 main | 在 main worktree 中 `git pull`，无 worktree 时用 `git -C .bare branch -f main` | — |
| 4. 版本升级 | 幂等检查：最新 commit 含 "bump version" 则跳过。否则 `npm version <type> --no-git-tag-version` | 非 npm 项目跳过 |
| 5. Tag + Push | `git add && git commit && git tag && git push origin main --tags` | — |
| 6. GitHub Release | `gh release create` ，notes 从 PR title+body 生成 | Tag 已有 release 时 warn |

### 输出

```
Workspace: /path/to/project-workspace
PR: #42

=== 步骤 1: 检查 CI（先验证，再 merge）===
CI 状态: success
✅ CI 检查全部通过。

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
| `CI 尚未全部完成` | 有 pending/queued/in_progress 的检查项 | 等待 CI 完成后重试 |
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

## AI 操作步骤（重要：先验证，再 merge）

**核心原则：先验证，再 merge，绝不先 merge 再验证。** 每一步验证失败都必须修复后才能进入下一步。

### 阶段 0: 读取 CLAUDE.md（必须首先执行）

**在执行任何操作之前，必须先读取项目的 CLAUDE.md**，从中发现：
1. **项目特定的合并/发布脚本路径**（如 `scripts/release.sh`）
2. **版本与发布规则**（CI 触发模式、发布包路径等）
3. **Workspace 结构**（bare repo + worktree 的目录布局）
4. **项目测试/构建命令**（`npm test`、`npm run build` 等）

读取逻辑：
```
1. 定位 CLAUDE.md：优先从 main worktree 目录，回退到当前 worktree 目录
2. 搜索关键词：`合并与发布流程`、`release`、`npm publish`、`tag`、`scripts/`、`测试`、`构建`
3. 根据发现的信息决定使用哪个脚本和什么策略
```

**脚本选择优先级：**
1. **CLAUDE.md 中指定的项目脚本**（如 `scripts/release.sh`）— 优先使用
2. **本 skill 自带的脚本**（`merge-worktree-release.sh`）— 仅在 CLAUDE.md 未指定时作为回退

### 阶段 1: 本地验证（merge 前必须执行）

**在运行任何 release 脚本之前，必须在 feature worktree 中执行完整的本地验证。** 这是防止 Actions 错误的第一个防线。

执行以下全部检查，按失败优先级排序：

```bash
# 1. TypeScript 类型检查
cd <feature-worktree>
npx vue-tsc --noEmit 2>&1
# 如果失败：修复类型错误，重新运行，直到通过

# 2. Lint 检查
npx eslint . --max-warnings 0 2>&1 || npm run lint 2>&1
# 如果失败：修复 lint 错误，重新运行，直到通过

# 3. 单元测试
npm test 2>&1 || npx vitest run 2>&1
# 如果失败：修复测试错误，重新运行，直到全部通过

# 4. 构建检查
npm run build 2>&1 || true  # 仅作为额外验证，不强阻塞
```

**规则：**
- 任何一项检查失败 → **必须修复后才能继续**，不可跳过
- 修复后重新运行该项检查，确认通过
- 如果本地验证全部通过，才能进入阶段 2
- **如果 fix 涉及代码变更，先 commit 再继续**

### 阶段 2: 远程 CI 验证 + Release

在本地验证通过的前提下，运行 release 脚本进行远程 CI 检查和合并。

**如果 CLAUDE.md 指定了项目脚本**（如 `scripts/release.sh`）：
```bash
cd <feature-worktree>
bash scripts/release.sh <patch|minor|major>
```

**如果没有项目脚本**，使用本 skill 自带脚本：
```bash
bash ~/.claude/skills/merge-worktree/merge-worktree-release.sh <pr-number>
```

脚本会执行：
1. ✅ 远程 CI 检查（pending/queued → 拒绝，failure → 拒绝，全部通过才继续）
2. ✅ Merge --no-ff 到 main
3. ✅ 版本升级 + tag + release

**如果脚本报错退出：**

| 错误类型 | 处理方式 |
|----------|---------|
| `CI 尚未全部完成` | 等待 CI 跑完，不要跳过。如果等待时间过长，问用户是否下次再合并 |
| `CI 有失败的检查项` | 见下方「CI 失败修复流程」 |
| `Merge 冲突` | 手动解决冲突 → `git add . && git commit` → 重新运行脚本 |
| `gh CLI 错误` | 检查网络和认证状态后重试 |

#### CI 失败修复流程（结构化循环）

当脚本因 CI 失败退出时：

1. **分析失败原因**：查看脚本输出的失败项名称和结论
   ```bash
   gh pr view <pr-number> --json statusCheckRollup --jq \
     '.statusCheckRollup[] | select(.conclusion == "failure") | {name, summary: .output.summary}'
   ```

2. **在本地修复**：根据 CI 失败信息修改代码

3. **重新运行阶段 1**：本地验证必须重新全部执行，确认修复不引入新问题

4. **提交并推送修复**
   ```bash
   git add -A && git commit -m "fix: <修复内容>" && git push
   ```

5. **重跑 release 脚本**：重新执行阶段 2
   ```bash
   bash ~/.claude/skills/merge-worktree/merge-worktree-release.sh <pr-number>
   ```

6. **最多重试 3 次**。如果 3 次后 CI 仍然失败：
   - 向用户报告所有尝试和失败原因
   - 询问用户是否需要手动介入
   - **不得使用 `--skip-ci` 绕过**

#### --skip-ci 使用约束

`--skip-ci` 仅限以下场景使用：
- AI 已亲眼确认 CI 上次运行时全部通过（例如刚看到一个绿色勾）
- 由于 GitHub 临时问题 CI 状态未更新
- **AI 不得自行决定跳过 CI 检查**，必须告知用户原因并获得确认

### 阶段 3: Cleanup + Sync

1. **先 cd 到 workspace 根目录**（避免后续删除当前工作目录导致 bash 失败）：
   ```bash
   cd <workspace-root>  # 例如 cd /Users/xxx/project-workspace
   ```
2. 运行清理脚本：
   ```bash
   bash ~/.claude/skills/merge-worktree/merge-worktree.sh <branch-name>
   ```
   脚本会先同步其他 worktree，最后才删除目标 worktree。
3. 如果有 merge 冲突，收集冲突上下文并分派 `merge-conflict-resolver` agent：
   - 冲突文件列表：`git diff --name-only --diff-filter=U`
   - 当前分支改动：`git log --oneline origin/main..HEAD`
   - main 改动：`git log --oneline HEAD..origin/main`
4. 冲突解决后 `git add . && git commit`
5. 输出完整报告
