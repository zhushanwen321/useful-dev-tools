# LLM Agent 设计评判维度

## 维度定义

### 1. Prompt Engineering（提示工程）

**核心问题：应该问什么？**

关注点：
- System prompt 的结构与层次（角色→约束→能力→输出规范）
- Tool prompt 的 schema 设计（参数描述、使用场景、返回值格式）
- Few-shot examples 的选择与编排（聚焦边界情况，非常见场景）
- 指令的清晰度与无歧义性
- Prompt Cache 优化策略

### 2. Context Engineering（上下文工程）

**核心问题：应该展示什么？**

关注点：
- 上下文窗口的生命周期管理（LangChain 四模式：Write/Select/Compress/Isolate）
- 记忆系统设计（工作记忆、长期记忆、跨会话记忆）
- 代码索引与语义检索（RAG、embedding）
- Context compression 策略（摘要、滑动窗口、分层压缩）
- Token 效率（每个 token 的 ROI）

### 3. Harness Engineering（运行环境工程）

**核心问题：如何设计整个环境？**

OpenAI 2026 年提出：Agent = Model + Harness。Harness 包含约束、反馈循环、脚手架和运维系统。

关注点：
- 工具系统的设计哲学（原子工具 vs 复合工具、工具数量控制）
- 权限模型（分级审批、自动允许/需确认/禁止）
- 安全沙箱与隔离机制（VM 隔离、文件系统沙箱、网络限制）
- Hook 系统（lint on save、audit on shell、gate on deploy）
- 事件系统与可观测性（日志、追踪、replay）

### 4. Agent Loop Design（循环设计）

**核心问题：如何让 Agent 持续工作？**

关注点：
- 循环结构（while-tool-use 模式、状态机、事件驱动）
- 错误恢复策略（重试、降级、人工介入）
- 终止条件（自然终止、预算上限、收益递减检测）
- 规划机制（TODO list、动态 replan、子任务分解）
- 流式执行（streaming tool execution）

### 5. Sub-agent Scheduling（子 Agent 调度）

**核心问题：如何分解和隔离任务？**

关注点：
- 同步/异步/fork 三种调度模式
- 上下文隔离与继承
- 工具权限继承与过滤
- MCP 服务器继承
- 记忆共享策略

### 6. Multimodal Capabilities（多模态能力）

**核心问题：如何处理非文本输入？**

关注点：
- 图像理解（截图分析、UI 理解、图表解读）
- 文件处理（PDF、Jupyter notebook、视频）
- 跨模态推理（从图像中提取信息用于代码生成）
- 专用工具 vs 通用工具的取舍

### 7. User Experience（用户体验）

**核心问题：如何让用户信任和理解 Agent？**

关注点：
- 流式输出（SSE、token 级实时反馈）
- 进度反馈（任务状态、步骤追踪）
- 交互模式（自主模式 vs 协作模式）
- 可调试性（消息历史、决策链路追踪、replay）

### 8. Cost Engineering（成本工程）

**核心问题：如何用最少的 token 做最多的事？**

关注点：
- 分层模型路由（cheap models for cheap decisions）
- Token 预算追踪与收益递减检测
- Prompt Cache 利用率优化
- 新会话开销控制（Claude Code 基线 ~8,700 tokens）
- 压缩成本与信息保留的权衡

### 9. Operations & Observability（运维与可观测性）

**核心问题：如何监控、调试和持续改进 Agent？**

关注点：
- 遥测管道设计（双层管道、采样、killswitch）
- Feature Flag 系统（编译期 + 运行时，渐进式发布）
- VCR 录制回放（测试确定性）
- 启动序列优化（并行初始化、非阻塞缓存读取）
- 空闲资源利用（autoDream 记忆整合）

### 10. Multi-Agent Collaboration（多 Agent 协作）

**核心问题：如何 scale up 到多 Agent 并行工作？**

关注点：
- Coordinator/Worker 模式（研究并行、实现串行、验证并行）
- Team 系统（tmux 隔离、邮箱通信、权限同步）
- Scratchpad 共享知识空间
- Worker 间通信限制（只能通过 Coordinator 中转）

## 业界共识

1. **Agent 的能力上限由模型决定，但实际交付质量由 Harness 决定**
2. 最成功的 agent 共享同一基础架构：一个 while 循环 + 工具调用
3. 分层记忆是主流：组织级 → 项目级 → 用户级 → 自动学习级
4. 确定性工具 > LLM 判断（关键安全环节不应依赖 LLM）
5. Prompt Cache 是生产环境的核心优化维度
6. **记忆应是"带索引的提示"而非"可信的真相"** — 行动前必须验证
7. **不是每个决策都需要最贵的模型** — 分层路由是成本控制的关键
8. **512,000 行代码中，agent 循环只占 20 行** — 复杂性在 harness，不在循环

## 评估框架参考

- **Galileo 2026 框架**：7 维度 → 25 子维度 → 130 评估项
- **SWE-bench**：代码修改能力基准
- **WebArena**：Web 操作能力基准
- **FieldWorkArena**：多模态 Agent 基准
