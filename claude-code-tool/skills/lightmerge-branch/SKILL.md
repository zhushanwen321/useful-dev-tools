---
name: lightmerge-branch
description: |
  本地 lightmerge 分支管理工具，用于将多个开发分支合并到一个测试分支，方便快速部署验证多个功能。
  触发词："lightmerge"、"合并分支测试"、"创建测试分支"、"lm"。
  当用户想要：(1) 将多个分支合并到一起测试，(2) 管理测试合并分支，(3) 添加/移除要合并的分支，
  (4) 说 "lightmerge"、"lm"、"合并测试" 时使用此 skill。
user-invocable: true
argument-hint: "[add <branch>] [remove <branch>] [list] [init] [rebuild] [push]"
model: sonnet
---

# Lightmerge Branch - 多分支测试合并工具

将多个开发分支合并到一个 lightmerge 分支，用于快速部署和集成测试验证。

## 核心概念

- **lightmerge 分支**：一个临时的集成分支，包含所有需要一起测试的功能分支
- **配置文件**：`~/.claude/lightmerge-data/<project-name>/lightmerge-branches.json`，记录需要合并的分支和远端信息
- **操作策略**：每次变更都删除旧 lightmerge 分支、从 base branch 重建，保证状态干净

## 配置文件格式

`~/.claude/lightmerge-data/<project-name>/lightmerge-branches.json`：

```json
{
  "base_branch": "main",
  "lightmerge_branch_name": "lightmerge",
  "remotes": ["origin"],
  "branches": [
    "feature/login",
    "feature/dashboard"
  ]
}
```

| 字段 | 说明 |
|------|------|
| `base_branch` | 基于哪个分支创建 lightmerge（通常是 main 或 master） |
| `lightmerge_branch_name` | lightmerge 分支名称，默认 `lightmerge` |
| `remotes` | 要推送到的远端列表，默认 `["origin"]`，也可以包含 fork 如 `["origin", "user-fork"]` |
| `branches` | 需要合并到 lightmerge 的分支列表 |

## 触发条件

用户说以下任一短语时触发：
- "/lightmerge-branch" 或 "/lm"
- "lightmerge"
- "合并分支测试"
- "创建测试合并分支"

## 参数说明

| 命令 | 说明 |
|------|------|
| `init` | 首次使用，初始化配置（配置 base_branch 和 remote） |
| `add <branch>` | 添加一个分支到合并列表并重建 |
| `remove <branch>` | 从合并列表移除一个分支并重建 |
| `list` | 查看当前配置和合并列表 |
| `rebuild` | 强制重建 lightmerge 分支（不增减分支） |
| `push` | 手动推送到远端（通常 rebuild 会自动推送） |
| 无参数 | 等同于 `list` |

## 执行流程

### 首次初始化（init）

用户首次使用时需要配置基本参数。

1. 确定项目名称（取 git 仓库的目录名）
2. 询问用户 base_branch（如果当前有 main 就用 main，否则问用户）
3. 询问用户要推送的 remote（默认 origin）
4. 创建配置文件目录和初始配置

使用脚本执行：

```bash
bash <skill-path>/scripts/lightmerge.sh init <project-name> <base-branch> <remote>
```

脚本会：
- 创建 `~/.claude/lightmerge-data/<project-name>/` 目录
- 写入初始配置（branches 为空数组）
- 输出配置文件路径

### 添加分支（add）

将一个新分支加入合并列表，然后重建 lightmerge。

1. 读取当前配置，检查分支是否存在（`git branch -a` 中查找）
2. 将分支加入配置文件的 `branches` 数组
3. 执行重建流程

使用脚本执行：

```bash
bash <skill-path>/scripts/lightmerge.sh add <project-name> <branch-name>
```

### 移除分支（remove）

从合并列表中移除一个分支，然后重建 lightmerge。

```bash
bash <skill-path>/scripts/lightmerge.sh remove <project-name> <branch-name>
```

### 重建 lightmerge 分支（rebuild）

核心操作流程：

1. 切换到 base_branch 并拉取最新代码
2. 删除本地 lightmerge 分支（如果存在）
3. 从 base_branch 创建新的 lightmerge 分支
4. 逐个 merge 配置中的分支
5. 推送到所有配置的 remote

使用脚本执行：

```bash
bash <skill-path>/scripts/lightmerge.sh rebuild <project-name>
```

脚本会处理以下情况：
- 分支合并冲突时，输出冲突信息并中止，提示用户手动处理
- 某个分支不存在时，跳过并警告，继续合并其余分支
- 推送失败时，输出错误信息

### 查看状态（list）

显示当前配置和 lightmerge 分支状态。

```bash
bash <skill-path>/scripts/lightmerge.sh list <project-name>
```

## 脚本说明

所有 git 操作通过 `scripts/lightmerge.sh` 执行，原因：
- git 操作涉及分支切换、删除、创建，脚本比逐步命令更安全
- 脚本内建有错误处理，不会中途失败导致分支状态不一致
- 合并冲突可以统一处理，避免交互式冲突解决被中断

脚本位置：`scripts/lightmerge.sh`（相对于 SKILL.md 所在目录）

## 合并冲突处理

当某个分支合并产生冲突时：

1. 脚本会中止合并（`git merge --no-commit`，冲突时不自动继续）
2. 输出冲突的分支名和冲突文件列表
3. 建议用户选择：
   - 手动解决冲突后继续
   - 跳过该分支，只合并其余分支
   - 放弃本次操作

## 示例工作流

### 首次使用

```
用户: /lm init

> 请确认以下配置：
> - Base branch: main
> - Remote: origin
> 确认？(Y/n)

配置文件已创建: ~/.claude/lightmerge-data/my-project/lightmerge-branches.json
```

### 添加分支并重建

```
用户: /lm add feature/login

检查分支 feature/login... 存在
添加到合并列表...
当前合并列表: [feature/login]
开始重建 lightmerge 分支...

[1/1] 合并 feature/login... 成功
推送到 origin... 成功

lightmerge 分支已更新并推送到: origin/lightmerge
```

### 移除分支并重建

```
用户: /lm remove feature/login

从合并列表移除 feature/login...
当前合并列表: [feature/dashboard]
开始重建 lightmerge 分支...

[1/1] 合并 feature/dashboard... 成功
推送到 origin... 成功

lightmerge 分支已更新并推送到: origin/lightmerge
```

### 查看状态

```
用户: /lm

配置文件: ~/.claude/lightmerge-data/my-project/lightmerge-branches.json
Base branch: main
Remotes: origin
合并列表 (2 个分支):
  1. feature/login
  2. feature/dashboard

lightmerge 分支状态: 存在于本地和 origin
```

## 注意事项

1. **每次重建都是全量操作**：删除旧 lightmerge 再从 base branch 重新创建，不保留上一次的合并状态
2. **本地分支优先**：合并时优先使用本地分支，如果本地不存在则从 remote 拉取
3. **推送所有 remote**：配置了多个 remote 时（如 origin + fork），会逐一推送
4. **不支持自动冲突解决**：遇到合并冲突必须人工介入
5. **配置文件跨项目隔离**：每个项目有独立的配置目录，互不影响
