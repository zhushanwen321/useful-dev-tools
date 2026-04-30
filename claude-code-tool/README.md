# Claude Code Tool

Claude Code / OpenCode 的增强工具套件。通过 skills、agents、hooks 和知识引擎，将 Claude Code 从通用编码助手扩展为专业化开发平台。

## 功能模块

### Skills (16 个)

Claude Code 的技能扩展机制，每个 skill 是一组领域专用指令。

| 类别 | Skill | 说明 |
|------|-------|------|
| **代码分析** | `batch-tracer` | 批量代码分析调度器，对目录下所有源文件执行 code-trace -> issue-trace -> review-trace 三阶段分析 |
| | `code-trace` | 分析代码文件的完整调用链路和数据流，找出上下游依赖关系，审查链路正确性并评分 |
| | `issue-trace` | 通过构建调用链路和数据链路来验证问题是否真实存在，对严重程度评分 (1-10) |
| | `review-tracer` | 审查代码审查工具的输出质量，对审查结果进行评分和评估 |
| **Python 开发** | `py-preference` | Python 开发偏好指南，覆盖命名规范、类型标注、错误处理、异步模式等 |
| | `python-refactor` | 基于 rope 库的 Python 重构，支持重命名、移动模块、提取方法等 |
| | `qwen-fast-coder` | 使用 Qwen Code 无头模式执行快速代码改动（移动文件、批量重命名、格式化） |
| **元技能** | `skill-creator` | 创建和改进 skills，支持 draft-test-evaluate-iterate 循环 |
| | `skill-memory-keeper` | 记录 skills 使用经验，双维度存储（用户/项目），渐进式总结 |
| **工作流** | `bug-fix-recorder` | 记录 bug 修复到知识库，支持相似度检索和统计 |
| | `recheck-code` | 对最近修改的代码进行质量检查，查找 bug、重复代码、遗漏 |
| | `review-changes` | 批量审查未提交的代码变更，支持自动提交 |
| | `task-group-planner` | 将复杂任务拆分为并行/串行执行组 |
| | `zcommit` | 智能 git commit，自动识别变更类型并生成规范提交信息 |
| | `learned` | 累积学习的占位 skill |

### Agents (4 个)

可并行分发的子代理定义。

| Agent | 说明 |
|-------|------|
| `batch-code-tracer` | 对单个代码文件执行调用链路和数据流分析，生成 code-trace 报告 |
| `batch-issue-tracer` | 根据 code-trace 报告验证问题的真实性和严重程度 |
| `batch-review-tracer` | 评估 issue-trace 报告的审查质量 |
| `bug-fixer` | Bug 修复知识库管理器，支持 record/search/stats/repair 四种操作 |

### Knowledge Engine (知识引擎)

TypeScript/Bun 实现的三层知识系统，自动从代码变更中积累项目知识。

```
Layer 1: Record  — 每次 Write/Edit 操作后记录变更日志
Layer 2: Summarize — 会话结束时用 AI 提取知识（主题、决策、模式）
Layer 3: Consolidate — 当临时知识积累到阈值后，用 AI 合并到正式知识库
```

**存储结构**:
```
~/.claude/knowledge/
  config.json           # 全局配置（类别、阈值、排除模式）
  state.json            # 上次汇总的 commit 追踪
  changelog.log         # 原始变更日志
  {project-slug}/       # 每项目知识
    temp/               # 未合并的临时知识
    formal/             # 已合并的正式知识库
      index.md          # 按类别的主索引
      tag_index.md      # 按标签的交叉索引
      {category}/       # 按类别组织的知识文件
```

**AI 集成**: 使用 `qwen` CLI，配置了安全约束（`--approval-mode plan`，排除文件操作工具，30秒超时）。AI 不可用时自动降级为基于 commit 数据的简单模式。

### Custom Tools (自定义工具)

| 工具 | 说明 |
|------|------|
| `statusline.sh` | 三行 ANSI 彩色状态栏，显示项目信息、上下文窗口使用率、智谱 AI token 用量、会话计时等 |
| `zhipu_token.py` | 从 macOS Chrome 提取智谱 AI token（PBKDF2 解密 Chrome Safe Storage，AES-128-CBC cookie 解密） |

### Hooks

| Hook | 触发时机 | 说明 |
|------|---------|------|
| `skill-inject.sh` | PreToolUse (Skill) | 为 `writing-plans` 和 `subagent-driven-development` 注入额外上下文 |

### Commands

| 命令 | 说明 |
|------|------|
| `commit` | Conventional Commits 规范，带 emoji 前缀 |
| `sketch` | HLD（概要设计）生成，包含架构、模块、技术栈、数据设计等模板 |

## 安装

### 前置条件

- **bash** (macOS/Linux)
- **jq** — 用于安全修改 settings.json
- **bun** — 知识引擎的运行时（可选，仅安装知识引擎时需要）

### 安装方式

```bash
cd claude-code-tool
./install.sh
```

安装脚本提供交互式菜单：

1. 选择目标平台（Claude Code / OpenCode / Agent Skills / pi / 全部）
2. 选择安装/卸载
3. 确认执行

**安装机制**: 采用**子项级 symlink**，而非目录级 symlink。即：

```
# 不是这样（目录级 — 会替换整个目录，用户原有内容全部丢失）:
~/.claude/skills → /path/to/repo/skills

# 而是这样（子项级 — 只添加/替换单个子项，用户原有内容不受影响）:
~/.claude/skills/code-trace     → /path/to/repo/skills/code-trace
~/.claude/skills/batch-tracer   → /path/to/repo/skills/batch-tracer
~/.claude/skills/zcommit        → /path/to/repo/skills/zcommit
...
# 用户自己安装的 skills 保持原样:
~/.claude/skills/my-custom-skill  (不受影响)
```

这种策略适用于所有目录类模块（skills、agents、commands、hooks、custom-tools）。用户可以自由混合使用本工具的模块和自己的模块，互不干扰。卸载时只移除指向本仓库的 symlink，不影响同目录下的其他文件。

**备份**: 如果目标位置已有同名文件（非 symlink），会自动备份到 `~/.claude/bak/`，带时间戳。

### 注意事项

- `CLAUDE.md` 会覆盖 Claude Code 的全局行为配置，如有自定义配置请先备份或手动合并
- 知识引擎会在 `settings.json` 中注册 hooks（PostToolUse、Stop、SessionStart）
- `skill-inject` 会在 `settings.json` 中注册 PreToolUse hook
- 所有 settings.json 修改都通过 jq 原子操作（写临时文件后替换），不会损坏配置

### pi 集成

安装脚本支持将 skills 和 agents 安装到 [pi](https://github.com/nicholasgasior/pi-coding-agent)（`~/.pi/agent/`）：

- **Skills** → `~/.pi/agent/skills/<skill-name>/`（与 `~/.agents/skills/` 相同的 symlink 策略）
- **Agents** → `~/.pi/agent/agents/<name>.md`（自动展平 `agents/<name>/agent.md` 为 `<name>.md`）

pi 的 agent 格式是扁平的 `.md` 文件（YAML frontmatter + 系统提示词），而本仓库的 agent 使用 `agent-name/agent.md` 子目录结构。安装脚本会自动处理这种映射。

## 卸载

```bash
./install.sh
# 选择 "卸载" -> 选择目标平台
```

卸载只移除指向本仓库的 symlink 和对应的 settings.json 配置。同目录下的其他文件（用户自己的 skills、agents 等）不受影响。知识引擎数据（`~/.claude/knowledge/`）不会被删除。

## 目录结构

```
claude-code-tool/
  CLAUDE.md                    # Claude Code 全局行为配置
  install.sh                   # 安装/卸载脚本
  agents/                      # 子代理定义
  commands/                    # 斜杠命令
  skills/                      # 技能定义
  custom-tools/                # 独立工具（statusline, zhipu_token）
  hooks/                       # Hook 脚本
  knowledge-engine/            # 知识引擎
    src/
      cli.ts                   # CLI 入口
      recorder.ts              # Layer 1: 记录变更
      summarizer.ts            # Layer 2: AI 摘要
      consolidator.ts          # Layer 3: 合并知识
      ai.ts                    # AI 集成（qwen CLI）
      config.ts                # 三级配置合并
```
