# Claude Code Harness 工程设计详解

源码位置：`~/GitApp/claude-code-source-code/`

## 1. 工具系统架构

### 静态注册 + 条件编译 + 动态合并

`src/tools.ts:193-251` `getAllBaseTools()` 是所有内置工具的权威来源。通过 `feature()` 函数做条件编译，结合 `bun:bundle` 的 tree-shaking，实验性功能关闭时相关代码完全从构建产物中移除。

**动态合并** `src/tools.ts:345-367` `assembleToolPool()`：
- 内置工具按名称排序保持连续前缀
- MCP 工具追加在后
- 服务端在最后一个内置工具后设全局 cache breakpoint

**工具默认值**（`src/Tool.ts:757-792`）：
```typescript
isEnabled: () => true,           // 默认启用
isConcurrencySafe: () => false,  // 默认不安全（保守）
isReadOnly: () => false,         // 默认需审批
isDestructive: () => false,      // 默认非破坏性
```

安全相关默认值都是 fail-closed。

### 延迟加载

`shouldDefer` 标记工具延迟加载（通过 `ToolSearchTool` 按需获取 schema），减少初始 prompt 中的工具数量。`alwaysLoad` 相反。

## 2. 权限模型

### 四级决策系统

`src/hooks/toolPermission/PermissionContext.ts`

| 行为 | 含义 | 后续动作 |
|------|------|----------|
| `allow` | 自动允许 | 直接执行 |
| `deny` | 自动拒绝 | 返回拒绝消息给模型 |
| `ask` | 需确认 | 显示权限对话框 |
| `passthrough` | 无匹配 | 进入默认审批流程 |

### 规则匹配优先级

`src/tools/BashTool/bashPermissions.ts:937-986`

```
精确 deny/ask → 前缀/通配符 deny → 路径约束 →
精确 allow → 前缀/通配符 allow → sed 约束 →
模式检查 → 只读规则 → passthrough
```

**deny 永远优先于 allow**。

### 规则类型

- **精确匹配**：`Bash(git commit -m "fix typo")` — 完全一致
- **前缀匹配**：`Bash(git commit:*)` — 命令前缀 + 词边界
- **通配符**：`Bash(npm run *)` — glob 风格

### LLM 分类器（推测执行）

`bashPermissions.ts:1459-1658` 使用 Haiku 对 Bash 命令进行安全分类（allow/deny/ask descriptions），三级置信度（high/medium/low），只有 high 才触发自动决策。

**推测性执行**（行 1491）：在权限检查开始时就启动分类器 API 调用，与 pre-tool hooks 和对话框渲染**并行执行**。用户看到权限对话框时，分类器可能已返回自动批准结果。

### 竞态保护

`PermissionContext.ts:63-94` `ResolveOnce.claim()`：原子化 check-and-set，解决分类器和用户同时决策的竞态。`claim()` 在 `await` 之前调用，关闭检查和 resolve 之间的时间窗口。

## 3. 安全沙箱

`src/tools/BashTool/shouldUseSandbox.ts`

三层决策：全局开关 → 显式覆盖 → 排除列表。

沙箱开启时无显式 deny/ask 规则的命令自动允许，但**复合命令逐子命令检查** deny/ask 规则（防止 `echo hello && rm -rf /` 逃逸）。

### 命令安全检查

`src/tools/BashTool/bashSecurity.ts` 23 种安全模式，包括命令替换、进程替换、Zsh 特有攻击、IFS 注入等。

**两阶段解析**：tree-sitter AST 优先，不可用时回退 legacy shell-quote 解析。tree-sitter 的 `too-complex` 直接降级为 `ask`（安全默认值）。

**Tree-sitter Shadow 模式**：`TREE_SITTER_BASH_SHADOW` feature flag 允许 tree-sitter 和 legacy 并行运行，记录分歧但不改变行为。渐进式迁移的工程实践。

## 4. Hook 系统

`src/utils/hooks.ts`

27 种事件类型：PreToolUse/PostToolUse、PermissionRequest/Denied、SessionStart/End、PreCompact/PostCompact、SubagentStart/Stop、UserPromptSubmit、FileChanged、CwdChanged 等。

**AsyncGenerator 执行模型**：允许逐步产出、串联执行、外部中断。三种执行方式：shell 命令、HTTP 请求、Agent 执行。

**工作区信任检查**：所有 hook 执行前必须通过 `shouldSkipHookDueToTrust()` 检查。

## 5. MCP 工具集成

`src/tools/MCPTool/MCPTool.ts`

通过桥接类与内置工具共存，统一使用 `mcp__server__tool` 前缀命名。支持 Stdio/SSE/StreamableHTTP 三种传输协议。权限默认 `passthrough`，支持 server 级前缀匹配。

## 6. Agent 隔离

`src/tools/AgentTool/agentToolUtils.ts`

三层黑名单过滤：ALL（通用禁止）/ CUSTOM（额外限制）/ ASYNC（异步 agent 更严格）。MCP 工具始终放行。

子 agent 可继承或自定义 MCP 服务器，只有内联定义的新服务器在结束时清理。

## 7. 精巧设计

### Env Var 安全剥离

Allow/Deny 规则使用不同剥离策略（HackerOne #3543050 修复）：
- Allow 规则：只剥离 SAFE_ENV_VARS（防止逃逸）
- Deny 规则：剥离所有 env var 前缀（防止绕过）

### Safe Wrapper 两阶段剥离

Phase 1 只处理 env vars 和注释，Phase 2 只处理 wrapper 命令。因为 bash 中 wrapper 后面的 `VAR=val` 是命令而非环境变量。

### cd + git 复合命令防御

检测 cd + git 组合，防止 bare git repo 攻击（通过 core.fsmonitor）。

### 子命令数量上限

`MAX_SUBCOMMANDS_FOR_SECURITY_CHECK = 50` 防止 splitCommand 的指数级增长（ReDoS）导致事件循环饥饿。

### backfillObservableInput

工具可以在 `backfillObservableInput` 中添加派生字段，保持 API-bound 输入不变（保护 prompt cache），同时允许下游消费者看到增强数据。
