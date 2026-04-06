# install.sh 重构设计: 细粒度模块化安装器

## 核心设计原则: 子项级 Symlink

**这是整个安装器最重要的设计决策。**

对目录类模块（skills、agents、commands、hooks、custom-tools），采用**子项级 symlink** 而非目录级 symlink：

```
错误（目录级 — 替换整个目录，用户原有内容全部丢失）:
~/.claude/skills → /path/to/repo/skills

正确（子项级 — 只添加/替换单个子项，用户原有内容不受影响）:
~/.claude/skills/code-trace   → /path/to/repo/skills/code-trace
~/.claude/skills/zcommit      → /path/to/repo/skills/zcommit
~/.claude/skills/my-own-skill  (用户原有，不受影响)
```

**Why:** 开源发布场景下，用户可能已经有自己的 skills、agents 等目录。目录级 symlink 会"吞掉"用户原有内容，而子项级只操作本仓库提供的子项，用户可以自由混合使用多个来源的模块。

**How to apply:**
- 安装时: 遍历源目录的每个子项，逐个创建 symlink 到目标目录
- 卸载时: 只移除指向本仓库的 symlink（通过 `is_our_symlink()` 检查），不碰其他文件
- 目标目录本身（`~/.claude/skills/`）只做 `mkdir -p`，不创建 symlink

## 背景

当前 `claude-code-tool/install.sh` 是一个全量安装/卸载脚本，存在以下问题：

1. **全量操作** — 安装/卸载是"全部或没有"，用户无法选择性安装
2. **settings.json 直接修改** — 对已有自定义配置的用户有冲突风险
3. **无预览机制** — 没有 dry-run，用户无法预知将要发生的变更
4. **CLAUDE.md 风险** — 直接覆盖用户的全局行为配置，无 diff 展示
5. **开源发布需求** — 需要面向不同环境的用户，安全性要求更高

## 方案: 方案 A — 重构 install.sh

在现有单文件结构上增加模块注册表、交互式 checklist、dry-run 和确认流程。

## 架构

### 模块注册表

```bash
# 格式: name|description|type|risk_level|dependencies
MODULES=(
  "skills|Skills 技能集合|symlink|low|"
  "agents|Agent 子代理|symlink|low|"
  "commands|自定义命令|symlink|low|"
  "hooks|Hook 脚本|symlink|low|"
  "custom-tools|自定义工具|symlink|low|"
  "claude-md|CLAUDE.md 全局配置|file|medium|"
  "statusline|状态栏|settings|low|"
  "skill-inject|Skill 注入 Hook|settings|medium|"
  "knowledge-engine|知识引擎|settings+deps|high|bun,jq"
)
```

字段说明:
- **type**: `symlink`(子项级 symlink — 遍历源目录每个子项，逐个链接到目标目录，不替换目标目录本身)、`file`(单文件链接)、`settings`(修改 settings.json)、`settings+deps`(修改设置+安装依赖)
- **risk_level**: `low`(可逆的 symlink)、`medium`(修改配置文件)、`high`(需要额外依赖或有数据存储)
- **dependencies**: 逗号分隔的依赖模块名，安装时自动勾选

### 交互流程 (4步)

```
[1/4] 选择目标平台
  Claude Code / OpenCode / 全部

[2/4] 选择要安装的模块 (checklist)
  [x] skills         [low risk]
  [x] agents         [low risk]
  [ ] claude-md      [medium]    ← 标注风险
  [ ] knowledge-engine [high]    ← 标注风险+依赖

[3/4] 变更预览 (dry-run)
  展示将要创建的 symlink、备份的文件、修改的配置

[4/4] 确认执行
  展示变更摘要，用户确认后才执行
```

### Dry-run 机制

所有变更操作通过 `plan_*` 函数记录到 PLAN 数组:

```bash
PLAN=()  # 格式: "操作类型|描述|命令"

plan_symlink() { PLAN+=("symlink|$1|$2"); }
plan_backup()  { PLAN+=("backup|$1|$2"); }
plan_setting() { PLAN+=("setting|$1|$2"); }
```

- `--dry-run` 参数: 跳过交互，直接展示全量变更计划
- 确认后才调用 `execute_plan()` 顺序执行

### 安全性增强

#### 子项级 Symlink 安全
- 目录类模块只操作子项，不替换目标目录本身
- 已有同名 symlink: 如果指向本仓库则跳过（幂等），指向其他来源则提示用户选择
- 已有同名普通文件: 自动备份到 `~/.claude/bak/` 后再创建 symlink
- 卸载时只移除指向本仓库的 symlink，通过 `is_our_symlink()` 确保不误删其他来源的文件

#### settings.json 安全
- 预检查已有 hooks 配置，标注 `⚠ 已有自定义配置，将追加而非覆盖`
- jq 操作后验证输出是有效 JSON
- 修改前自动备份到 `~/.claude/bak/settings.json_{timestamp}`
- 安装结束后输出回滚命令

#### CLAUDE.md 安全
- 已有文件时在预览中展示 diff
- 默认不勾选此模块
- 建议用户手动合并

#### knowledge-engine 安全
- 模块勾选阶段检测 bun/jq 可用性
- 不可用时标注并给出安装提示
- crontab 不自动安装（保持当前行为）

#### 变更日志
- 每次操作后在 `~/.claude/bak/install.log` 追加记录
- 记录: 时间、操作类型、涉及的模块、备份的文件

## 文件变更清单

仅修改一个文件:
- `claude-code-tool/install.sh` — 重构，增加上述功能

## 不在范围内

- 拆分为多文件结构（方案 B）
- 配置文件驱动（方案 C）
- 自动回滚功能（仅提供回滚指令）
- 单元测试（bash 脚本通过 dry-run 验证即可）
