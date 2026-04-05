# Knowledge Engine 设计文档

> 日期：2026-04-05
> 状态：设计中

## 1. 概述

### 1.1 目标

构建一个自动化的项目知识管理系统，在 AI 辅助编程过程中：

1. **自动记录**代码变更元数据（轻量、高频）
2. **自动总结**关键业务/技术知识（per commit，中频）
3. **自动沉淀**为结构化的正式知识库（per batch，低频）
4. **按需加载**知识到对话上下文（SessionStart 索引注入）

### 1.2 设计原则

- **记录与总结分离**：记录可以高频低成本，总结在自然断点批量执行
- **跨项目通用**：核心引擎在全局目录，知识按项目隔离
- **降级容错**：AI CLI 不可用时自动降级为纯元数据模式
- **双平台兼容**：核心逻辑纯函数，Claude Code 和 OpenCode 通过适配器接入
- **索引本地化**：索引通过扫描文件 frontmatter 自动生成，不依赖 AI

### 1.3 范围

- 作用范围：跨项目通用，任何 Claude Code / OpenCode 会话都可接入
- 实现技术：Hook 触发 + Bun 运行 TS + qwencode CLI
- AI 后端：仅 qwencode CLI（headless 模式）

## 2. 目录结构

### 2.1 项目源码

```
claude-code-tool/knowledge-engine/
├── package.json
├── tsconfig.json
├── src/
│   ├── core/                    # 核心逻辑（纯函数，与平台无关）
│   │   ├── recorder.ts          # 记录层：解析输入，追加 changelog.log
│   │   ├── summarizer.ts        # 总结层：git diff + qwencode 总结
│   │   ├── consolidator.ts      # 沉淀层：合并 temp -> formal + 生成 index.md
│   │   ├── ai.ts                # qwencode CLI 调用封装
│   │   ├── config.ts            # 配置读取（全局 + 项目级覆盖）
│   │   ├── slug.ts              # 项目路径 -> slug 生成
│   │   └── types.ts             # 共享类型定义
│   ├── adapters/
│   │   ├── claude-code.ts       # Claude Code hook 入口（读 stdin JSON）
│   │   └── opencode.ts          # OpenCode Plugin 入口（Plugin API）
│   └── cli.ts                   # CLI 入口（bun run cli.ts <command>）
└── scripts/
    └── cron-maintenance.sh      # crontab 触发的维护脚本
```

### 2.2 运行时知识库

```
~/.claude/knowledge/
├── config.json                  # 全局配置
└── <project-slug>/              # 按项目隔离
    ├── config.json              # 项目级配置覆盖
    ├── state.json               # 状态（lastSummarizedCommit）
    ├── changelog.log            # 记录层写入，append-only
    ├── temp/                    # 总结层写入，临时知识
    │   └── <commit-hash>.md
    └── formal/                  # 沉淀层写入，正式知识
        ├── index.md             # 分类索引（自动生成）
        ├── tag_index.md         # 标签索引（自动生成）
        └── <category>/
            ├── index.md         # 分类索引（自动生成）
            └── *.md
```

slug 生成规则：项目根路径去掉前导 `/Users/`，路径分隔符替换为 `-`，保留原始大小写。示例：`/Users/zhushanwen/GitApp/my-project` -> `gitApp-my-project`。避免对路径做大小写规范化，macOS 文件系统不区分大小写但实际路径可能有差异。

## 3. 三层工作流

### 3.1 记录层（recorder.ts）

**触发**：Claude Code `PostToolUse(Write|Edit)` hook，async=true

**核心逻辑**（纯函数）：

- 输入：`{ tool_name, file_path, content?, new_string?, old_string?, project_root }`
- 过滤：读取 `config.json` 中的 `excludePatterns`，排除匹配的文件路径
- 变更量极小（纯空白变更）也跳过
- 输出：追加一行到 `changelog.log`：`timestamp|tool_name|file_path|change_preview(前200字)`
- 目录不存在时自动初始化

**不调 AI**，纯本地操作，延迟 < 5ms。

### 3.2 总结层（summarizer.ts）

**触发**：Claude Code `Stop` hook + crontab

**核心逻辑**：

1. 读 `state.json` 中的 `lastSummarizedCommit`
2. `git log <last>..HEAD` 获取未总结 commit
3. 没有新 commit 则静默退出（< 1ms）
4. **单次执行限制最多处理 5 个 commit**，剩余留给下次 Stop 或 crontab。防止 hook 超时
5. 对每个 commit：
   - 取 diff：
     - 初始 commit：`git diff 4b825dc642cb6eb9a060e54bf899d15363d7aa91 <commit>`（对比空 tree）
     - 后续 commit：`git diff <commit>~1 <commit>`
     - **diff 大小控制**：先 `git diff --stat` 获取文件列表，如果 diff 超过 10000 字符，只传 `--stat` 结果而非完整 diff。避免大 commit 截断丢失关键信息
   - 读取 changelog.log 中该 commit 时间范围内的条目（用 `state.json` 中记录的 `lastSummarizedTimestamp` 和当前 commit 时间戳界定范围）
   - 拼接 prompt 调 qwencode，要求输出结构化 JSON：

```json
{
  "should_summarize": true,
  "topics": ["auth", "hook-system"],
  "summary": "2-3 句话总结",
  "key_decisions": ["决策及原因"],
  "patterns": ["发现的模式"]
}
```

   - `should_summarize=true` 时写入 `temp/<commit-hash>.md`
   - 更新 `state.json`：`lastSummarizedCommit = 当前 hash`

**降级**：qwencode 不可用时，原始元数据（commit message + diff stat）写入 temp 文件，frontmatter 标记 `status: raw`。格式与 summarized 一致，沉淀层不需要区分处理。

**并发安全**：`state.json` 使用原子 rename（先写 `.tmp` 再 rename）。两个会话同时 Stop 时，第二个看到已更新的 commit hash，自动跳过。

### 3.3 沉淀层（consolidator.ts）

**触发**：Claude Code `Stop` hook（summarize 之后）+ crontab

**核心逻辑**：

1. 扫描 `temp/` 文件数，未达阈值（默认 3）则静默退出
2. 读现有 `formal/` 目录结构
3. 调 qwencode：输入所有 temp 知识 + 现有结构，输出文件操作指令：

```json
{
  "operations": [
    { "action": "create", "category": "architecture", "filename": "hook-lifecycle.md", "name": "hook-lifecycle", "description": "Hook 完整生命周期", "content": "..." },
    { "action": "update", "category": "patterns", "filename": "error-handling.md", "content": "..." },
    { "action": "merge", "sources": ["abc123.md", "def456.md"], "target": "patterns/error-handling.md", "content": "..." }
  ]
}
```

4. 执行文件操作到 `formal/`（每个文件 frontmatter 包含 name、description、tags）
5. 扫描 formal 所有文件的 frontmatter，重新生成 `index.md`（按 category）、`tag_index.md`（按 tag）和各分类 `index.md`
6. 清理 `temp/`

**幂等性**：consolidate 是幂等操作，出错下次重跑即可。

**并发安全**：沉淀层使用 `temp/.consolidating` 标记文件实现互斥：
1. 尝试用 `O_EXCL` 原子创建标记文件，失败则说明另一个进程正在执行，静默退出
2. 操作完成后删除标记文件
3. 如果进程异常退出导致标记残留，下次执行时检查标记文件创建时间，超过 10 分钟则视为过期，强制删除后继续

**category 校验**：沉淀层 AI 输出的 category 必须在配置的 `categories` 列表中。如果 AI 输出了未知 category，归入第一个默认 category，并在 frontmatter 中保留原始 category 作为 `original_category` 字段。

### 3.4 自动加载（SessionStart）

**触发**：`SessionStart` hook

**行为**：

1. 从 stdin JSON 的 `cwd` 或环境变量获取当前项目路径，计算 slug
2. 检查 `~/.claude/knowledge/<slug>/formal/index.md` 是否存在
3. 存在则读取内容，通过 JSON 输出的 `additionalContext` 字段注入上下文
4. 不存在则静默退出

**注入内容**：只注入索引（通常 < 50 行），模型根据当前任务按需读取详细内容。

## 4. 双平台适配

### 4.1 设计思路

核心逻辑在 `core/` 中写纯函数（输入标准化参数对象，输出结果），适配器只做参数提取和结果转换。

### 4.2 Claude Code 适配

**CLI 入口**（cli.ts）：通过子命令分发，从 stdin 读取 hook JSON。

```typescript
const command = process.argv[2] // record | process | inject-index | cleanup
```

**Hook 配置**（`~/.claude/settings.json`）：

```json
{
  "PostToolUse": [{
    "matcher": "Write|Edit",
    "hooks": [{
      "type": "command",
      "command": "bun /path/to/knowledge-engine/src/cli.ts record",
      "async": true,
      "timeout": 5
    }]
  }],
  "Stop": [{
    "hooks": [{
      "type": "command",
      "command": "bun /path/to/knowledge-engine/src/cli.ts process",
      "async": true,
      "timeout": 120
    }]
  }],
  "SessionStart": [{
    "hooks": [{
      "type": "command",
      "command": "bun /path/to/knowledge-engine/src/cli.ts inject-index",
      "timeout": 5
    }]
  }]
}
```

> **关于 `process` 命令**：将 summarize 和 consolidate 合并为单个 `process` 命令，内部串行执行（先总结再沉淀）。这样可以保证执行顺序，同时避免 Stop hook 数组中多个命令的执行顺序不确定问题。

### 4.3 OpenCode 适配

**Plugin 入口**（adapters/opencode.ts）：

```typescript
export const KnowledgeEnginePlugin: Plugin = async (ctx) => {
  return {
    'tool.execute.after': async (input, output) => {
      if (['Write', 'Edit'].includes(input.tool)) {
        record({
          tool_name: input.tool,
          file_path: output.args.file_path,
          project_root: ctx.directory
        })
      }
    },
    'session.end': async () => {
      await summarize({ project_root: ctx.directory })
      await consolidate({ project_root: ctx.directory })
    },
    'session.start': async () => {
      return getInjectIndex({ project_root: ctx.directory })
    }
  }
}
```

### 4.4 平台差异对照

| | Claude Code | OpenCode |
|---|---|---|
| 文件操作后 | `PostToolUse` hook + stdin JSON | `tool.execute.after` 回调 |
| 会话结束 | `Stop` hook | `session.end` 回调 |
| 会话开始 | `SessionStart` hook + additionalContext | `session.start` 回调 |
| 项目路径 | `CLAUDE_PROJECT_DIR` 环境变量 | `ctx.directory` |
| 核心逻辑 | 相同的 `core/*.ts` 纯函数 | 相同的 `core/*.ts` 纯函数 |

## 5. AI 调用

### 5.1 qwencode 封装（ai.ts）

```typescript
export async function callQwen(prompt: string): Promise<string> {
  const result = spawnSync('qwencode', [
    '--headless',
    '--prompt', prompt
  ], { timeout: 30000 })

  if (result.status !== 0) throw new Error('qwencode failed')
  return result.stdout.toString()
}
```

单一函数，不做 provider 发现/降级链。调用方自行处理降级逻辑。

### 5.2 可用性检测

```typescript
export function isQwenAvailable(): boolean {
  return spawnSync('which', ['qwencode']).status === 0
}
```

总结层和沉淀层在调用前先检测，不可用时走降级路径。

### 5.3 Prompt 模板

#### 总结层 prompt

```
你是一个代码变更知识提取器。分析以下代码变更，提取有价值的业务或技术知识。

## 操作序列
{changelog_entries}

## Commit 信息
Message: {commit_message}
Files changed: {files_list}

## Diff 摘要（前 2000 字）
{diff_summary}

## 输出要求
返回 JSON：
{
  "should_summarize": true/false,
  "topics": ["topic1"],
  "summary": "2-3 句话总结",
  "key_decisions": ["决策及原因"],
  "patterns": ["发现的模式"]
}

should_summarize 判断：涉及架构决策、新功能、重要 bug 修复为 true；格式化、依赖更新、typo 为 false。
```

#### 沉淀层 prompt

```
你是一个知识整合器。将以下临时知识合并到现有知识库中。

## 现有目录结构
{formal_structure}

## 临时知识文件
{temp_files_content}

## 输出要求
返回 JSON：
{
  "operations": [
    {
      "action": "create|update|merge",
      "category": "分类",
      "filename": "文件名.md",
      "name": "简短标识名",
      "description": "一句话描述（用于索引生成）",
      "tags": ["tag1", "tag2"],
      "content": "完整 markdown 内容"
    }
  ]
}
```

## 6. 配置体系

### 6.1 全局配置（~/.claude/knowledge/config.json）

```json
{
  "categories": ["architecture", "patterns", "domain", "troubleshooting"],
  "consolidateThreshold": 3,
  "excludePatterns": ["**/*.lock", "**/node_modules/**", ".env*"]
}
```

### 6.2 项目级配置（~/.claude/knowledge/<slug>/config.json）

```json
{
  "categories": ["auth", "api", "frontend"],
  "consolidateThreshold": 5,
  "excludePatterns": ["**/generated/**"]
}
```

项目级覆盖全局。`config.ts` 负责合并两层配置。

## 7. 知识文档格式

### 7.1 临时知识（temp/<commit-hash>.md）

```markdown
---
name: "实现 PostToolUse hook 解析"
description: "本次提交实现了 PostToolUse hook 的 JSON 输出解析逻辑"
tags: [hook, json, parsing, post-tool-use]
commit: abc123def
timestamp: 2026-04-05T14:30:22+08:00
topics: [auth, hook-system]
status: summarized
---

# <commit message>

## Summary
<AI 总结，或降级时的原始元数据>

## Key Decisions
- <决策及原因>

## Patterns
- <发现的模式>
```

`status: summarized` 和 `status: raw` 格式一致，区别在于内容丰富度。

**raw 降级示例**（qwencode 不可用时）：

```markdown
---
name: "fix: 修复 hook 超时问题"
description: "修复了 Stop hook 执行超时导致的知识丢失"
tags: [bugfix, hook, timeout]
commit: abc123def
timestamp: 2026-04-05T14:30:22+08:00
topics: []
status: raw
---

# fix: 修复 hook 超时问题

## Summary
commit message: fix: 修复 hook 超时问题
files changed: src/hooks/stop.ts, src/utils/timeout.ts
diff stat: +45 -12

## Key Decisions
(原始元数据，待 AI 总结)

## Patterns
(原始元数据，待 AI 总结)
```

raw 模式下 `topics` 为空数组，`tags` 由简单规则从文件路径和 commit message 中提取关键词。沉淀层遇到 `status: raw` 的文件时，先调 AI 补充总结再合并。

### 7.2 正式知识（formal/<category>/<name>.md）

```markdown
---
name: "hook-lifecycle"
description: "Hook 从注册到执行的完整生命周期"
tags: [hook, lifecycle, event-system, claude-code]
category: architecture
created: 2026-04-05
updated: 2026-04-05
sources: [abc123def, def456abc]
---

# <标题>

<从临时知识合并提炼的内容>

## Related
- [相关文档](./other-doc.md)
```

每个文件的 `name`、`description`、`tags` 用于索引自动生成。

### 7.3 分类索引文件（formal/index.md）

按 category 分层的索引，适合 AI 进行结构化检索。通过扫描所有 formal 文件的 frontmatter 自动生成，不依赖 AI：

```markdown
# 项目知识库索引

## architecture
- [hook-lifecycle](architecture/hook-lifecycle.md) — Hook 从注册到执行的完整生命周期
- [oauth-flow](architecture/oauth-flow.md) — OAuth 2.0 认证流程

## patterns
- [error-handling](patterns/error-handling.md) — 错误处理模式汇总

---
最近更新：2026-04-05 | 文档数：3
```

### 7.4 标签索引文件（formal/tag_index.md）

按 tag 聚合的交叉索引，适合 AI 进行模糊搜索、扩大检索范围。同样通过扫描 frontmatter 自动生成：

```markdown
# 标签索引

## hook
- [hook-lifecycle](architecture/hook-lifecycle.md) — Hook 从注册到执行的完整生命周期
- [hook-json-parsing](patterns/hook-json-parsing.md) — Hook JSON 输入解析模式

## lifecycle
- [hook-lifecycle](architecture/hook-lifecycle.md) — Hook 从注册到执行的完整生命周期

## error-handling
- [error-handling](patterns/error-handling.md) — 错误处理模式汇总

---
最近更新：2026-04-05 | 标签数：3 | 文档数：3
```

**两种索引的用途**：
- `index.md`：分层体系下的精确检索（"我需要看 architecture 相关的知识"）
- `tag_index.md`：模糊搜索扩大范围（"我需要看所有和 hook 相关的知识"，跨 category 检索）

同一篇文档可以出现在 tag_index.md 的多个 tag 下，形成交叉引用。

## 8. Crontab 维护

### scripts/cron-maintenance.sh

```bash
#!/bin/bash
# 被 crontab 调用，依次执行所有维护任务
ENGINE_DIR="/path/to/knowledge-engine"
cd "$ENGINE_DIR"
bun run src/cli.ts process    # summarize + consolidate（内部串行）
bun run src/cli.ts cleanup
```

用户通过 `crontab -e` 添加：

```
0 23 * * * /path/to/knowledge-engine/scripts/cron-maintenance.sh
```

### cleanup 命令

截断 changelog.log 中已被成功总结的条目。截断条件：changelog 条目的时间戳早于 `state.json.lastSummarizedCommit` 对应的 git commit 时间，且该 commit 的 temp 文件已被成功 consolidate（不在 temp/ 中存在）。只截断同时满足这两个条件的条目，确保不会丢失未处理的数据。

## 9. 降级与容错

| 场景 | 处理方式 |
|------|---------|
| qwencode 未安装 | 记录层正常，总结/沉淀层降级为原始元数据 |
| qwencode 超时 | 同上，并记录错误日志 |
| qwencode 返回非 JSON | 解析失败，降级为原始元数据 |
| 首次使用，目录不存在 | recorder 自动创建目录结构和 config.json |
| 非 git 项目 | recorder 正常，summarize/consolidate 静默退出 |
| 多会话并发 | changelog 追加天然安全，state.json 原子 rename，consolidate 用标记文件互斥 |
| consolidate 中途失败 | formal 目录保持一致（操作未全部完成不影响已有文件），下次重跑 |

## 10. 触发机制汇总

| 触发方式 | 执行什么 | 说明 |
|---------|---------|------|
| `PostToolUse(Write\|Edit)` | record | 每次文件操作，async，轻量 |
| `Stop` hook | process（summarize + consolidate） | 单命令串行，内部有守卫条件 |
| crontab | process + cleanup | 定时全量维护 |
| `SessionStart` | inject-index | 注入 formal/index.md 到上下文 |
