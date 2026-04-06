---
name: lightmerge-branch
description: |
  Use when users want to merge multiple development branches into one test branch for integration testing,
  or mention "lightmerge", "lm", "lightmerge-branch", "合并测试", or need to quickly deploy and verify
  multiple features together. Also use when users want to add or remove branches from a test merge configuration,
  or manage per-project branch merging setups.
user-invocable: true
argument-hint: "[add <branch>] [remove <branch>] [list] [init] [rebuild] [push]"
model: sonnet
---

# Lightmerge Branch

将多个开发分支合并到一个临时集成分支，用于快速集成测试。每次操作都从 base branch 全量重建，保证状态干净。

## 快速参考

| 命令 | 用途 |
|------|------|
| `init` | 首次使用，配置 base_branch 和 remote |
| `add <branch>` | 添加分支到合并列表并重建 |
| `remove <branch>` | 移除分支并重建 |
| `rebuild` | 从 base branch 全量重建 lightmerge 分支 |
| `list` | 查看当前配置和分支状态（默认命令） |
| `push` | 手动推送到远端 |

## 配置文件

路径：`~/.claude/lightmerge-data/<project-name>/lightmerge-branches.json`

```json
{
  "base_branch": "main",
  "lightmerge_branch_name": "<project>-lightmerge",
  "remotes": ["origin"],
  "branches": ["feature/login", "feature/dashboard"]
}
```

- `remotes` 支持多个远端，如 `["origin", "user-fork"]`
- 首次使用 `init` 自动生成，后续只需 add/remove 分支

## 执行方式

所有 git 操作通过脚本执行（`scripts/lightmerge.sh`，相对于 SKILL.md 所在目录）：

```bash
bash <skill-dir>/scripts/lightmerge.sh <command> [project-name] [args...]
```

`project-name` 默认取 git 仓库目录名，可省略。

## 常见问题

| 场景 | 处理方式 |
|------|----------|
| 合并冲突 | 脚本自动中止该分支，输出冲突文件列表，继续合并其余分支 |
| 分支不存在 | 跳过并警告，不阻断其余分支合并 |
| 推送失败 | 输出错误信息，本地 lightmerge 分支不受影响 |
| 首次使用 | 先运行 `init` 配置 base_branch 和 remote，再 `add` 分支 |

## 示例

**初始化 + 添加分支：**

```
> /lm init
配置文件已创建: ~/.claude/lightmerge-data/my-project/lightmerge-branches.json

> /lm add feature/login
[1/1] 合并 feature/login... 成功
推送到 origin... 成功
```

**查看状态：**

```
> /lm
Base branch: main | Remotes: origin
合并列表 (2): feature/login, feature/dashboard
分支状态: 存在于本地和 origin
```
