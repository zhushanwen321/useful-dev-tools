# Claude Code Context 工程设计详解

源码位置：`~/GitApp/claude-code-source-code/src/services/`

## 1. 多层梯度压缩体系

从轻量到重量依次为：

```
Time-based Microcompact → Cached Microcompact → Session Memory Compaction → Full Compact → Reactive Compact
```

## 2. Token 监控与阈值

`src/services/compact/autoCompact.ts:62-65`

**Token 计数策略**（`src/utils/tokens.ts:226`）：
- 有 API usage 时：使用最后一次响应的精确 `input_tokens` + 新增消息的粗估算
- 无 API usage 时：全部使用粗估算（默认 4 字节/token，JSON 用 2 字节/token）

**有效上下文窗口** = 模型上下文窗口 - min(maxOutputTokens, 20,000)

**阈值体系**：

| 缓冲区 | 大小 | 用途 |
|--------|------|------|
| Auto-compact | 13,000 tokens | 上下文达 ~95% 时触发 |
| Warning | 20,000 tokens | UI 警告 |
| Manual compact | 3,000 tokens | 手动 compact 阻断 |

**熔断器**：连续 3 次压缩失败后停止重试（`autoCompact.ts:68`）。BQ 数据显示曾有 session 连续失败 3,272 次。

## 3. Auto-compact 流程

`src/services/compact/autoCompact.ts:241`

1. 熔断器检查
2. **优先尝试 Session Memory Compaction**（免 API 调用）
3. SM 失败则 fallback 到传统 `compactConversation`
4. 成功后执行 `runPostCompactCleanup`

### Full Compact 关键设计

`src/services/compact/compact.ts:387`

- **Prompt Cache 共享**：使用 `runForkedAgent` 复用主线程 prompt cache
- **PTL 重试**：压缩请求本身太长时，从最老的 API-round group 开始丢弃，最多 3 次
- **两阶段 summary prompt**：先在 `<analysis>` 标签起草思考过程，再在 `<summary>` 写最终摘要。analysis 部分被丢弃，不浪费 context（`prompt.ts:31`）
- **Post-compact 重建**：清除 readFileState 缓存 → 重新注入最近 5 个文件（50K 预算）→ 重新注入 plan/skills/attachments

## 4. Micro-compact 机制

### Cached Microcompact（`microCompact.ts:305`）

通过 API `cache_edits` 机制在服务端删除旧 tool results：
- 不修改本地消息内容，不破坏 prompt cache 前缀
- 可清除工具：FileRead, Shell, Grep, Glob, WebSearch, WebFetch, FileEdit, FileWrite
- 基于 GrowthBook 配置的 count-based 阈值触发

### Time-based Microcompact（`microCompact.ts:446`）

- 触发条件：距上次 assistant 消息超过 60 分钟（服务器端 cache TTL = 1 小时）
- 核心洞察：cache 已冷必然被重写，不如主动清除旧 tool results 减少重写量
- 直接修改消息内容（将旧 tool result 替换为 `[Old tool result content cleared]`）
- 执行后重置 cached MC 状态

### 对比

| 维度 | Micro-compact | Full Compact |
|------|--------------|-------------|
| 触发时机 | 每次 API 调用前 | Token 超阈值时 |
| API 调用 | 无（cache editing） | 1 次（生成 summary） |
| 延迟 | ~0ms | 5-10 秒 |
| 信息损失 | 低（仅丢弃工具输出） | 高（历史压缩为摘要） |

## 5. Session Memory 系统

`src/services/SessionMemory/sessionMemory.ts`

后台持续运行的记忆提取系统，通过 post-sampling hook 实现。

**触发条件**（`shouldExtractMemory`，行 134）：
- 初始化：上下文达 10,000 tokens
- 更新：自上次提取增长 5,000 tokens 且至少 3 次 tool 调用
- 自然对话间隙：达到 token 阈值且最后一个 turn 无 tool 调用

**记忆模板**（`prompts.ts:11`）：9 个 section（Session Title、Current State、Task specification、Files and Functions、Workflow、Errors & Corrections、Codebase Documentation、Learnings、Worklog），每个 ~2,000 tokens，总量上限 12,000 tokens。

**跨会话持久化**：存储在 `~/.claude/session-memory/` 目录下的 markdown 文件中。

### Session Memory Compaction

`src/services/compact/sessionMemoryCompact.ts:514`

Auto-compact 的首选路径（优先于传统 compact）：
1. 读取 session memory 文件
2. 根据 `lastSummarizedMessageId` 确定已被记忆的消息
3. 计算保留范围（min 10K / max 40K tokens）
4. 构建 CompactionResult：session memory 作为 summary + 保留的最近消息

关键优势：不需要调用 API 生成 summary。

## 6. 消息分组

`src/services/compact/grouping.ts:22`

按 API round 边界分组（每次新的 assistant response 开始新 group）。不用 human-turn 分组，因为 SDK/eval 场景可能整个工作负载只有一个 human turn。

## 7. Agent 摘要

`src/services/AgentSummary/agentSummary.ts`

每 30 秒通过 `runForkedAgent` 生成 3-5 词进度摘要。要求现在进行时、命名具体文件/函数。与父 agent 共享 CacheSafeParams，通过 `canUseTool: deny` 禁止工具调用（不传 `tools:[]`，避免破坏 cache key）。

## 8. Away Summary

`src/hooks/useAwaySummary.ts`

终端失焦 5 分钟后自动生成 1-3 句话摘要。使用 session memory 作为上下文补充。

## 9. 精巧设计汇总

- **Prompt Cache 全链路保护**：每个环节都考虑 cache 影响
- **两阶段 summary**：analysis 作为工作空间提升质量，不浪费 context
- **Partial Compact**：支持方向性压缩（from 保护前缀 cache，up_to 保护最新上下文）
- **SM Compact 消息边界保护**：确保 tool_use/tool_result 配对、thinking 块与 tool_use 在同一切片
- **API-level Context Management**：通过 `clear_tool_uses` 和 `clear_thinking` 策略在服务端管理
