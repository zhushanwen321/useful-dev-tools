# Claude Code 运维与可扩展性设计详解

源码位置：`~/GitApp/claude-code-source-code/`

## 1. 成本优化：分层模型路由

**核心原则**：不是每个决策都需要最贵的模型。

| 决策类型 | 使用的模型/方法 | 原因 |
|---------|---------------|------|
| 安全分类 | Haiku（最小最便宜） | 结构化安全检查不需要前沿推理 |
| 情绪检测 | regex（`userPromptKeywords.ts`） | regex 能解决的不烧 token |
| Microcompact | 本地操作，零 API 调用 | 只在本地不够时才升级 |
| 上下文压缩 | Session Memory Compact（免 API） | 优先用已有记忆替代 summary 生成 |
| 权限分类器 | 推测执行 Haiku | 与 UI 并行，用户可能还没看到对话框就自动批准了 |

**成本数据**（来自 codewithmukesh 测量）：
- 新会话启动开销：~8,700 tokens（system prompt ~2,900 + tools ~3,000 + CLAUDE.md ~1,200 + rules ~500 + git status ~300 + skills ~800）
- 简单 bug 修复：30,000-50,000 tokens
- 复杂重构：150,000-200,000 tokens
- 平均成本：~$6/开发者/天，90th percentile < $12/天

## 2. 收益递减检测

`src/query/tokenBudget.ts`

连续 3 轮 delta < 500 tokens 时判定为 diminishing returns，触发早期停止。防止模型无限循环地说"让我再试一次修复"而空烧 token。

实现方式：跟踪每轮 output tokens，当 `consecutiveSmallOutputs >= 3` 且 `progress < 90%` budget 时，注入 stop 指令。

## 3. Feature Flag 双层架构

### 编译期 Flag（89 个）

通过 `feature('XXX')` 包裹 `require()`，结合 Bun 的 tree-shaking 实现死代码消除。关闭的功能完全从构建产物中移除。

**验证结果**：源码 `grep -roh "feature('[^']*')"` 确认存在 89 个唯一编译期 feature flag。

关键类别：
- 核心功能：`EXTRACT_MEMORIES`, `CONTEXT_COLLAPSE`, `TOKEN_BUDGET`
- 协作能力：`TEAMMEM`, `FORK_SUBAGENT`, `BG_SESSIONS`
- 平台特性：`KAIROS`, `BRIDGE_MODE`
- 安全防护：`COMMIT_ATTRIBUTION`, `ANTI_DISTILLATION_CC`

### 运行时 Flag（60+ 个）

通过 GrowthBook `tengu_*` 动态下发，非阻塞读取（磁盘缓存）。支持环境变量覆盖、配置覆盖、分层降级。

**刷新周期**：外部用户 6h，内部 20min。

## 4. AutoDream — 空闲时记忆整合

`src/services/autoDream/autoDream.ts`

利用 REPL 空闲时间（每轮查询结束时）运行后台记忆整合。

**三级门控**（从最廉价到最昂贵）：
1. **Time gate**：距上次整合 >= minHours（默认 24h），开销仅 1 次 stat
2. **Session gate**：新增 session 数 >= minSessions（默认 5）
3. **Lock**：无其他进程正在整合（基于文件的 PID 锁）

**四阶段整合**：Orient → Gather → Consolidate → Prune

**成本控制**：通过 `runForkedAgent` 复用主会话 prompt cache，零额外 token 开销。子 agent 只使用只读工具 + 记忆目录内的写操作。

## 5. Coordinator/Worker 多 Agent 协作

`src/coordinator/coordinatorMode.ts`

编译期 feature flag `COORDINATOR_MODE` 控制。

**角色模型**：
- **Coordinator**：不直接写代码，负责理解需求、分解任务、综合结果
- **Worker**：通过 Agent 工具 spawn，独立执行任务

**关键约束**：
- Worker 之间不可互相通信，只能通过 Coordinator 中转
- Coordinator 必须自己理解研究结果后才能写 prompt 给实现 worker
- Scratchpad 目录提供跨 worker 的共享知识空间

**并发策略**：
- 只读任务（研究）可自由并行
- 写入任务（实现）每个文件集合一次一个
- 验证可与实现并行（不同文件区域）

## 6. 可观测性/遥测

`src/services/analytics/`

**双层管道**：
- **1P Event Logging**：所有事件，包含 PII
- **Datadog**：白名单 30+ 个事件，自动 strip PII

**关键机制**：
- Event Sampling（采样率控制）
- Sink Killswitch（`tengu_frond_boric` 可动态关闭整个管道）
- 用户桶化（SHA256 哈希分 30 桶，估计影响范围）
- 队列缓冲（启动前的事件排队，sink attach 后异步 drain）
- 3P 提供商（Bedrock/Vertex）完全禁用 analytics

## 7. 启动序列优化

`src/setup.ts`

**关键优化**：
- GrowthBook init：`getFeatureValue_CACHED_MAY_BE_STALE` 从磁盘缓存读取，不阻塞启动
- LSP：异步初始化，不阻塞主流程
- Plugin prefetch：与主流程并行
- 启动前的事件排队，sink attach 后异步 drain

**启动步骤**：Node.js 版本检查 → UDS Server 启动 → Teammate snapshot → Terminal backup → Hooks 配置快照 → Worktree 创建 → **并行启动**（SessionMemory、ContextCollapse、版本锁定） → Prefetch

## 8. Undercover 模式

`src/utils/undercover.ts`

防止 Anthropic 内部信息泄露到公开仓库：
- AUTO 模式：除非确认在内部 repo，否则默认开启
- Strip 所有 Co-Authored-By 行
- 提示模型不使用内部代号
- 通过 `USER_TYPE === 'ant'` 编译期消除，外部版本无此功能

## 9. "怀疑式记忆"模式

记忆系统将自身内容视为**不可靠**：
- MEMORY.md 作为轻量索引（最多 200 行），详细内容按需加载
- agent 被明确指示：在基于记忆采取行动前，必须先在代码库中验证
- 只在文件成功写入后更新记忆索引（防止失败尝试污染记忆）
- autoDream 在空闲时做垃圾回收（合并、去矛盾、确认）

## 10. LSP 集成

`src/services/lsp/manager.ts`

- 按需启动（首次访问某类型文件时）
- 全生命周期文件同步（didOpen/didChange/didSave/didClose）
- 诊断信息通过 `passiveFeedback.ts` 自动注入上下文
- Generation counter 防止 stale 初始化

## 11. Swarm/Team 系统

- **Team Lead**：协调者，通过 `TeamCreate`/`TeamDelete` 管理
- **Teammate**：在 tmux 中运行的 worker agent
- **通信**：邮箱系统（`teammateMailbox`），非直接消息传递
- 每个 teammate 独立 tmux pane，UDS messaging server 进程间通信
