# Claude Code Agent Loop 设计详解

源码位置：`~/GitApp/claude-code-source-code/`

## 1. 循环结构：while-true + AsyncGenerator

`src/query.ts:241` `queryLoop()` — 不是事件驱动，是经典的 agentic loop。

```
QueryEngine.submitMessage()  ← 会话级生命周期
  └→ query()                 ← 命令生命周期、资源清理
       └→ queryLoop()        ← 核心 while-true 循环
```

三层架构，每层有自己的职责边界。State 对象在循环迭代间传递状态。

### 单次迭代流程

```
preProcessing:
  snipCompactIfNeeded()      → 历史裁剪
  microcompact()             → 微型压缩
  applyCollapsesIfNeeded()   → 上下文折叠
  autocompact()              → 自动压缩

apiCall:
  deps.callModel()           → 调用 Claude API（streaming）
  → yield 每个 StreamEvent / Message

toolExecution:
  StreamingToolExecutor      → 流式执行已接收的 tool_use
  runTools()                 → 执行剩余工具

postProcessing:
  getAttachmentMessages()    → 注入附件
  pendingMemoryPrefetch      → 消费内存预取

stateUpdate → continue
```

## 2. 终止条件

10 种退出路径：

| 终止原因 | 条件 |
|---------|------|
| `completed` | 模型返回无 tool_use，stop hooks 通过 |
| `aborted_streaming` | 用户在 streaming 期间中断 |
| `aborted_tools` | 用户在工具执行期间中断 |
| `max_turns` | 达到 maxTurns 限制 |
| `model_error` | API 调用抛出未预期异常 |
| `blocking_limit` | 上下文超出硬限制且压缩关闭 |
| `prompt_too_long` | reactive compact 也无法恢复 |
| `image_error` | 图片大小/处理错误 |
| `stop_hook_prevented` | Stop hook 主动阻止 |
| `hook_stopped` | 工具执行中的 hook 阻止 |

关键判断点：`if (!needsFollowUp)` — 响应不包含 tool_use 则进入终止逻辑。

## 3. 错误恢复

### API 重试（`src/services/api/withRetry.ts`）

- 指数退避 + 抖动：base 500ms，最大 32s
- 可重试：429（仅 Enterprise）、529（始终，最多 3 次后 fallback）、401（刷新 token）、408/409/5xx
- 最大重试次数：10 次
- Foreground 重试 529；Background 立即放弃
- Fast Mode：短 retry-after 保持 fast mode；长 retry-after 进入 cooldown

### 模型 Fallback

非自定义 Opus 连续 529 达 3 次时，切换到 Sonnet 重试。处理：
1. 产出 tombstone 消息清除已 yield 的部分 assistant 消息
2. 丢弃 streaming executor 的挂起结果
3. 剥离 thinking signature blocks（不同模型签名不兼容）

### 上下文溢出多层恢复

```
Proactive autocompact → Microcompact → Snip → Context Collapse →
Reactive Compact → Max output tokens recovery (3 次递增) → Escalated max tokens (8k→64k)
```

### Withheld 机制

可恢复的错误在 streaming 期间被"扣留"，不 yield 给调用方。解决 SDK 在收到 error 后立即终止 session 的问题。

### Stop Hooks 防死循环

最后一条消息是 API error 时跳过 stop hooks。防止 stop hook → blocking error → 重试 → API error → stop hook 的死循环。

## 4. 流式工具执行

`StreamingToolExecutor` 在模型 streaming 期间就开始执行已接收到的 tool_use blocks，而不是等整个响应完成。减少工具执行等待时间。

## 5. 子 Agent 调度

### 三种模式

**同步**：共享 abortController 和 setAppState，阻塞父级循环。

**异步**：独立 AbortController 和状态管理，后台运行，通过 `task-notification` 机制通知完成。

**Fork**：继承父级完整上下文（byte-identical API prefix），所有 tool_result 用统一占位符。防递归：检测 `FORK_BOILERPLATE_TAG`。

### Fork Prompt Cache 共享

所有 fork child 产生 byte-identical 的 API 请求前缀，只有最后的 directive 文本块不同。最大化 prompt cache 命中率。

## 6. 取消机制

AbortController 传递链：QueryEngine → queryLoop → callModel → withRetry → tools

优先级：Escape（取消当前）→ 弹出队列 → Ctrl+C（中断+可选终止后台）→ 双击 Ctrl+X Ctrl+K（终止所有后台）。

中断时 `yieldMissingToolResultBlocks()` 确保每个已 yield 的 tool_use 都有对应 tool_result。

## 7. VCR 机制（测试专用）

`src/services/vcr.ts` 实现录制回放：
- 录制模式（`VCR_RECORD=1`）：调用真实 API，写入 JSON fixture
- 回放模式（CI）：从 fixture 读取，跳过 API 调用
- 脱敏处理：CWD/config home/动态数值替换为占位符

## 8. 精巧设计

- **Withheld 机制**：可恢复错误不立即 yield，防止调用方过早终止
- **参考水印**：用对象引用（非数组索引）标记错误日志起始点，避免环形缓冲区 shift 导致索引偏移
- **Transcript 持久化策略**：assistant 消息用 `void` fire-and-forget（不阻塞 generator），user 消息用 `await`。因为 assistant 消息会在 message_delta 时被修改
- **Feature Gate DCE**：`feature()` 包裹 `require()`，结合 bun:bundle tree-shaking，关闭的功能完全移除
- **Stop Hooks 防死循环**：API error 后跳过 stop hooks
