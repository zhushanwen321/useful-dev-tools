# Ralph Loop & Codex /goal 深度分析报告

> 搜索日期: 2026-05-06  
> 分析范围: Ralph Loop 模式及其多个实现、OpenAI Codex CLI `/goal` 命令

---

## 一、Ralph Loop（Ralph Wiggum 循环）

### 1.1 什么是 Ralph Loop

Ralph Loop 是由 Geoffrey Huntley 提出的一种**AI 编码代理循环模式**，得名于《辛普森一家》中的 Ralph Wiggum。核心理念极其简洁：

> **"Ralph is a Bash loop." — Geoffrey Huntley**

它不是一个产品，而是一个**设计模式/方法论**：持续向 AI 代理输入任务，直到任务完成。每次迭代使用全新的上下文窗口（fresh context），通过磁盘文件（而非对话历史）在迭代间传递记忆。

### 1.2 核心设计原理

Ralph Loop 解决了 LLM 编码代理的三个稳定失败模式：

| 失败模式 | 描述 | Ralph 如何解决 |
|----------|------|---------------|
| **上下文腐烂 (Context Rot)** | 随着对话历史增长，模型精度下降 | 每次迭代创建全新实例，干净上下文 |
| **目标漂移 (Goal Drift)** | 模型开始解决与原始任务不同的问题 | 每次迭代重新读取 PRD/任务文件，重新对齐 |
| **代理信号坍缩 (Proxy-Signal Collapse)** | 模型看到测试通过就宣布完成，实际未满足需求 | 通过外部验证函数/审计逻辑确认真实完成 |

**关键洞察**：Ralph Loop 的智能在**循环本身**，而非代理。代理是可替换的（fungible），循环才是自主性的来源。

### 1.3 完整工作流程

```
┌─────────────────────────────────────────────────────────┐
│                    Ralph Loop（外层）                      │
│                                                          │
│  1. 读取 PRD/任务列表（prd.json / tasks.json）              │
│  2. 选择最高优先级的未完成任务                                │
│  3. 启动全新 AI 实例（新上下文窗口）                          │
│  4. AI 代理执行单一任务                                     │
│  5. 运行质量检查（类型检查、测试、lint）                       │
│  6. 如果检查通过 → 提交代码                                  │
│  7. 更新任务状态（passes: true）                             │
│  8. 追加学习到 progress.txt                                 │
│  9. 检查：所有任务完成？                                     │
│     ├── 是 → 输出 COMPLETE，退出循环                        │
│     └── 否 → 回到步骤 2                                    │
│                                                          │
│  安全阀：达到最大迭代次数时强制停止                             │
└─────────────────────────────────────────────────────────┘
```

### 1.4 代码级实现分析

#### 1.4.1 snarktank/ralph — 最简洁的实现

**核心脚本 `ralph.sh`**（~100行 Bash）：

```bash
#!/bin/bash
set -e

TOOL="amp"  # 或 "claude"
MAX_ITERATIONS=10

# 解析参数：--tool amp|claude, [max_iterations]

for i in $(seq 1 $MAX_ITERATIONS); do
  echo "Ralph Iteration $i of $MAX_ITERATIONS ($TOOL)"

  if [[ "$TOOL" == "amp" ]]; then
    OUTPUT=$(cat prompt.md | amp --dangerously-allow-all 2>&1 | tee /dev/stderr) || true
  else
    # Claude Code: 非交互模式 + 跳过权限
    OUTPUT=$(claude --dangerously-skip-permissions --print < CLAUDE.md 2>&1 | tee /dev/stderr) || true
  fi

  # 完成检测：在输出中搜索 COMPLETE 关键字
  if echo "$OUTPUT" | grep -q "COMPLETE"; then
    echo "Ralph completed all tasks!"
    exit 0
  fi

  sleep 2
done

echo "Ralph reached max iterations without completing all tasks."
exit 1
```

**CLAUDE.md — 代理指令模板**（每次迭代注入）：

```markdown
# Ralph Agent Instructions
You are an autonomous coding agent working on a software project.

## Your Task
1. Read the PRD at `prd.json`
2. Read the progress log at `progress.txt` (check Codebase Patterns section first)
3. Check you're on the correct branch from PRD `branchName`
4. Pick the **highest priority** user story where `passes: false`
5. Implement that single user story
6. Run quality checks (typecheck, lint, test)
7. Update CLAUDE.md files if you discover reusable patterns
8. If checks pass, commit ALL changes with message: `feat: [Story ID] - [Story Title]`
9. Update the PRD to set `passes: true` for the completed story
10. Append your progress to `progress.txt`

## Stop Condition
After completing a user story, check if ALL stories have `passes: true`.
If ALL stories are complete and passing, reply with: COMPLETE
```

**任务文件格式 `prd.json`**：

```json
{
  "branchName": "ralph/feature-auth",
  "userStories": [
    {
      "id": "STORY-001",
      "title": "Add login page",
      "priority": 1,
      "passes": false,
      "acceptanceCriteria": ["Login form renders", "Valid credentials work"]
    }
  ]
}
```

**记忆机制 `progress.txt`**（追加式日志）：

```markdown
## Codebase Patterns
- Use `sql` template for aggregations
- Always use `IF NOT EXISTS` for migrations

## 2026-05-06 - STORY-001
- What was implemented: Login page with form validation
- Files changed: src/pages/Login.tsx, src/api/auth.ts
- **Learnings for future iterations:**
- The auth API uses JWT with 15min expiry
- Don't forget to update AuthContext when changing auth flow
---
```

#### 1.4.2 PageAI-Pro/ralph-loop — 生产级实现

更完善的版本，增加了：
- **Docker 沙箱隔离**：每次迭代在容器中运行
- **实时输出监控**：使用 `script` 提供 pseudo-TTY，JSON 流解析
- **Spinner UI**：终端中显示实时进度
- **结构化日志**：每次迭代输出保存到 `.agent/history/ITERATION-*.txt`
- **退出码规范**：
  - `0` = COMPLETE — 所有任务完成
  - `1` = MAX_ITERATIONS — 达到上限
  - `2` = BLOCKED — 需要人工帮助
  - `3` = DECIDE — 需要人工决策

```bash
# 核心循环骨架
for i in $(seq 1 $MAX_ITERATIONS); do
  # 注入 PROJECT_ROOT + PROMPT.md 作为上下文
  PROMPT_CONTENT="PROJECT_ROOT=$SCRIPT_DIR\n$(cat .agent/PROMPT.md)"

  # 在 Docker 沙箱中运行代理
  AGENT_COMMAND=$(build_agent_command "$RALPH_AGENT" "$RALPH_SANDBOX_NAME")
  script -q "$OUTPUT_FILE" bash -c "$AGENT_COMMAND" &
  AGENT_PID=$!

  # 实时监控输出流
  while kill -0 "$AGENT_PID" 2>/dev/null; do
    # 增量读取新输出行
    # 解析 JSON 提取文本内容
    # 更新 spinner 和 preview
    sleep 0.2
  done

  # 保存迭代历史（SESSION_ID 防止覆盖）
  HISTORY_FILE="$HISTORY_DIR/ITERATION-${SESSION_ID}-${i}.txt"
done
```

#### 1.4.3 Vercel ralph-loop-agent — TypeScript SDK 实现

Vercel 实验室提供了一个类型化的 TypeScript 库，将 Ralph Loop 模式抽象为可编程的 SDK：

```typescript
import { RalphLoopAgent, iterationCountIs, tokenCountIs, costIs } from 'ralph-loop-agent';

const agent = new RalphLoopAgent({
  model: 'anthropic/claude-opus-4.5',
  instructions: 'You are a helpful coding assistant.',
  
  // 多层停止条件（任一满足即停）
  stopWhen: [iterationCountIs(50), tokenCountIs(100_000), costIs(5.00)],
  
  // 外部验证函数 — 核心创新
  verifyCompletion: async ({ result, iteration, allResults, originalPrompt }) => {
    const checks = await Promise.all([
      fileExists('vitest.config.ts'),
      !await fileExists('jest.config.js'),
      noFilesMatch('**/*.test.ts', /from ['"]@jest/),
    ]);
    
    return { 
      complete: checks.every(Boolean),
      reason: checks.every(Boolean) 
        ? 'Migration complete' 
        : 'Structural checks failed'  // ← 注入到下一次迭代
    };
  },
});

const result = await agent.loop({ prompt: 'Migrate all Jest tests to Vitest.' });
// result.completionReason: 'verified' | 'max-iterations' | 'aborted'
```

**关键设计**：
- **内层循环**：AI SDK 的 tool loop（LLM ↔ tools ↔ LLM ...）
- **外层循环**：Ralph 的迭代循环（agent runs → verifyCompletion → feedback → rerun）
- `verifyCompletion` 返回的 `reason` 会被注入到下一次迭代中，形成反馈闭环

### 1.5 Ralph Loop 如何检测"任务完成"

| 实现方式 | 机制 | 优缺点 |
|----------|------|--------|
| **信号字检测** | 输出中 grep "COMPLETE" | 简单可靠，但依赖代理诚实输出 |
| **任务状态文件** | 检查 prd.json 中所有 `passes: true` | 结构化、可审计，但代理可能错误标记 |
| **外部验证函数** | `verifyCompletion()` 运行实际检查 | 最可靠，可编程验证真实完成状态 |
| **DONE/BLOCKED 文件** | 代理写入特殊文件 | 简单，但文件可能残留 |

### 1.6 Ralph Loop 如何防止无限循环

```
┌──────────────────────────────────────────┐
│          多层防无限循环机制                  │
├──────────────────────────────────────────┤
│ 1. 硬性迭代上限（MAX_ITERATIONS）           │
│    默认 10 次，可配置                       │
│                                          │
│ 2. Token 预算限制                          │
│    tokenCountIs(100_000) 等               │
│                                          │
│ 3. 成本上限                                │
│    costIs(5.00) — 达到 $5 自动停止         │
│                                          │
│ 4. 阻塞检测                                │
│    代理写入 BLOCKED 文件 → 退出码 2        │
│                                          │
│ 5. 质量门禁                                │
│    测试/lint 不通过 → 不提交 → 不标记完成   │
│                                          │
│ 6. 人工中断                                │
│    Ctrl+C 随时终止                         │
└──────────────────────────────────────────┘
```

---

## 二、Codex CLI `/goal` 命令

### 2.1 概述

Codex CLI 0.128.0（2026年4月30日发布）内置了 OpenAI 版本的 Ralph Loop。Greg Brockman 在 X 上总结：**"codex now has a built in Ralph loop++"**。

它将 bash 脚本时代的外层循环、DONE/BLOCKED 文件约定、token 预算防护全部内化到 Codex 运行时中。

### 2.2 启用方式

```toml
# ~/.codex/config.toml
[features]
goals = true
```

> ⚠️ 0.128.0 中 `/goal` 是 feature flag 门控的。不设置此标志，`/goal` 命令甚至不会被识别。

### 2.3 完整工作流程

```
用户输入: /goal <objective>
         ↓
┌──────────────────────────────────────────────────────┐
│  Codex /goal 运行时                                    │
│                                                       │
│  1. 创建持久化 Goal 对象                                │
│     - objective: 用户目标文本                            │
│     - status: pursuing                                │
│     - token_budget: 配置的预算                          │
│                                                       │
│  2. 进入代理循环                                        │
│     ┌──────────────────────────────────┐              │
│     │  a. 运行模型推理                   │              │
│     │  b. 执行工具调用                   │              │
│     │  c. 模型调用 update_goal 工具      │              │
│     │     更新状态                       │              │
│     │  d. 如果 status != achieved:       │              │
│     │     → 注入 continuation.md         │              │
│     │     → 继续下一轮                   │              │
│     │  e. 如果 status == achieved:       │              │
│     │     → 循环结束                     │              │
│     └──────────────────────────────────┘              │
│                                                       │
│  3. 预算检查（每轮）                                    │
│     如果 token 使用接近预算:                             │
│     → 注入 budget_limit.md                             │
│     → 代理执行收尾工作                                  │
│     → status 变为 budget-limited                       │
│                                                       │
│  4. 输出最终结果                                        │
│     - achieved: 目标达成                                │
│     - budget-limited: 预算耗尽                          │
│     - unmet: 无法完成                                   │
└──────────────────────────────────────────────────────┘
```

### 2.4 四个子命令

| 命令 | 功能 | 使用场景 |
|------|------|---------|
| `/goal <objective>` | 设置新目标并开始追求 | 开始一个长期任务 |
| `/goal pause` | 暂停当前目标 | 想手动检查或介入 |
| `/goal resume` | 恢复暂停的目标 | "继续做" |
| `/goal clear` | 删除当前目标 | 目标不再需要 |

### 2.5 五种生命周期状态

```
                    ┌───────────┐
                    │ pursuing  │ ← /goal 设置后的默认状态
                    │ (追求中)   │
                    └─────┬─────┘
                          │
              ┌───────────┼───────────┐
              │           │           │
              ▼           ▼           ▼
        ┌──────────┐ ┌────────┐ ┌──────────┐
        │ achieved │ │ unmet  │ │ budget-  │
        │ (达成)   │ │(未达成)│ │ limited  │
        └──────────┘ └────────┘ │(预算耗尽)│
                                 └──────────┘
        ┌──────────┐
        │  paused  │ ← /goal pause
        │ (暂停)   │ → /goal resume → 回到 pursuing
        └──────────┘
```

### 2.6 两个核心 Prompt（代码级细节）

`/goal` 的智能主要来自两个自动注入的 prompt 文件：

#### `continuation.md` — 持续循环驱动

在每个 turn 结束时，如果目标未达成且预算充足，自动注入此 prompt。核心逻辑：

1. **重建审计清单**：从**原始目标**（非当前实现）构建检查项
2. **逐项直接验证**：不依赖代理信号（如"测试通过"），而是直接检查每个交付物
3. **禁止代理信号**：明确告诉代理"不要因为测试通过就宣布完成"
4. **调用 update_goal**：只有所有审计项通过后才标记 `achieved`

这个 prompt 的关键设计是**反代理信号坍缩**：它要求代理从需求而非实现出发验证完成度。

#### `budget_limit.md` — 预算限制处理

当 token 使用接近预算时注入：

1. 告知代理剩余 token 预算有限
2. 要求代理执行收尾操作（总结进度、提交当前工作）
3. 通过 `update_goal` 将状态标记为 `budget-limited`
4. 不允许代理假装任务完成

### 2.7 `update_goal` 模型工具

这是一个**结构化工具调用**（不是纯文本输出），代理用它来更新目标状态：

```typescript
// 概念性伪代码
update_goal({
  status: "pursuing" | "achieved" | "unmet" | "budget-limited",
  progress_notes: "已完成数据库迁移，正在处理 API 层...",
  remaining_items: ["更新前端组件", "添加集成测试"]
})
```

运行时解析这个工具调用，决定是否继续循环。

### 2.8 任务完成检测机制

```
┌─────────────────────────────────────────────────┐
│  Codex /goal 的三层完成检测                       │
├─────────────────────────────────────────────────┤
│                                                 │
│  第1层: 模型自主判断                              │
│  - 模型基于 continuation.md 的审计清单验证       │
│  - 调用 update_goal(status: "achieved")         │
│                                                 │
│  第2层: 预算约束                                  │
│  - token 使用接近预算 → 注入 budget_limit.md     │
│  - 强制收尾，status 变为 budget-limited           │
│                                                 │
│  第3层: 无进展检测                                │
│  - 如果连续的 continuation turns 没有工具调用     │
│  - 系统抑制重复继续（代理陷入空转）               │
│                                                 │
│  用户层: 人工覆盖                                │
│  - Ctrl+C 暂停目标                               │
│  - /goal pause/resume/clear                     │
│  - 用户新消息优先于自动继续                       │
└─────────────────────────────────────────────────┘
```

### 2.9 防止无限循环

| 机制 | 实现方式 |
|------|---------|
| **Token 预算** | 配置的预算上限，超限自动触发 `budget_limit.md` |
| **无进展检测** | 连续 continuation turns 无工具调用时抑制 |
| **用户优先级** | 用户输入总是优先于自动继续 |
| **Pause 机制** | 任意时刻可暂停 |
| **Compact 安全** | 已知问题：mid-turn compaction 可能丢失 goal 上下文（issue #19910） |

---

## 三、对比分析

### 3.1 架构对比

| 维度 | Ralph Loop (Bash) | Vercel ralph-loop-agent | Codex /goal |
|------|-------------------|------------------------|-------------|
| **实现语言** | Bash 脚本 | TypeScript | 内置于 Codex 运行时 |
| **循环位置** | 外层 bash for 循环 | 外层 JS while 循环 | 运行时内部 continuation |
| **上下文管理** | 每次迭代全新进程 | 每次迭代全新 generateText | 同一会话内，compaction 管理 |
| **记忆持久化** | 文件（prd.json, progress.txt, git） | verifyCompletion 函数返回值 | Goal 对象 + app-server 状态 |
| **完成验证** | 代理自报 COMPLETE + 文件状态 | 外部 verifyCompletion 函数 | 模型工具 update_goal + continuation.md 审计 |
| **预算控制** | MAX_ITERATIONS | iteration/token/cost 三种条件 | Token 预算 + budget_limit.md |

### 3.2 设计哲学对比

| 维度 | Ralph Loop | Codex /goal |
|------|-----------|-------------|
| **核心理念** | 智能在循环，不在代理 | 智能在运行时 + prompt 工程 |
| **上下文策略** | 每次完全重建（激进遗忘） | 会话内持续（依赖 compaction） |
| **验证策略** | 文件状态 + 外部函数 | Prompt 驱动的审计清单 |
| **可组合性** | 高（bash 可组合一切） | 中（限于 Codex 生态） |
| **可审计性** | 高（所有状态在文件中） | 中（Goal 对象通过 API 查询） |

---

## 四、值得借鉴的设计模式

### 4.1 Fresh Context Pattern（新鲜上下文模式）

**问题**：长对话中 LLM 精度下降、上下文腐烂。
**解法**：每次迭代使用全新上下文窗口，只注入必要信息。
**适用场景**：任何需要多轮自动化的 LLM 任务。

```python
# 伪代码
for task in task_list:
    context = build_fresh_context(task, progress_file, codebase_state)
    result = llm.run(context)  # 全新对话
    save_progress(result, progress_file)
    if verify_complete(task):
        mark_done(task)
```

### 4.2 File-as-Memory Pattern（文件即记忆模式）

**问题**：LLM 无持久记忆，对话历史会膨胀。
**解法**：用文件系统作为跨迭代的唯一真实来源。

关键文件：
- `prd.json` / `tasks.json` — 任务状态（可 grep、可 diff、可审计）
- `progress.txt` — 追加式学习日志
- `AGENTS.md` / `CLAUDE.md` — 累积的项目知识
- `git history` — 代码变更历史

### 4.3 External Verification Pattern（外部验证模式）

**问题**：LLM 容易"自认为完成"（代理信号坍缩）。
**解法**：由外部函数/系统验证完成状态，不信任代理的自我报告。

```typescript
// Vercel ralph-loop-agent 的实现
verifyCompletion: async ({ result }) => {
  // 不看代理说了什么，看实际文件状态
  const vitestExists = await fileExists('vitest.config.ts');
  const jestGone = !await fileExists('jest.config.js');
  return { complete: vitestExists && jestGone };
}
```

### 4.4 Multi-Layer Safety Valve Pattern（多层安全阀模式）

**问题**：单一防护不够可靠。
**解法**：多层独立的安全机制叠加。

```
Layer 1: 迭代次数上限（硬性停止）
Layer 2: Token/成本预算（资源保护）
Layer 3: 质量门禁（不通过不提交）
Layer 4: 阻塞检测（需要人工时主动停止）
Layer 5: 人工中断（随时 Ctrl+C）
```

### 4.5 Feedback Injection Pattern（反馈注入模式）

**问题**：每次迭代是全新上下文，不知道之前为什么失败。
**解法**：将验证失败的原因注入到下一次迭代的 prompt 中。

```typescript
verifyCompletion: async ({ result }) => ({
  complete: false,
  reason: "vitest.config.ts still missing, jest imports still present"  
  // ← 这个 reason 会被注入到下一次迭代
})
```

### 4.6 Anti-Proxy-Signal Pattern（反代理信号模式）

**问题**：代理看到"测试通过"就宣布完成，但实际需求未满足。
**解法**：continuation.md 明确要求代理从原始目标（非当前实现）构建审计清单。

```
错误方式: "检查测试是否通过" → 代理可能修改测试让它通过
正确方式: "从原始需求列出交付物，逐一验证每个交付物存在且正确"
```

---

## 五、实际使用建议

### 5.1 何时用 Ralph Loop（Bash 版本）

- 需要完全控制和可审计性
- 使用多种 AI 工具（Claude Code、Amp、Codex）
- 任务可以被分解为独立的小步骤
- 需要自定义完成验证逻辑

### 5.2 何时用 Codex `/goal`

- 已在 Codex 生态中
- 目标是单一、可明确验证的任务
- 需要内置的预算管理
- 不想维护 bash 脚本

### 5.3 关键最佳实践

1. **任务粒度**：每个任务应该在一次上下文窗口内可完成
2. **AGENTS.md**：这是最高杠杆的投资——累积项目知识
3. **质量门禁**：必须有 typecheck + test + lint，否则错误会跨迭代累积
4. **观察循环**：定期观察迭代输出，发现失败域后用工程手段解决
5. **预算设置**：始终设置预算上限，防止意外超支

---

## 六、信息来源

| 来源 | URL |
|------|-----|
| snarktank/ralph | https://github.com/snarktank/ralph |
| PageAI-Pro/ralph-loop | https://github.com/PageAI-Pro/ralph-loop |
| vercel-labs/ralph-loop-agent | https://github.com/vercel-labs/ralph-loop-agent |
| ghuntley/how-to-ralph-wiggum | https://github.com/ghuntley/how-to-ralph-wiggum |
| Geoffrey Huntley 原文 | https://ghuntley.com/loop/ |
| Codex /goal 深度分析 | https://ralphable.com/blog/codex-goal-command-ralph-loop-openai-built-in-autonomous-coding-agent-2026 |
| Codex issue #20536 | https://github.com/openai/codex/issues/20536 |
| Simon Willison 笔记 | https://simonwillison.net/2026/Apr/30/codex-goals/ |
| Codex agent loop 博文 | https://openai.com/index/unrolling-the-codex-agent-loop/ |
| Matt Pocock 入门指南 | https://www.aihero.dev/getting-started-with-ralph |
| LinearB 分析 | https://linearb.io/blog/ralph-loop-agentic-engineering-geoffrey-huntley |
