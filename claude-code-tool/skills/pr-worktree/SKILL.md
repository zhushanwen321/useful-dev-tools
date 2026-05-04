---
name: pr-worktree
description: >
  在当前 worktree 中提交所有变更、推送到远程、创建 Pull Request。
  当用户说"提交PR"、"创建PR"、"pr-worktree"、"提交并创建PR"、"push 并开 PR"、
  "提交代码"时使用此 skill。
---

# PR Worktree

在当前 worktree 中完成提交、推送和创建 PR 的完整流程。

## 脚本

```
pr-worktree.sh [--draft] [--title "xxx"] [--body "xxx"] [--base main]
```

**前提**：当前在 worktree 目录中，变更已 commit。

### 参数

| 参数 | 说明 |
|------|------|
| `--title "xxx"` | PR 标题。省略时从最新 commit message 第一行提取 |
| `--body "xxx"` | PR 正文。省略时从 commit body 提取，或自动生成 diff --stat 摘要 |
| `--base main` | 目标分支，默认 `main` |
| `--draft` | 创建为 Draft PR |

### 用法示例

```bash
# 基本用法：从最新 commit 自动提取标题和正文
bash ~/.claude/skills/pr-worktree/pr-worktree.sh

# 指定标题和正文
bash ~/.claude/skills/pr-worktree/pr-worktree.sh --title "feat: add dark mode" --body "支持暗色主题切换"

# 创建 Draft PR
bash ~/.claude/skills/pr-worktree/pr-worktree.sh --draft

# 指定目标分支为 develop
bash ~/.claude/skills/pr-worktree/pr-worktree.sh --base develop
```

### 脚本行为

1. 检查当前分支和 gh CLI 状态
2. 检查是否有未提交变更（有则报错退出）
3. `git push -u origin <branch>`，失败时自动 `git pull --no-ff` 后重试
4. 查找已有 PR：`gh pr list --head <branch>`
5. **已有 PR** → 更新标题和正文（`gh pr edit`）
6. **无 PR** → 创建新 PR（`gh pr create`）
7. 输出 PR 编号和 URL

### 输出

创建新 PR：
```
当前分支: feat/new-feature

=== 推送到远程 ===

=== 检查已有 PR ===
未找到已有 PR，创建新 PR...

============================================
PR 已创建!
  PR: #42
  URL: https://github.com/xxx/pull/42
============================================
```

更新已有 PR：
```
当前分支: feat/new-feature

=== 推送到远程 ===

=== 检查已有 PR ===
已有 PR #42 (状态: OPEN)，更新中...

============================================
PR 已更新!
  PR: #42
  URL: https://github.com/xxx/pull/42
============================================
```

### 错误场景

| 输出 | 原因 | 解决 |
|------|------|------|
| `Warning: 有未提交的变更` | git add 后未 commit | 先提交变更 |
| `Error: gh CLI 未安装` | 未安装 GitHub CLI | `brew install gh` |
| `Error: gh CLI 未登录` | gh 未认证 | `gh auth login` |
| `pull 失败` | push 被拒且 pull 有冲突 | 手动解决冲突后重试 |

## AI 操作步骤（重要：先验证，再推送 PR）

1. 评估工作量：查看变更文件数和行数
   - 简单（<10 文件）：直接执行
   - 中等（10-30 文件）：按功能分组 commit
   - 复杂（>30 文件）：建议先用 code-review-worktree 审查
2. 检查变更内容，排除敏感信息
3. 让用户提供 commit message，或使用 zcommit skill 自动生成
4. `git add -A && git commit -m "<message>"`
5. **本地验证（push 前必须执行）**：

   运行以下全部检查，**任何一项失败都必须修复后才能 push**：

   ```bash
   # 1. TypeScript 类型检查
   npx vue-tsc --noEmit 2>&1 || npm run type-check 2>&1
   # 如果失败 → 修复 → 重新检查直到通过

   # 2. Lint 检查
   npx eslint . --max-warnings 0 2>&1 || npm run lint 2>&1
   # 如果失败 → 修复 → 重新检查直到通过

   # 3. 单元测试
   npm test 2>&1 || npx vitest run 2>&1
   # 如果失败 → 修复 → 重新检查直到全部通过

   # 4. 构建检查（可选）
   npm run build 2>&1 || true
   ```

   **规则：**
   - type-check 和 lint 必须 0 error 0 warning
   - 测试必须全部通过
   - 修复后重新运行确认通过，再继续

6. 运行脚本创建 PR：
   ```bash
   bash ~/.claude/skills/pr-worktree/pr-worktree.sh [--draft]
   ```
7. 确认输出包含 `"PR 已创建!"` 或 `"PR 已更新!"`
8. **（可选）检查 PR 的 CI 状态**：创建 PR 后，确认 Actions 已触发并初始状态正常
   ```bash
   gh pr view --json statusCheckRollup --jq '[.statusCheckRollup[] | .name + ": " + (.conclusion // "pending")] | .[]'
   ```
   如果有 check 立即失败（非 pending/queued），应分析原因并修复
