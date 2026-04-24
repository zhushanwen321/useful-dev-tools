---
name: cc-agent-design
description: Use when designing, building, or evaluating an AI coding agent system. Covers Prompt engineering, Context engineering, Harness engineering, Agent loop design, and evaluation dimensions. Provides access to Claude Code source code analysis and local wiki knowledge base for comparison. Triggers include designing agent architecture, choosing tool systems, implementing context management, building permission models, or benchmarking against Claude Code.
---

# CC Agent Design: Claude Code 架构设计参考

基于 Claude Code 源码的深度分析，提炼 AI Coding Agent 的设计最佳实践框架。

## 源码与知识库导航

### Claude Code 源码

- **本地路径**: `/Users/zhushanwen/GitApp/claude-code-source-code/`
- **版本**: v2.1.88 | ~1,884 源文件，~512,664 行代码
- **代码探索**: 使用 `explore-codebase` 技能，graph 数据库：`/Users/zhushanwen/GitApp/claude-code-source-code/.code-review-graph/graph.db`

### 知识库 Wiki

路径: `/Users/zhushanwen/Documents/Knowledge/`

**核心概念页面**（设计模式级）:

| 页面 | 核心内容 |
|------|---------|
| `wiki/entity/Claude Code.md` | 实体总览、技术架构、综合评分 |
| `wiki/concept/上下文压缩.md` | 4 层压缩管线、缓存策略 |
| `wiki/concept/工具系统.md` | 工具定义、执行、泛型接口 |
| `wiki/concept/权限控制.md` | 6 层权限防线、安全默认 |
| `wiki/concept/记忆系统.md` | 提取 + 巩固 + 同步 |
| `wiki/concept/多层错误恢复.md` | 渐进式恢复、熔断器 |
| `wiki/concept/Agent 分叉机制.md` | 状态克隆、CacheSafeParams |
| `wiki/concept/Withholding 机制.md` | 可恢复错误的隐藏 |
| `wiki/concept/流式工具执行.md` | 并发安全、错误级联取消 |
| `wiki/concept/异步生成器模式.md` | Agent 循环核心模式 |

**深度分析页面**（设计哲学级）:

| 页面 | 核心内容 |
|------|---------|
| `wiki/source/28-深度分析-设计原则与协同效应.md` | 三大设计原则及协同效应 |
| `wiki/source/30-总结-设计模式与协同关系.md` | 12 种核心设计模式及依赖图 |

完整源码导航和 wiki 索引见 [references/source-navigation.md](references/source-navigation.md)

## Overview

Agent 的能力上限由模型决定，但实际交付质量由 Harness 决定。2026 年的核心转变是从优化 prompt/context 转向设计整个运行环境。

三个工程层次：

| 层次 | 核心问题 | 设计目标 |
|------|---------|---------|
| **Prompt Engineering** | "应该问什么？" | 发送给 LLM 的指令文本 |
| **Context Engineering** | "应该展示什么？" | LLM 推理时可用的所有 token |
| **Harness Engineering** | "如何设计整个环境？" | 约束、反馈和运行系统 |

## 评判维度总览

10 个核心维度，详见 [references/evaluation-dimensions.md](references/evaluation-dimensions.md)：

1. **Prompt 工程** — system prompt 结构、tool prompt、few-shot、指令分层
2. **Context 工程** — 上下文窗口管理、压缩策略、记忆系统
3. **Harness 工程** — 工具系统、权限模型、安全沙箱、Hook 系统
4. **Agent Loop** — 循环结构、终止条件、错误恢复、重试策略
5. **子 Agent 调度** — 隔离、权限继承、异步/fork 模式
6. **多模态能力** — 图像、文件、跨模态推理
7. **用户体验** — 流式输出、进度反馈、可调试性
8. **成本工程** — 分层模型路由、token 预算、收益递减检测
9. **运维与可观测性** — 遥测管道、Feature Flag、VCR、启动优化
10. **多 Agent 协作** — Coordinator/Worker、Team 系统、邮箱通信

## Quick Reference: Claude Code 核心设计决策

### Prompt 工程

| 设计点 | Claude Code 做法 | 关键文件 |
|--------|-----------------|----------|
| System Prompt | 分层组装：静态层(可缓存) + 动态层(会话特定)，用 `__SYSTEM_PROMPT_DYNAMIC_BOUNDARY__` 分隔 | `src/constants/prompts.ts` |
| Tool Prompt | 每个工具有 `prompt()` 动态函数，可访问权限上下文；工具间用"推荐/不推荐"网络引导选择 | `src/Tool.ts`, 各工具 `prompt.ts` |
| Prompt Cache | 工具排序保持内置工具连续前缀，服务端在最后一个内置工具后设 cache breakpoint | `src/tools.ts:354` |
| Skill 注入 | 通过 `system-reminder` 列表注入，预算控制在 context 的 1%，bundled skills 优先保留 | `src/tools/SkillTool/prompt.ts` |
| Anti-rationalization | 预判模型合理化借口并要求"识别后做相反的事"（Verification Agent） | `built-in/verificationAgent.ts:54` |

详见 [references/prompt-engineering.md](references/prompt-engineering.md)

### Context 工程

| 设计点 | Claude Code 做法 | 关键文件 |
|--------|-----------------|----------|
| 多层压缩 | Snip → Microcompact → SM Compact → Full Compact → Reactive Compact，梯度响应 | `src/services/compact/` |
| Auto-compact | 上下文达 ~95% 时触发，优先 Session Memory Compaction（免 API 调用），fallback 到传统 compact | `src/services/compact/autoCompact.ts` |
| Cached Microcompact | 通过 API `cache_edits` 删除旧 tool results，不破坏 prompt cache 前缀 | `src/services/compact/microCompact.ts` |
| Session Memory | 后台持续运行的记忆提取系统，post-sampling hook 触发，9 个 section 模板，12K token 上限 | `src/services/SessionMemory/` |
| 熔断器 | 连续 3 次 compact 失败后停止（防止无限循环浪费 API 调用） | `autoCompact.ts:68` |

详见 [references/context-engineering.md](references/context-engineering.md)

### Harness 工程

| 设计点 | Claude Code 做法 | 关键文件 |
|--------|-----------------|----------|
| 工具架构 | 静态注册 + feature flag 条件编译 + 动态 MCP 合并，`assembleToolPool()` 唯一入口 | `src/tools.ts` |
| 权限模型 | 四级决策（allow/deny/ask/passthrough），deny 永远优先；LLM 分类器推测执行与 UI 并行 | `src/hooks/toolPermission/` |
| 安全沙箱 | 三层决策（全局→显式→排除），复合命令逐子命令检查防逃逸 | `src/tools/BashTool/shouldUseSandbox.ts` |
| Hook 系统 | 27 种事件类型，AsyncGenerator 执行模型，shell/http/agent 三种执行方式 | `src/utils/hooks.ts` |
| 竞态保护 | `ResolveOnce.claim()` 原子化 check-and-set，解决分类器和用户同时决策的竞态 | `PermissionContext.ts:63` |

详见 [references/harness-engineering.md](references/harness-engineering.md)

### Agent Loop

| 设计点 | Claude Code 做法 | 关键文件 |
|--------|-----------------|----------|
| 循环结构 | `while (true)` + AsyncGenerator，State 对象在迭代间传递 | `src/query.ts:307` |
| 终止条件 | 10 种退出路径（completed/aborted/max_turns/model_error/blocking_limit 等） | `src/query.ts:1357` |
| 错误恢复 | withRetry 指数退避(最多10次) + 模型 fallback(Sonnet) + 多层上下文恢复 + withheld 机制 | `src/services/api/withRetry.ts` |
| 流式工具执行 | StreamingToolExecutor 在模型 streaming 期间就执行已接收的 tool_use | `src/query.ts:1366` |
| Fork Cache 共享 | 所有 fork child 产生 byte-identical API 请求前缀，最大化 prompt cache 命中 | `src/tools/AgentTool/forkSubagent.ts` |

详见 [references/agent-loop.md](references/agent-loop.md)

### 成本工程与运维

| 设计点 | Claude Code 做法 | 关键文件 |
|--------|-----------------|----------|
| 分层模型路由 | Haiku 做安全分类，regex 做情绪检测，SM Compact 免 API 调用 | `bashPermissions.ts`, `tokenBudget.ts` |
| 收益递减检测 | 连续 3 轮 output < 500 tokens 自动停止 | `src/query/tokenBudget.ts` |
| Feature Flag | 89 个编译期(DCE) + 60+ 运行时(GrowthBook)，渐进式发布 | `src/services/analytics/growthbook.ts` |
| AutoDream | REPL 空闲时做记忆整合（24h 门控，Forked agent 零额外 token） | `src/services/autoDream/` |
| Coordinator 模式 | 研究→并行，实现→串行，验证→并行，Worker 间不通信 | `src/coordinator/` |
| 遥测管道 | 双层（1P 全量 + Datadog 白名单），采样、killswitch、隐私保护 | `src/services/analytics/` |
| 怀疑式记忆 | 记忆视为"不可靠提示"，行动前必须验证；只在成功写入后更新 | `src/memdir/`, `src/tools/AgentTool/agentMemory.ts` |

详见 [references/operations-and-scalability.md](references/operations-and-scalability.md)

## 设计原则速查

三大核心原则（详见 wiki `28-深度分析-设计原则与协同效应.md`）：

1. **防御性乐观** — 正常路径极致优化 + 异常路径多层恢复
2. **信息保真度优先** — 有限预算内最大化有用信息，渐进修约而非简单截断
3. **可恢复性设计** — 故障是常态，每种故障有降级路径

12 种核心模式（详见 wiki `30-总结-设计模式与协同关系.md`）：

| 模式组 | 模式 | 核心思想 |
|--------|------|---------|
| 架构 | 异步生成器管道 | 整个 Agent 系统是异步生成器管道 |
| 架构 | 不可变状态转换 | 状态不被修改，而是被全新对象替换 |
| 架构 | 多层管道 | 复杂转换分解为有序管道阶段 |
| 可靠性 | 熔断器 | 连续失败达阈值后停止（3 次） |
| 可靠性 | 流式工具执行 | 模型流式输出时就开始执行工具 |
| 可靠性 | 渐进式降级 | 每种故障准备从低到高代价的恢复策略 |
| 性能 | 双缓冲 | 同步数据源 + 异步渲染状态同时维护 |
| 性能 | CacheSafeParams | Fork 参数选择保持 cache key 不变 |
| 性能 | 双向验证 | 同时检查正向和反向一致性 |
| 安全 | Fail-Closed 默认值 | 每个决策默认保守，要求显式声明开放 |
| 安全 | Sticky-on Latch | 某些决策一旦做出就不可撤回 |
| 安全 | 预编译匹配闭包 | 为 hook 条件预编译正则 |

## Common Mistakes

| 错误做法 | 正确做法 |
|---------|---------|
| 单一压缩策略处理所有上下文问题 | 多层梯度响应，每层有独立触发条件 |
| 工具 prompt 写死在 system prompt | 动态 `prompt()` 函数，按需组装 |
| 权限全靠 LLM 判断 | 确定性代码做关键检查，LLM 做辅助分类 |
| 忽视 prompt cache | 工具排序、动态/静态分离、byte-identical fork，跟踪 cache-break 向量 |
| 子 agent 共享完整上下文 | 隔离上下文、过滤工具、省略非必要信息 |
| 错误只做简单重试 | withheld + fallback + 熔断器多层恢复 |
| 所有决策都用最贵的模型 | 分层路由：regex → Haiku → 主模型，按需升级 |
| 记忆作为可信事实 | 怀疑式记忆：带索引的提示，行动前验证 |
| 复杂状态机控制 Agent 流程 | 简单 while 循环 + State 对象，复杂性留给 harness |
| 安全规则放在单独的配置文件 | 嵌入在工具描述中，模型每次调用都能看到约束 |

## 参考资源

### 本地知识库

- **Wiki 索引**: `/Users/zhushanwen/Documents/Knowledge/wiki/index.md`
- **原始分析文档**: `/Users/zhushanwen/Documents/Knowledge/raw/CodexCliSourceDesignAnalyze/`（30+ 篇）

### 网络文章（2026 年 3 月源码泄露后）

- [waiterxiaoyy/Deep-Dive-Claude-Code](https://github.com/waiterxiaoyy/Deep-Dive-Claude-Code) — 13 章深度分析
- [amitshekhariitbhu/claude-code-codebase-architecture-report](https://github.com/amitshekhariitbhu/claude-code-codebase-architecture-report) — 全面架构分析
- [Particula Tech: 7 Agent Architecture Lessons](https://particula.tech/blog/claude-code-source-leak-agent-architecture-lessons) — 7 个生产级 Agent 模式
- [HarrisonSec: The 1,421-Line While Loop](https://harrisonsec.com/blog/claude-code-deep-dive-query-loop/) — query.ts 逐行分析
- [codewithmukesh: Anatomy of a Claude Code Session](https://codewithmukesh.com/blog/anatomy-claude-code-session/) — 会话生命周期
- [WaveSpeed AI: Architecture Deep Dive](https://wavespeed.ai/blog/posts/claude-code-architecture-leaked-source-deep-dive/) — 工具系统、查询引擎
- [vrungta: Claude Code Architecture (Reverse Engineered)](https://vrungta.substack.com/p/claude-code-architecture-reverse) — 设计支柱
- [Bits Bytes NN: Architecture Analysis](https://bits-bytes-nn.github.io/insights/agentic-ai/2026/03/31/claude-code-architecture-analysis.html) — 4 层压缩管道

## 数据验证说明

| 数据项 | 验证方法 | 验证结果 |
|-------|---------|---------|
| Prompt cache-break 向量 | grep `promptCacheBreakDetection.ts` 的 `*Changed` 字段 | **12**（非声称的 14） |
| 编译期 feature flags | grep -roh "feature('[^']*')"\|sort -u\|wc -l | **89 个** |
| Bash 安全检查 ID | grep `bashSecurity.ts` SECURITY_CHECK_ID 枚举 | **23 个** |
| 收益递减阈值 | grep `tokenBudget.ts` DIMINISHING_THRESHOLD | **500 tokens** |
| bashSecurity.ts 行数 | wc -l | **2,592 行** |
| BashTool 目录总行数 | wc -l | **10,894 行** |
