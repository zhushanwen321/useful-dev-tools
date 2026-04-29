---
name: manage-worktree
description: 管理 bare repo + worktree 结构的 workspace。支持创建和删除 worktree，自动检测 workspace、同步配置、安装依赖。
user-invocable: true
---

# Worktree 管理

在 bare repo + worktree 结构中创建或删除隔离工作目录。

## Workspace 模式

```
<project>-workspace/
├── .bare/              # Bare 仓库（git 对象数据库，不是分支）
├── master/             # 主分支 worktree（实际工作目录）
├── feat-xxx/           # 其他分支（分支名 / 替换为 -）
└── .../
```

## 脚本位置

```
~/.claude/skills/manage-worktree/create-worktree.sh
~/.claude/skills/manage-worktree/remove-worktree.sh
```

## 创建 Worktree

### 触发条件

- "创建 worktree"、"新 worktree"、"create worktree"、"/manage-worktree"
- 需要为新功能或 bugfix 创建隔离工作目录

### 步骤

1. 向用户获取参数：

| 参数 | 必填 | 默认值 | 示例 |
|------|------|--------|------|
| 分支名 | 是 | - | `feat/new-feature` |
| 基础分支 | 否 | 自动检测远程默认分支 | `develop` |

2. 运行脚本：

```bash
bash ~/.claude/skills/manage-worktree/create-worktree.sh <branch-name> [base-branch]
```

3. 确认输出包含 "Worktree 创建完成!"

脚本自动完成：查找 workspace → fetch → 创建分支 → 复制 .claude 配置 → 安装依赖 → 安装 hooks。

## 删除 Worktree

### 触发条件

- "删除 worktree"、"清理 worktree"、"remove worktree"、"/manage-worktree"
- 功能开发完成、分支已合并，需要清理工作目录

### 步骤

1. 确认要删除的分支名，向用户确认是否同时删除本地分支。

2. 运行脚本：

```bash
# 仅删除 worktree，保留本地分支
bash ~/.claude/skills/manage-worktree/remove-worktree.sh <branch-name>

# 同时删除本地分支（未推送的提交将丢失）
bash ~/.claude/skills/manage-worktree/remove-worktree.sh <branch-name> --delete-branch
```

3. 确认输出包含 "Worktree 已删除!"

### 安全检查

脚本会阻止删除的情况：
- 主分支（master/main）
- 有未提交更改的 worktree
- 列出未推送的提交并提示风险

## 快速参考

| 场景 | 命令 |
|------|------|
| 创建新分支 worktree | `bash ~/.claude/skills/manage-worktree/create-worktree.sh feat/new-feature` |
| 基于其他分支创建 | `bash ~/.claude/skills/manage-worktree/create-worktree.sh fix/bug develop` |
| 检出已有分支 | `bash ~/.claude/skills/manage-worktree/create-worktree.sh 024-ai-data-api` |
| 删除 worktree（保留分支） | `bash ~/.claude/skills/manage-worktree/remove-worktree.sh feat/old-feature` |
| 删除 worktree 和分支 | `bash ~/.claude/skills/manage-worktree/remove-worktree.sh feat/old-feature --delete-branch` |

## 错误处理

| 错误 | 原因 | 解决 |
|------|------|------|
| 未找到 workspace | 不在 worktree 内 | cd 到正确的 workspace 目录 |
| 目录已存在 | 同名 worktree 已创建 | `git -C .bare worktree list` 检查 |
| 有未提交更改 | 删除前必须提交 | 先 commit 或 stash |
| 不能删除主分支 | master/main 受保护 | 这是正确的保护机制 |
