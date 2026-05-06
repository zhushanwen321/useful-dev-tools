# Force-Loop Extension 设计文档

> 日期: 2026-05-06
> 状态: 已批准

## 概述

Pi Coding Agent 扩展，通过 `/loop` 命令启动"强制完成"机制，确保 LLM 完成所有任务后才停止对话。如果模型提前停止，自动注入追问消息驱动其继续执行。

## 核心设计决策

| 决策 | 选择 | 理由 |
|------|------|------|
| 任务定义 | 混合模式（用户显式定义 或 LLM 自动规划） | 灵活性 |
| 继续机制 | 以用户消息形式追问 | 对话中可见，LLM 更重视 |
| 完成检测 | 任务清单驱动 | 明确可验证 |
| 任务标记 | 专用工具 `loop_task_tracker` | 不依赖文本解析 |
| 循环上限 | 可配置（默认 10） | 用户可控 |
| 触发方式 | `/loop <prompt>` 命令 | 简洁 |

## 架构

```
┌──────────────────────────────────────────────────────┐
│              force-loop Extension                     │
├──────────────┬───────────────┬────────────────────────┤
│  Commands    │    Tools      │       Events           │
├──────────────┼───────────────┼────────────────────────┤
│ /loop        │ loop_task_    │ before_agent_start     │
│   <prompt>   │ tracker       │   - 注入系统指令        │
│ /loop pause  │  - create     │   - 上下文预算检查      │
│ /loop resume │  - complete   │ agent_end              │
│ /loop status │  - list       │   - 任务完成检查        │
│              │               │   - 无进展检测          │
│              │               │   - 反馈注入            │
│              │               │ turn_start              │
│              │               │   - 进度追踪            │
│              │               │ session_start           │
│              │               │   (状态恢复)            │
├──────────────┴───────────────┴────────────────────────┤
│                    State (in-memory + session)         │
│  tasks[] · loopCount · maxLoops · isActive · isPaused │
│  stallCount · tasksCompletedThisTurn                   │
└───────────────────────────────────────────────────────┘
```

## 工具：loop_task_tracker

### Actions

| Action | 参数 | 说明 |
|--------|------|------|
| `create_tasks` | `tasks: string[]` | 创建任务清单，要求每个任务描述具体到文件/函数级别 |
| `complete_task` | `taskId: number` | 标记指定任务为已完成 |
| `list_tasks` | 无 | 列出当前所有任务及状态 |

### 工具元数据

- **promptSnippet:** `"创建、完成、查看任务清单，用于跟踪 /loop 命令的多步骤任务进度"`
- **promptGuidelines:**
  - `"使用 loop_task_tracker 的 create_tasks 在开始工作前拆分任务清单"`
  - `"完成每个任务后必须调用 loop_task_tracker 的 complete_task 标记，不要遗漏"`
  - `"使用 loop_task_tracker 的 list_tasks 查看当前进度和剩余任务"`

## 状态管理

```typescript
interface LoopTask {
  id: number;
  description: string;
  completed: boolean;
}

interface LoopState {
  isActive: boolean;        // 是否处于 loop 模式
  isPaused: boolean;        // 是否暂停
  tasks: LoopTask[];        // 任务列表
  loopCount: number;        // 已循环次数
  maxLoops: number;         // 最大循环次数（默认 10）
  stallCount: number;       // 连续无进展轮数
  originalPrompt: string;   // 用户原始 prompt
}
```

### 持久化与恢复

通过 `pi.appendEntry("force-loop", state)` 存入 session。`session_start` 时从 session entries 恢复：
1. 扫描 custom entries 中 `force-loop` 恢复 `maxLoops`、`originalPrompt`、`isActive`、`isPaused`
2. 扫描 toolResult entries 中 `loop_task_tracker` 的 details 重建 tasks 和 loopCount
3. 如果 `isActive` 且有未完成任务，自动恢复循环模式

## 事件处理

### before_agent_start

当 `isActive && !isPaused` 时注入系统消息：

```
[FORCE-LOOP ACTIVE — 你必须严格遵守以下规则]

1. 你的第一个操作必须是调用 loop_task_tracker 的 create_tasks，将任务拆分为可验证的具体步骤。
   每个任务必须具体到"修改/创建哪个文件的哪个部分"，禁止模糊描述。

2. 每完成一个任务，必须立即调用 loop_task_tracker 的 complete_task 标记。

3. 在标记所有任务完成前，不要说"完成"或"搞定"。

4. 原始目标：{originalPrompt}
   完成判断必须回到这个原始目标，逐项验证交付物是否存在且正确。

5. 如果遇到无法解决的问题，调用 loop_task_tracker 的 list_tasks 列出状态，
   并说明哪些任务被阻塞及原因。
```

#### 上下文预算检查

当 `ctx.getContextUsage()` 显示 token 使用超过 80% 时，替换注入内容为收尾指令：

```
[FORCE-LOOP — 上下文空间不足，必须立即收尾]
1. 用 loop_task_tracker 的 list_tasks 查看剩余任务
2. 只标记你真正完成的任务
3. 总结当前进度和剩余工作
不要再开始新任务。
```

同时设置 `isPaused = true`。

### agent_end

检查未完成任务并决定后续动作：

```
未完成任务 > 0?
├─ 是 & loopCount >= maxLoops (L1)
│   → 通知用户"已达最大循环次数"
│   → isActive = false
│
├─ 是 & stallCount >= 3 (L2)
│   → 通知用户"连续 N 轮无进展"
│   → isActive = false
│
├─ 是 & contextBudget > 80% (L3)
│   → isActive = false
│
├─ 是 & 正常情况
│   → loopCount++
│   → 更新 stallCount（本轮 0 进度则 +1，否则重置为 0）
│   → sendUserMessage(追问消息)
│
└─ 否（全部完成）
    → 通知用户"所有任务已完成 ✓"
    → isActive = false
```

#### 追问消息模板

```
你还有 {N} 个任务未完成：

{未完成任务的 id + 描述 列表}

{已完成任务摘要（如有）}

本轮完成进度: {progressThisRound} 个任务

请继续执行未完成的任务。每完成一个任务务必调用 loop_task_tracker 的 complete_task 标记。
回到原始目标验证：{originalPrompt}
```

### turn_start / turn_end

- `turn_start`: 记录 `tasksCompletedAtTurnStart = completedCount`
- `turn_end`: 计算 `progressThisRound = completedCount - tasksCompletedAtTurnStart`

### session_start

从 session entries 恢复状态（见持久化章节）。

## 安全阀机制（5 层）

| 层 | 机制 | 条件 | 行为 |
|----|------|------|------|
| L1 | 循环次数上限 | `loopCount >= maxLoops` | 停止 + 通知用户 |
| L2 | 无进展检测 | 连续 3 轮完成 0 个任务 | 停止 + 通知用户 |
| L3 | 上下文预算 | token 使用 > 80% | 注入收尾指令，不再追问 |
| L4 | 用户中断 | `/loop pause` 或会话结束 | 暂停循环 |
| L5 | 全部完成 | 所有任务 completed | 通知完成 + 退出循环 |

## 命令接口

| 命令 | 说明 |
|------|------|
| `/loop <prompt>` | 启动 loop 模式 |
| `/loop <prompt> --max 20` | 启动并设置最大循环次数（默认 10） |
| `/loop pause` | 暂停循环（不再自动追问） |
| `/loop resume` | 恢复暂停的循环 |
| `/loop status` | 显示当前状态、任务清单、循环计数 |

## Widget（TUI 实时展示）

```
┌─ loop ──────────────────────────────────┐
│ 🔄 3/10 轮 | ✓ 2/5 任务 | ⚠ 1轮无进展  │
│ ✓ #1 分析模块结构                        │
│ ✓ #2 重构函数 X                          │
│ ☐ #3 重构函数 Y                          │
│ ☐ #4 更新测试                            │
│ ☐ #5 更新文档                            │
└──────────────────────────────────────────┘
```

通过 `ctx.ui.setWidget("force-loop", lines)` 在编辑器上方显示，loop 模式结束时清除。

## 文件结构

```
~/.pi/agent/extensions/force-loop/
└── index.ts
```

单文件扩展，约 300-400 行 TypeScript。

## 设计依据

借鉴自 Ralph Loop 和 Codex `/goal` 的关键模式：
- **反代理信号坍缩**：追问消息要求 LLM 回到原始 prompt 验证，而非依赖"测试通过"
- **上下文预算监控**：接近上限时注入收尾指令
- **无进展检测**：连续多轮无进展自动停止
- **反馈注入**：追问消息包含具体进度信息
- **多层安全阀**：5 层独立防护叠加
