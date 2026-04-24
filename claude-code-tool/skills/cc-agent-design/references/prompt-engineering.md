# Claude Code Prompt 工程设计详解

源码位置：`~/GitApp/claude-code-source-code/`

## 1. System Prompt 分层架构

`src/constants/prompts.ts:getSystemPrompt()` (行 444-577)

整体分为静态层（可跨用户缓存）和动态层（每轮重算），用 `__SYSTEM_PROMPT_DYNAMIC_BOUNDARY__` 分隔。

### 静态层（可缓存）

- Intro Section — 身份定义
- System Section — 权限模式、hooks、system-reminder
- Doing Tasks Section — 行为准则
- Actions Section — 风险评估
- Using Your Tools Section — 工具使用指南
- Tone and Style Section
- Output Efficiency Section

### 动态层（会话特定）

- Session-specific guidance（fork/Explore/verification 指引）
- Memory（agent 记忆）
- Environment info（cwd, OS, model, git）
- Language preference、Output style
- MCP instructions（**uncached**，每轮重算）
- Scratchpad instructions
- Proactive section

### Section 管理机制

`src/constants/systemPromptSections.ts`：每个动态 section 用 `systemPromptSection()` 包装，支持 memoization（`/clear` 或 `/compact` 时重置）。`DANGEROUS_uncachedSystemPromptSection()` 标记必须每轮重算的 volatile section。

## 2. Tool Prompt 设计模式

`src/Tool.ts:518` 定义了 `prompt()` 方法签名，每个工具的 prompt 是**动态计算的函数**，可访问当前权限上下文和可用工具列表。

### 工具 prompt 规律

| 工具 | 文件 | 特征 |
|------|------|------|
| Bash | `src/tools/BashTool/prompt.ts` | 最长(~370行)，含 git 安全协议、sandbox 限制、PR 创建流程、HEREDOC 示例 |
| FileEdit | `src/tools/FileEditTool/prompt.ts` | 短小精悍，强调"先读后改"、唯一性匹配、`replace_all` 用法 |
| FileRead | `src/tools/FileReadTool/prompt.ts` | 参数化模板（运行时传入 lineFormat/maxSize/offset），支持 PDF/notebook/图片 |
| Glob | `src/tools/GlobTool/prompt.ts` | 最简单，4 行纯描述 |
| Grep | `src/tools/GrepTool/prompt.ts` | 强调"永远用 Grep 而非 Bash 里的 grep/rg" |
| Agent | `src/tools/AgentTool/prompt.ts` | 最复杂，含 fork 语义、prompt 写作指南、few-shot 示例 |

### 工具间引导网络

Bash prompt 中大量引用其他工具名（通过常量 `XXX_TOOL_NAME`），形成"推荐/不推荐"网络，引导模型使用最合适的工具。例如：
```
- File search: Use Glob (NOT find or ls)
- Content search: Use Grep (NOT grep or rg)
- Read files: Use Read (NOT cat/head/tail)
```

Agent prompt 有 "When NOT to use" 反向引导，防止过度使用子 agent。

## 3. Few-shot 示例设计

### Agent Tool 的 few-shot（`prompt.ts:115-188`）

使用 `<example>` XML 标签包裹，内含 `<commentary>` 标签解释推理过程（给模型看的，非用户可见）。

Fork 模式示例特别展示了"异步等待"的正确行为：不要编造结果，不要 poll，等通知到达。

### 关键设计

- 示例聚焦边界情况（异步等待、anti-rationalization），非常见场景
- `<commentary>` 教会模型"思考模式"而非仅"行为模式"
- HEREDOC 格式示例嵌入在 Bash prompt 中

## 4. Anti-rationalization Prompt

`src/tools/AgentTool/built-in/verificationAgent.ts:54-61`

明确列出模型会产生的合理化借口：
```
- "The code looks correct" — reading is not verification. Run it.
- "The implementer's tests already pass" — the implementer is an LLM. Verify independently.
- "This is probably fine" — probably is not verified. Run it.
```

这是一种"预判失败模式"的 prompt 技术，比泛泛的"be thorough"有效得多。

## 5. Subagent Prompt 差异

| 维度 | 主 Agent | 子 Agent |
|------|---------|---------|
| System prompt | 完整分层结构(~15个 section) | agent 自身 prompt + 环境信息 |
| CLAUDE.md | 完整注入 | Explore/Plan 可省略（省 token） |
| gitStatus | 包含（可能 40KB） | Explore/Plan 省略 |
| Thinking | 用户配置 | 子 agent 默认 disabled |
| 工具集 | 全部 | 通过 `resolveAgentTools()` 过滤 |

## 6. Prompt Cache 优化策略

1. **全局缓存前缀**：`SYSTEM_PROMPT_DYNAMIC_BOUNDARY` 之前跨用户共享
2. **工具排序**：内置工具连续前缀 + MCP 工具追加在后，服务端在最后一个内置工具后设 cache breakpoint
3. **Agent 列表 attachment 分离**：从 tool description 移到 `agent_listing_delta` attachment，避免 MCP 连接/断开 bust cache
4. **Fork byte-identical 前缀**：fork child 的 API 请求前缀与父级字节级相同，复用 cache
5. **Temp 目录规范化**：sandbox 的 temp dir 路径替换为 `$TMPDIR`，使 prompt 跨用户完全相同
6. **Compact 不设 maxOutputTokens**：设置它会改变 thinking config，破坏 cache key 匹配

## 7. Skill 注入机制

Skills 不嵌入 system prompt，通过三种方式按需注入：
1. **system-reminder 列表**：每轮开始时注入可用 skills 概览（预算：context 的 1%）
2. **SkillTool 调用时展开**：调用后完整 prompt 作为 user message 注入
3. **Agent 预加载**：agent frontmatter 的 `skills` 字段在启动时预加载

## 8. "Never delegate understanding"

`src/tools/AgentTool/prompt.ts:112`：禁止将理解工作推给子 agent（"based on your findings, fix the bug"），要求主 agent 先理解再分配。防止"把思考推给子 agent"的懒惰模式。
