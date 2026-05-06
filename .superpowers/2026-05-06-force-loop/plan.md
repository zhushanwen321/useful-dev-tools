# Force-Loop Extension 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现 Pi 扩展，通过 `/loop` 命令强制 LLM 完成所有任务后才能停止，否则自动追问继续。

**Architecture:** 单文件 TypeScript 扩展 (`~/.pi/agent/extensions/force-loop/index.ts`)，通过 Pi Extension API 注册工具、命令和事件处理。状态通过 `appendEntry` 持久化到 session，`session_start` 时恢复。

**Tech Stack:** TypeScript, Pi Extension API (`ExtensionAPI`), TypeBox (schema), `@mariozechner/pi-tui` (渲染)

---

## 文件结构

| 文件 | 职责 |
|------|------|
| `~/.pi/agent/extensions/force-loop/index.ts` | 唯一文件：状态管理、工具注册、命令注册、事件处理、Widget 渲染 |

---

### Task 1: 骨架 — 状态类型与工厂函数

**Files:**
- Create: `~/.pi/agent/extensions/force-loop/index.ts`

- [ ] **Step 1: 创建文件，定义状态接口和默认状态**

```typescript
import { StringEnum } from "@mariozechner/pi-ai";
import type { ExtensionAPI, ExtensionContext } from "@mariozechner/pi-coding-agent";
import { Text } from "@mariozechner/pi-tui";
import { Type } from "typebox";

// ── State ──────────────────────────────────────────────

interface LoopTask {
	id: number;
	description: string;
	completed: boolean;
}

interface LoopState {
	isActive: boolean;
	isPaused: boolean;
	tasks: LoopTask[];
	loopCount: number;
	maxLoops: number;
	stallCount: number;
	originalPrompt: string;
}

interface LoopTaskDetails {
	action: "create_tasks" | "complete_task" | "list_tasks";
	tasks: LoopTask[];
	nextId: number;
}

const DEFAULT_STATE: LoopState = {
	isActive: false,
	isPaused: false,
	tasks: [],
	loopCount: 0,
	maxLoops: 10,
	stallCount: 0,
	originalPrompt: "",
};

// ── Extension Factory ──────────────────────────────────

export default function forceLoopExtension(pi: ExtensionAPI) {
	const state: LoopState = { ...DEFAULT_STATE };
	let tasksCompletedAtTurnStart = 0;

	// Subsequent tasks will fill in:
	// - Tool schema & registration
	// - Commands
	// - Event handlers
	// - Widget rendering
}
```

- [ ] **Step 2: 验证文件能被 Pi 加载**

Run: `pi -e ~/.pi/agent/extensions/force-loop/index.ts --help 2>&1 | head -5`
Expected: 无报错（正常显示 pi help 或启动信息）

- [ ] **Step 3: Commit**

```bash
mkdir -p ~/.pi/agent/extensions/force-loop
git add -A && git commit -m "feat(force-loop): scaffold extension with state types"
```

---

### Task 2: 工具注册 — loop_task_tracker

**Files:**
- Modify: `~/.pi/agent/extensions/force-loop/index.ts`

- [ ] **Step 1: 在工厂函数内添加工具 schema 和注册**

在 `forceLoopExtension` 函数体内，紧接 `tasksCompletedAtTurnStart` 之后添加：

```typescript
	// ── Tool: loop_task_tracker ─────────────────────────

	const LoopTaskParams = Type.Object({
		action: StringEnum(["create_tasks", "complete_task", "list_tasks"] as const),
		tasks: Type.Optional(Type.Array(Type.String(), { description: "Task descriptions for create_tasks" })),
		taskId: Type.Optional(Type.Number({ description: "Task ID for complete_task" })),
	});

	pi.registerTool({
		name: "loop_task_tracker",
		label: "Loop Task Tracker",
		description:
			"管理 /loop 模式的任务清单。必须在开始工作前调用 create_tasks 拆分任务，每完成一个任务调用 complete_task 标记。" +
			"使用 list_tasks 查看当前进度。只在 /loop 模式激活时可用。",
		promptSnippet: "创建、完成、查看任务清单，用于跟踪 /loop 命令的多步骤任务进度",
		promptGuidelines: [
			"使用 loop_task_tracker 的 create_tasks 在开始工作前拆分任务清单",
			"完成每个任务后必须调用 loop_task_tracker 的 complete_task 标记，不要遗漏",
			"使用 loop_task_tracker 的 list_tasks 查看当前进度和剩余任务",
		],
		parameters: LoopTaskParams,

		async execute(_toolCallId, params, _signal, _onUpdate, _ctx) {
			switch (params.action) {
				case "create_tasks": {
					if (!params.tasks || params.tasks.length === 0) {
						throw new Error("create_tasks requires a non-empty tasks array");
					}
					state.tasks = params.tasks.map((desc, i) => ({
						id: i + 1,
						description: desc,
						completed: false,
					}));
					return {
						content: [
							{
								type: "text",
								text: `已创建 ${state.tasks.length} 个任务：\n${state.tasks
									.map((t) => `  #${t.id}: ${t.description}`)
									.join("\n")}`,
							},
						],
						details: {
							action: "create_tasks",
							tasks: [...state.tasks],
							nextId: state.tasks.length + 1,
						} satisfies LoopTaskDetails,
					};
				}

				case "complete_task": {
					if (params.taskId === undefined) {
						throw new Error("complete_task requires taskId");
					}
					const task = state.tasks.find((t) => t.id === params.taskId);
					if (!task) {
						throw new Error(`Task #${params.taskId} not found`);
					}
					task.completed = true;
					return {
						content: [
							{
								type: "text",
								text: `已完成任务 #${task.id}: ${task.description}`,
							},
						],
						details: {
							action: "complete_task",
							tasks: [...state.tasks],
							nextId: state.tasks.length + 1,
						} satisfies LoopTaskDetails,
					};
				}

				case "list_tasks": {
					const completed = state.tasks.filter((t) => t.completed);
					const incomplete = state.tasks.filter((t) => !t.completed);
					const lines: string[] = [];
					if (incomplete.length > 0) {
						lines.push(`未完成 (${incomplete.length}):`);
						incomplete.forEach((t) => lines.push(`  ☐ #${t.id}: ${t.description}`));
					}
					if (completed.length > 0) {
						lines.push(`已完成 (${completed.length}):`);
						completed.forEach((t) => lines.push(`  ✓ #${t.id}: ${t.description}`));
					}
					if (state.tasks.length === 0) {
						lines.push("暂无任务。请先调用 create_tasks 创建任务清单。");
					}
					return {
						content: [{ type: "text", text: lines.join("\n") }],
						details: {
							action: "list_tasks",
							tasks: [...state.tasks],
							nextId: state.tasks.length + 1,
						} satisfies LoopTaskDetails,
					};
				}

				default:
					throw new Error(`Unknown action: ${params.action}`);
			}
		},

		renderCall(args, theme) {
			let text = theme.fg("toolTitle", theme.bold("loop_task_tracker ")) + theme.fg("muted", args.action);
			if (args.tasks) text += ` ${theme.fg("dim", `(${args.tasks.length} tasks)`)}`;
			if (args.taskId !== undefined) text += ` ${theme.fg("accent", `#${args.taskId}`)}`;
			return new Text(text, 0, 0);
		},

		renderResult(result, { expanded }, theme) {
			const details = result.details as LoopTaskDetails | undefined;
			if (!details) {
				const text = result.content[0];
				return new Text(text?.type === "text" ? text.text : "", 0, 0);
			}
			const tasks = details.tasks;
			const completed = tasks.filter((t) => t.completed).length;
			const summary = theme.fg("success", `✓ ${completed}/${tasks.length} 完成`);
			if (!expanded || tasks.length === 0) {
				return new Text(summary, 0, 0);
			}
			const lines = [summary];
			for (const t of tasks) {
				const icon = t.completed ? theme.fg("success", "✓") : theme.fg("dim", "☐");
				const desc = t.completed ? theme.fg("dim", t.description) : theme.fg("text", t.description);
				lines.push(`  ${icon} ${theme.fg("accent", `#${t.id}`)} ${desc}`);
			}
			return new Text(lines.join("\n"), 0, 0);
		},
	});
```

- [ ] **Step 2: 验证工具注册成功**

Run: `pi -e ~/.pi/agent/extensions/force-loop/index.ts --help 2>&1 | head -5`
Expected: 无报错

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat(force-loop): register loop_task_tracker tool with create/complete/list actions"
```

---

### Task 3: 辅助函数 — 状态持久化与恢复、Widget

**Files:**
- Modify: `~/.pi/agent/extensions/force-loop/index.ts`

- [ ] **Step 1: 在工厂函数内（工具注册之后）添加辅助函数**

```typescript
	// ── Helpers ──────────────────────────────────────────

	function persistState(): void {
		pi.appendEntry("force-loop", {
			isActive: state.isActive,
			isPaused: state.isPaused,
			tasks: state.tasks,
			loopCount: state.loopCount,
			maxLoops: state.maxLoops,
			stallCount: state.stallCount,
			originalPrompt: state.originalPrompt,
		});
	}

	function reconstructState(ctx: ExtensionContext): void {
		// Reset to defaults
		Object.assign(state, { ...DEFAULT_STATE });

		const entries = ctx.sessionManager.getEntries();

		// 1. Restore from custom entries
		for (let i = entries.length - 1; i >= 0; i--) {
			const entry = entries[i];
			if (
				entry.type === "custom" &&
				"customType" in entry &&
				(entry as any).customType === "force-loop"
			) {
				const data = (entry as any).data as LoopState | undefined;
				if (data) {
					state.isActive = data.isActive ?? false;
					state.isPaused = data.isPaused ?? false;
					state.tasks = data.tasks ?? [];
					state.loopCount = data.loopCount ?? 0;
					state.maxLoops = data.maxLoops ?? 10;
					state.stallCount = data.stallCount ?? 0;
					state.originalPrompt = data.originalPrompt ?? "";
				}
				break; // Use the latest entry
			}
		}

		// 2. Override tasks from tool results (most recent wins)
		for (let i = entries.length - 1; i >= 0; i--) {
			const entry = entries[i];
			if (
				entry.type === "message" &&
				"message" in entry &&
				(entry.message as any).role === "toolResult" &&
				(entry.message as any).toolName === "loop_task_tracker"
			) {
				const details = (entry.message as any).details as LoopTaskDetails | undefined;
				if (details?.tasks) {
					state.tasks = details.tasks;
				}
			}
		}
	}

	function updateWidget(ctx: ExtensionContext): void {
		if (!state.isActive) {
			ctx.ui.setWidget("force-loop", undefined);
			ctx.ui.setStatus("force-loop", undefined);
			return;
		}

		const completed = state.tasks.filter((t) => t.completed).length;
		const total = state.tasks.length;
		const th = ctx.ui.theme;

		// Status bar
		let statusText = th.fg("accent", `🔄 ${state.loopCount}/${state.maxLoops} 轮`);
		if (total > 0) {
			statusText += th.fg("muted", ` | ${completed}/${total} 任务`);
		}
		if (state.stallCount > 0) {
			statusText += th.fg("warning", ` | ⚠ ${state.stallCount}轮无进展`);
		}
		if (state.isPaused) {
			statusText += th.fg("warning", " | ⏸ 暂停");
		}
		ctx.ui.setStatus("force-loop", statusText);

		// Widget
		if (total === 0) {
			ctx.ui.setWidget("force-loop", [
				th.fg("accent", "🔄 Loop 模式已激活 — 等待任务清单创建"),
			]);
			return;
		}

		const lines: string[] = [];
		const incomplete = state.tasks.filter((t) => !t.completed);
		const header =
			`🔄 ${state.loopCount}/${state.maxLoops} 轮 | ✓ ${completed}/${total} 任务` +
			(state.stallCount > 0 ? ` | ⚠ ${state.stallCount}轮无进展` : "") +
			(state.isPaused ? " | ⏸ 暂停" : "");
		lines.push(header);
		for (const t of state.tasks) {
			const icon = t.completed ? th.fg("success", "✓") : th.fg("dim", "☐");
			const desc = t.completed ? th.fg("dim", t.description) : th.fg("text", t.description);
			lines.push(`${icon} ${th.fg("accent", `#${t.id}`)} ${desc}`);
		}
		ctx.ui.setWidget("force-loop", lines);
	}
```

- [ ] **Step 2: Commit**

```bash
git add -A && git commit -m "feat(force-loop): add state persistence, reconstruction, and widget helpers"
```

---

### Task 4: 命令注册 — /loop, /loop pause, /loop resume, /loop status

**Files:**
- Modify: `~/.pi/agent/extensions/force-loop/index.ts`

- [ ] **Step 1: 在工厂函数内添加命令解析和注册**

```typescript
	// ── Command Parsing ──────────────────────────────────

	function parseLoopArgs(raw: string): { prompt: string; maxLoops: number } {
		let maxLoops = 10;
		let remaining = raw.trim();

		const maxMatch = remaining.match(/--max\s+(\d+)/);
		if (maxMatch) {
			maxLoops = Math.max(1, parseInt(maxMatch[1]!, 10));
			remaining = remaining.replace(/--max\s+\d+/, "").trim();
		}

		return { prompt: remaining, maxLoops };
	}

	// ── Commands ─────────────────────────────────────────

	pi.registerCommand("loop", {
		description: "强制循环模式：/loop <prompt> [--max N] | /loop pause | /loop resume | /loop status",

		handler: async (args, ctx) => {
			const trimmed = args.trim().toLowerCase();

			// Sub-command: pause
			if (trimmed === "pause") {
				if (!state.isActive) {
					ctx.ui.notify("Loop 模式未激活", "warning");
					return;
				}
				state.isPaused = true;
				persistState();
				updateWidget(ctx);
				ctx.ui.notify("Loop 已暂停。使用 /loop resume 恢复。", "info");
				return;
			}

			// Sub-command: resume
			if (trimmed === "resume") {
				if (!state.isActive) {
					ctx.ui.notify("Loop 模式未激活", "warning");
					return;
				}
				if (!state.isPaused) {
					ctx.ui.notify("Loop 未暂停，无需恢复", "info");
					return;
				}
				state.isPaused = false;
				state.stallCount = 0;
				persistState();
				updateWidget(ctx);

				const incomplete = state.tasks.filter((t) => !t.completed);
				if (incomplete.length > 0) {
					pi.sendUserMessage(
						`Loop 已恢复。继续执行剩余 ${incomplete.length} 个任务。` +
							`每完成一个任务务必调用 loop_task_tracker 的 complete_task 标记。` +
							`\n\n回到原始目标验证：${state.originalPrompt}`
					);
				} else {
					ctx.ui.notify("所有任务已完成，无需恢复", "info");
					state.isActive = false;
					persistState();
					updateWidget(ctx);
				}
				return;
			}

			// Sub-command: status
			if (trimmed === "status") {
				if (!state.isActive) {
					ctx.ui.notify("Loop 模式未激活", "info");
					return;
				}
				const completed = state.tasks.filter((t) => t.completed).length;
				const total = state.tasks.length;
				const lines: string[] = [
					`状态: ${state.isPaused ? "⏸ 暂停" : "🔄 活跃"}`,
					`循环: ${state.loopCount}/${state.maxLoops}`,
					`任务: ${completed}/${total} 完成`,
					`无进展轮数: ${state.stallCount}`,
					`原始目标: ${state.originalPrompt}`,
				];
				ctx.ui.notify(lines.join("\n"), "info");
				return;
			}

			// Main: /loop <prompt>
			if (!args.trim()) {
				ctx.ui.notify("用法: /loop <prompt> [--max N] | /loop pause | /loop resume | /loop status", "warning");
				return;
			}

			const { prompt, maxLoops } = parseLoopArgs(args);

			// Reset state
			state.isActive = true;
			state.isPaused = false;
			state.tasks = [];
			state.loopCount = 0;
			state.maxLoops = maxLoops;
			state.stallCount = 0;
			state.originalPrompt = prompt;
			tasksCompletedAtTurnStart = 0;

			persistState();
			updateWidget(ctx);
			ctx.ui.notify(`Loop 模式已启动 (最大 ${maxLoops} 轮)`, "info");

			// Send the prompt as a user message to trigger the agent
			pi.sendUserMessage(prompt);
		},
	});
```

- [ ] **Step 2: Commit**

```bash
git add -A && git commit -m "feat(force-loop): register /loop command with pause/resume/status sub-commands"
```

---

### Task 5: 事件处理 — before_agent_start 系统指令注入

**Files:**
- Modify: `~/.pi/agent/extensions/force-loop/index.ts`

- [ ] **Step 1: 添加 before_agent_start 事件处理器**

```typescript
	// ── Events ───────────────────────────────────────────

	pi.on("before_agent_start", async (_event, ctx) => {
		if (!state.isActive || state.isPaused) return;

		// Context budget check (L3)
		const usage = ctx.getContextUsage();
		if (usage && usage.maxTokens > 0 && usage.tokens / usage.maxTokens > 0.8) {
			state.isPaused = true;
			persistState();
			updateWidget(ctx);

			return {
				message: {
					customType: "force-loop-budget",
					content:
						"[FORCE-LOOP — 上下文空间不足，必须立即收尾]\n" +
						"1. 用 loop_task_tracker 的 list_tasks 查看剩余任务\n" +
						"2. 只标记你真正完成的任务\n" +
						"3. 总结当前进度和剩余工作\n" +
						"不要再开始新任务。",
					display: false,
				},
			};
		}

		// Normal injection
		return {
			message: {
				customType: "force-loop-context",
				content:
					`[FORCE-LOOP ACTIVE — 你必须严格遵守以下规则]\n\n` +
					`1. 你的第一个操作必须是调用 loop_task_tracker 的 create_tasks，将任务拆分为可验证的具体步骤。\n` +
					`   每个任务必须具体到"修改/创建哪个文件的哪个部分"，禁止模糊描述。\n\n` +
					`2. 每完成一个任务，必须立即调用 loop_task_tracker 的 complete_task 标记。\n\n` +
					`3. 在标记所有任务完成前，不要说"完成"或"搞定"。\n\n` +
					`4. 原始目标：${state.originalPrompt}\n` +
					`   完成判断必须回到这个原始目标，逐项验证交付物是否存在且正确。\n\n` +
					`5. 如果遇到无法解决的问题，调用 loop_task_tracker 的 list_tasks 列出状态，\n` +
					`   并说明哪些任务被阻塞及原因。`,
				display: false,
			},
		};
	});
```

- [ ] **Step 2: Commit**

```bash
git add -A && git commit -m "feat(force-loop): add before_agent_start event with system prompt injection and budget check"
```

---

### Task 6: 事件处理 — turn_start/turn_end 进度追踪

**Files:**
- Modify: `~/.pi/agent/extensions/force-loop/index.ts`

- [ ] **Step 1: 添加 turn_start 和 turn_end 事件处理器**

```typescript
	pi.on("turn_start", async () => {
		if (!state.isActive) return;
		tasksCompletedAtTurnStart = state.tasks.filter((t) => t.completed).length;
	});

	pi.on("turn_end", async (_event, ctx) => {
		if (!state.isActive) return;
		// Just update the widget to reflect any task completions this turn
		updateWidget(ctx);
	});
```

- [ ] **Step 2: Commit**

```bash
git add -A && git commit -m "feat(force-loop): add turn_start/turn_end for progress tracking"
```

---

### Task 7: 事件处理 — agent_end 核心循环逻辑

**Files:**
- Modify: `~/.pi/agent/extensions/force-loop/index.ts`

- [ ] **Step 1: 添加 agent_end 事件处理器（核心循环驱动）**

```typescript
	pi.on("agent_end", async (_event, ctx) => {
		if (!state.isActive || state.isPaused) return;

		const incomplete = state.tasks.filter((t) => !t.completed);
		const completed = state.tasks.filter((t) => t.completed);
		const currentCompleted = completed.length;
		const progressThisRound = currentCompleted - tasksCompletedAtTurnStart;

		// L5: All tasks completed
		if (state.tasks.length > 0 && incomplete.length === 0) {
			state.isActive = false;
			persistState();
			updateWidget(ctx);
			ctx.ui.notify(
				`所有任务已完成 ✓ (${completed.length}/${state.tasks.length})`,
				"info"
			);
			return;
		}

		// No tasks created yet — LLM might have ignored the instruction
		if (state.tasks.length === 0) {
			state.loopCount++;
			if (state.loopCount >= state.maxLoops) {
				// L1: Max loops reached
				state.isActive = false;
				persistState();
				updateWidget(ctx);
				ctx.ui.notify(
					`已达最大循环次数 (${state.maxLoops})，LLM 未创建任务清单。请手动接管。`,
					"warning"
				);
				return;
			}
			// Remind to create tasks
			pi.sendUserMessage(
				"你尚未创建任务清单。请立即调用 loop_task_tracker 的 create_tasks " +
					"将工作拆分为具体可验证的任务步骤。\n\n" +
					`原始目标：${state.originalPrompt}`
			);
			persistState();
			updateWidget(ctx);
			return;
		}

		// L1: Max loops reached
		if (state.loopCount >= state.maxLoops) {
			state.isActive = false;
			persistState();
			updateWidget(ctx);
			ctx.ui.notify(
				`已达最大循环次数 (${state.maxLoops})，还有 ${incomplete.length} 个任务未完成。请手动接管。`,
				"warning"
			);
			return;
		}

		// L2: Stall detection
		if (progressThisRound === 0) {
			state.stallCount++;
		} else {
			state.stallCount = 0;
		}

		if (state.stallCount >= 3) {
			state.isActive = false;
			persistState();
			updateWidget(ctx);
			ctx.ui.notify(
				`连续 ${state.stallCount} 轮无进展，自动停止。还有 ${incomplete.length} 个任务未完成。`,
				"warning"
			);
			return;
		}

		// Normal: continue loop
		state.loopCount++;

		// Build reminder message with feedback injection
		const incompleteList = incomplete.map((t) => `☐ #${t.id}: ${t.description}`).join("\n");
		const completedSummary =
			completed.length > 0
				? `\n\n已完成: ${completed.map((t) => `✓ #${t.id}`).join(", ")}`
				: "";
		const stallWarning =
			state.stallCount > 0
				? `\n\n⚠ 注意：已连续 ${state.stallCount} 轮没有进展。请专注于完成当前任务。`
				: "";

		pi.sendUserMessage(
			`你还有 ${incomplete.length} 个任务未完成：\n\n${incompleteList}` +
				`${completedSummary}` +
				`\n\n本轮完成进度: ${progressThisRound} 个任务` +
				`${stallWarning}` +
				`\n\n请继续执行未完成的任务。每完成一个任务务必调用 loop_task_tracker 的 complete_task 标记。` +
				`\n\n回到原始目标验证：${state.originalPrompt}`
		);

		persistState();
		updateWidget(ctx);
	});
```

- [ ] **Step 2: Commit**

```bash
git add -A && git commit -m "feat(force-loop): add agent_end with 5-layer safety valve and feedback injection"
```

---

### Task 8: 事件处理 — session_start 状态恢复

**Files:**
- Modify: `~/.pi/agent/extensions/force-loop/index.ts`

- [ ] **Step 1: 添加 session_start 和 session_shutdown 事件处理器**

```typescript
	pi.on("session_start", async (_event, ctx) => {
		reconstructState(ctx);
		updateWidget(ctx);
	});

	pi.on("session_shutdown", async () => {
		// Clean up on shutdown (state is already persisted in session)
	});
```

- [ ] **Step 2: Commit**

```bash
git add -A && git commit -m "feat(force-loop): add session_start state restoration and shutdown handler"
```

---

### Task 9: 消息渲染器注册

**Files:**
- Modify: `~/.pi/agent/extensions/force-loop/index.ts`

- [ ] **Step 1: 注册 force-loop 消息类型的渲染器**

在工厂函数末尾添加：

```typescript
	// ── Message Renderers ────────────────────────────────

	const loopMessageTypes = ["force-loop-context", "force-loop-budget"];

	for (const customType of loopMessageTypes) {
		pi.registerMessageRenderer(customType, (message, _options, theme) => {
			const prefix =
				message.customType === "force-loop-budget"
					? theme.fg("warning", "[FORCE-LOOP 预算] ")
					: theme.fg("accent", "[FORCE-LOOP] ");
			return new Text(prefix + theme.fg("dim", message.content), 0, 0);
		});
	}
```

- [ ] **Step 2: Commit**

```bash
git add -A && git commit -m "feat(force-loop): register message renderers for loop context types"
```

---

### Task 10: 端到端手动验证

**Files:**
- None (manual testing)

- [ ] **Step 1: 启动 Pi 并加载扩展**

Run: `pi -e ~/.pi/agent/extensions/force-loop/index.ts`

- [ ] **Step 2: 测试 /loop status（未激活时）**

输入: `/loop status`
Expected: 显示 "Loop 模式未激活"

- [ ] **Step 3: 测试 /loop 基本功能**

输入: `/loop 在当前目录创建三个文件：a.txt, b.txt, c.txt，每个文件写入当前时间`
Expected:
- LLM 调用 `loop_task_tracker create_tasks` 创建任务清单
- LLM 逐步完成每个文件创建，每步调用 `complete_task`
- Widget 实时更新进度
- 全部完成后显示 "所有任务已完成 ✓"

- [ ] **Step 4: 测试 /loop pause/resume**

输入: `/loop pause`
Expected: 显示暂停通知

输入: `/loop resume`
Expected: 恢复执行并发送继续消息

- [ ] **Step 5: 测试 /loop --max 参数**

输入: `/loop 创建一个简单的 hello world Python 脚本 --max 3`
Expected: 最大循环次数为 3，超过后自动停止

- [ ] **Step 6: 清理测试文件**

```bash
rm -f a.txt b.txt c.txt hello.py
```

- [ ] **Step 7: Final commit (if any fixes needed)**

```bash
git add -A && git commit -m "fix(force-loop): address issues from manual testing"
```
