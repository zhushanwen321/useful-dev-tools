# 源码导航与知识库索引

## Claude Code 源码

- **本地路径**: `/Users/zhushanwen/GitApp/claude-code-source-code/`
- **版本**: v2.1.88
- **代码规模**: ~1,884 个源文件，~512,664 行代码
- **探索方式**: 使用 `explore-codebase` 技能查看代码库
- **Graph 数据库**: `/Users/zhushanwen/GitApp/claude-code-source-code/.code-review-graph/graph.db`

## 核心源码目录结构

```text
src/
├── query.ts                    # Agent Loop 核心（1,729 行，while-true 循环）
├── QueryEngine.ts              # 会话级生命周期管理
├── Tool.ts                     # 工具基类（~30 个方法）
├── tools.ts                    # 工具注册与合并入口
├── constants/prompts.ts        # System Prompt 组装（914 行）
├── constants/systemPromptSections.ts  # 动态 section 管理
├── services/
│   ├── compact/                # 上下文压缩系统（5 层梯度）
│   ├── SessionMemory/          # 会话记忆系统
│   ├── AgentSummary/           # Agent 摘要（每 30s 更新）
│   ├── autoDream/              # 空闲时记忆整合（四阶段）
│   ├── extractMemories/        # 每轮结束后记忆提取
│   ├── analytics/              # 遥测（1P + Datadog 双层）
│   ├── api/withRetry.ts        # API 重试与 fallback
│   ├── lsp/                    # LSP 集成
│   └── vcr.ts                  # VCR 录制回放（测试）
├── tools/
│   ├── AgentTool/              # 子 Agent 系统
│   │   ├── runAgent.ts         # Agent 运行逻辑
│   │   ├── prompt.ts           # Agent prompt（含 few-shot）
│   │   ├── built-in/           # 内置 Agent（Explore/Plan/Verify/Guide）
│   │   ├── forkSubagent.ts     # Fork 子 Agent（cache 共享）
│   │   └── agentMemory.ts      # Agent 记忆（user/project/local）
│   ├── BashTool/               # Bash 执行（2,500+ 行安全代码）
│   ├── FileEditTool/           # 文件编辑
│   ├── SkillTool/              # Skill 系统
│   └── MCPTool/                # MCP 工具桥接
├── coordinator/                # Coordinator/Worker 多 Agent 协作
├── hooks/toolPermission/       # 权限系统（四级决策 + 推测分类器）
├── utils/
│   ├── hooks.ts                # Hook 系统（27 种事件）
│   └── undercover.ts           # Undercover 模式
├── memdir/                     # 记忆目录管理
└── skills/bundled/             # 内置 Skills
```

## 知识库 Wiki 索引

知识库路径: `/Users/zhushanwen/Documents/Knowledge/`

### 实体与概念页面

| Wiki 页面 | 核心内容 |
|-----------|---------|
| `wiki/entity/Claude Code.md` | 实体总览、技术架构、综合评分 4.8/5.0 |
| `wiki/concept/Agent 系统.md` | 多 Agent 架构、子 Agent、Agent 分叉 |
| `wiki/concept/Agent 分叉机制.md` | 状态克隆、并行探索、CacheSafeParams |
| `wiki/concept/上下文压缩.md` | 4 层压缩管线、缓存策略 |
| `wiki/concept/工具系统.md` | 工具定义、执行、泛型接口 |
| `wiki/concept/权限控制.md` | 6 层权限防线、安全默认 |
| `wiki/concept/记忆系统.md` | 提取 + 巩固 + 同步 |
| `wiki/concept/多层错误恢复.md` | 渐进式恢复、熔断器、Withholding |
| `wiki/concept/流式工具执行.md` | 并发安全、错误级联取消 |
| `wiki/concept/Withholding 机制.md` | 可恢复错误的隐藏设计 |
| `wiki/concept/异步生成器模式.md` | Agent 循环核心模式 |
| `wiki/concept/状态不可变更新.md` | 可回滚的状态管理 |
| `wiki/concept/任务系统.md` | 任务状态机、异步执行 |
| `wiki/concept/MCP 协议.md` | 6 种传输方式、工具扩展 |

### 深度分析页面

| Wiki 页面 | 核心内容 |
|-----------|---------|
| `wiki/source/28-深度分析-设计原则与协同效应.md` | 三大设计原则：防御性乐观、信息保真度、可恢复性 |
| `wiki/source/29-深度分析-精妙设计的工程逻辑.md` | 具体实现中的精妙设计决策 |
| `wiki/source/30-总结-设计模式与协同关系.md` | 12 种核心设计模式及协同依赖图 |
| `wiki/source/31-总结-工程洞察与设计启示.md` | 工程层面的洞察与启示 |

### 原始分析文档

`raw/CodexCliSourceDesignAnalyze/` 目录下 30+ 篇源码分析文档，涵盖：
- 核心系统（Agent 循环、上下文管理、工具系统、子代理、MCP、技能、记忆、权限、插件、命令）
- 前端交互（CLI、REPL、React UI、React Hooks、Ink 渲染、输入系统、键绑定、对话 UI）
- 基础设施层（API 服务、Bridge、消息系统、文件系统、Forked Agent、配置与设置）
- 深度分析（设计原则、精妙设计、设计模式、工程洞察）
