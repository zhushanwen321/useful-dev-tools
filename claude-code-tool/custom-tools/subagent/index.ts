/**
 * Subagent Tool v2 — Delegate tasks with explicit model selection
 *
 * Changes from original:
 * - model is REQUIRED ("provider/model" format, exact match from scoped models)
 * - No timeout — subagents run until completion or Ctrl+C
 * - background mode: detached spawn, collect results later
 * - Agent .md files provide systemPrompt + tools; model is always caller-specified
 *
 * Tools registered:
 *   subagent         — foreground (blocking) or background mode
 *   collect_subagent — collect background job results
 */

import { spawn } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { randomUUID } from "node:crypto";
import type { AgentToolResult } from "@mariozechner/pi-agent-core";
import type { Message } from "@mariozechner/pi-ai";
import { StringEnum } from "@mariozechner/pi-ai";
import { type ExtensionAPI, getMarkdownTheme, withFileMutationQueue } from "@mariozechner/pi-coding-agent";
import { Container, Markdown, Spacer, Text } from "@mariozechner/pi-tui";
import { Type } from "typebox";
import { type AgentConfig, type AgentScope, discoverAgents } from "./agents.js";

// ──────────────────────── Constants ────────────────────────

const MAX_PARALLEL_TASKS = 8;
const MAX_CONCURRENCY = 4;
const COLLAPSED_ITEM_COUNT = 10;

// ──────────────────────── Formatting helpers ────────────────────────

function formatTokens(count: number): string {
	if (count < 1000) return count.toString();
	if (count < 10000) return `${(count / 1000).toFixed(1)}k`;
	if (count < 1000000) return `${Math.round(count / 1000)}k`;
	return `${(count / 1000000).toFixed(1)}M}`;
}

function formatUsageStats(
	usage: {
		input: number;
		output: number;
		cacheRead: number;
		cacheWrite: number;
		cost: number;
		contextTokens?: number;
		turns?: number;
	},
	model?: string,
): string {
	const parts: string[] = [];
	if (usage.turns) parts.push(`${usage.turns} turn${usage.turns > 1 ? "s" : ""}`);
	if (usage.input) parts.push(`↑${formatTokens(usage.input)}`);
	if (usage.output) parts.push(`↓${formatTokens(usage.output)}`);
	if (usage.cacheRead) parts.push(`R${formatTokens(usage.cacheRead)}`);
	if (usage.cacheWrite) parts.push(`W${formatTokens(usage.cacheWrite)}`);
	if (usage.cost) parts.push(`$${usage.cost.toFixed(4)}`);
	if (usage.contextTokens && usage.contextTokens > 0) {
		parts.push(`ctx:${formatTokens(usage.contextTokens)}`);
	}
	if (model) parts.push(model);
	return parts.join(" ");
}

function formatToolCall(
	toolName: string,
	args: Record<string, unknown>,
	themeFg: (color: any, text: string) => string,
): string {
	const shortenPath = (p: string) => {
		const home = os.homedir();
		return p.startsWith(home) ? `~${p.slice(home.length)}` : p;
	};

	switch (toolName) {
		case "bash": {
			const command = (args.command as string) || "...";
			const preview = command.length > 60 ? `${command.slice(0, 60)}...` : command;
			return themeFg("muted", "$ ") + themeFg("toolOutput", preview);
		}
		case "read": {
			const rawPath = (args.file_path || args.path || "...") as string;
			const filePath = shortenPath(rawPath);
			const offset = args.offset as number | undefined;
			const limit = args.limit as number | undefined;
			let text = themeFg("accent", filePath);
			if (offset !== undefined || limit !== undefined) {
				const startLine = offset ?? 1;
				const endLine = limit !== undefined ? startLine + limit - 1 : "";
				text += themeFg("warning", `:${startLine}${endLine ? `-${endLine}` : ""}`);
			}
			return themeFg("muted", "read ") + text;
		}
		case "write": {
			const rawPath = (args.file_path || args.path || "...") as string;
			const filePath = shortenPath(rawPath);
			const content = (args.content || "") as string;
			const lines = content.split("\n").length;
			let text = themeFg("muted", "write ") + themeFg("accent", filePath);
			if (lines > 1) text += themeFg("dim", ` (${lines} lines)`);
			return text;
		}
		case "edit": {
			const rawPath = (args.file_path || args.path || "...") as string;
			return themeFg("muted", "edit ") + themeFg("accent", shortenPath(rawPath));
		}
		case "ls": {
			const rawPath = (args.path || ".") as string;
			return themeFg("muted", "ls ") + themeFg("accent", shortenPath(rawPath));
		}
		case "find": {
			const pattern = (args.pattern || "*") as string;
			const rawPath = (args.path || ".") as string;
			return themeFg("muted", "find ") + themeFg("accent", pattern) + themeFg("dim", ` in ${shortenPath(rawPath)}`);
		}
		case "grep": {
			const pattern = (args.pattern || "") as string;
			const rawPath = (args.path || ".") as string;
			return (
				themeFg("muted", "grep ") +
				themeFg("accent", `/${pattern}/`) +
				themeFg("dim", ` in ${shortenPath(rawPath)}`)
			);
		}
		default: {
			const argsStr = JSON.stringify(args);
			const preview = argsStr.length > 50 ? `${argsStr.slice(0, 50)}...` : argsStr;
			return themeFg("accent", toolName) + themeFg("dim", ` ${preview}`);
		}
	}
}

// ──────────────────────── Interfaces ────────────────────────

interface UsageStats {
	input: number;
	output: number;
	cacheRead: number;
	cacheWrite: number;
	cost: number;
	contextTokens: number;
	turns: number;
}

interface SingleResult {
	agent: string;
	agentSource: "user" | "project" | "unknown";
	task: string;
	exitCode: number;
	messages: Message[];
	stderr: string;
	usage: UsageStats;
	model?: string;
	stopReason?: string;
	errorMessage?: string;
	step?: number;
}

interface SubagentDetails {
	mode: "single" | "parallel" | "chain" | "background";
	resolvedModel: string;
	agentScope: AgentScope;
	projectAgentsDir: string | null;
	results: SingleResult[];
}

// ──────────────────────── Message helpers ────────────────────────

function getFinalOutput(messages: Message[]): string {
	for (let i = messages.length - 1; i >= 0; i--) {
		const msg = messages[i];
		if (msg.role === "assistant") {
			for (const part of msg.content) {
				if (part.type === "text") return part.text;
			}
		}
	}
	return "";
}

type DisplayItem = { type: "text"; text: string } | { type: "toolCall"; name: string; args: Record<string, any> };

function getDisplayItems(messages: Message[]): DisplayItem[] {
	const items: DisplayItem[] = [];
	for (const msg of messages) {
		if (msg.role === "assistant") {
			for (const part of msg.content) {
				if (part.type === "text") items.push({ type: "text", text: part.text });
				else if (part.type === "toolCall") items.push({ type: "toolCall", name: part.name, args: part.arguments });
			}
		}
	}
	return items;
}

// ──────────────────────── Utility ────────────────────────

async function mapWithConcurrencyLimit<TIn, TOut>(
	items: TIn[],
	concurrency: number,
	fn: (item: TIn, index: number) => Promise<TOut>,
): Promise<TOut[]> {
	if (items.length === 0) return [];
	const limit = Math.max(1, Math.min(concurrency, items.length));
	const results: TOut[] = new Array(items.length);
	let nextIndex = 0;
	const workers = new Array(limit).fill(null).map(async () => {
		while (true) {
			const current = nextIndex++;
			if (current >= items.length) return;
			results[current] = await fn(items[current], current);
		}
	});
	await Promise.all(workers);
	return results;
}

async function writePromptToTempFile(agentName: string, prompt: string): Promise<{ dir: string; filePath: string }> {
	const tmpDir = await fs.promises.mkdtemp(path.join(os.tmpdir(), "pi-subagent-"));
	const safeName = agentName.replace(/[^\w.-]+/g, "_");
	const filePath = path.join(tmpDir, `prompt-${safeName}.md`);
	await withFileMutationQueue(filePath, async () => {
		await fs.promises.writeFile(filePath, prompt, { encoding: "utf-8", mode: 0o600 });
	});
	return { dir: tmpDir, filePath };
}

function getPiInvocation(args: string[]): { command: string; args: string[] } {
	const currentScript = process.argv[1];
	const isBunVirtualScript = currentScript?.startsWith("/$bunfs/root/");
	if (currentScript && !isBunVirtualScript && fs.existsSync(currentScript)) {
		return { command: process.execPath, args: [currentScript, ...args] };
	}

	const execName = path.basename(process.execPath).toLowerCase();
	const isGenericRuntime = /^(node|bun)(\.exe)?$/.test(execName);
	if (!isGenericRuntime) {
		return { command: process.execPath, args };
	}

	return { command: "pi", args };
}

// ──────────────────────── Model resolution ────────────────────────

async function resolveModel(
	modelRef: string,
	ctx: any,
): Promise<{ ok: true; ref: string } | { ok: false; error: string }> {
	const slashIndex = modelRef.indexOf("/");
	if (slashIndex <= 0 || slashIndex === modelRef.length - 1) {
		return {
			ok: false,
			error: `Model must be in "provider/model" format. Got: "${modelRef}".`,
		};
	}

	const provider = modelRef.substring(0, slashIndex);
	const modelId = modelRef.substring(slashIndex + 1);

	let models: Array<{ id: string; provider: string }>;
	try {
		models = (await ctx.modelRegistry?.getAvailable?.()) ?? [];
	} catch {
		models = [];
	}

	if (models.length === 0) {
		// Cannot validate — pass through to CLI
		return { ok: true, ref: modelRef };
	}

	const match = models.find((m) => m.provider === provider && m.id === modelId);
	if (match) {
		return { ok: true, ref: `${match.provider}/${match.id}` };
	}

	const lines = models.map((m) => `  - ${m.id} (${m.provider})`).join("\n");
	return {
		ok: false,
		error: `Model "${modelRef}" not found in scoped models.\nAvailable models:\n${lines}`,
	};
}

// ──────────────────────── Background job management ────────────────────────

interface JobInfo {
	id: string;
	agent: string;
	task: string;
	model: string;
	pid: number;
	startedAt: number;
	status: "running" | "done" | "failed" | "aborted";
	outFile: string;
	errFile: string;
	promptFile: string | null;
	promptDir: string | null;
}

const jobs = new Map<string, JobInfo>();

function getJobDir(): string {
	const dir = path.join(os.tmpdir(), "pi-subagent-jobs");
	if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
	return dir;
}

function parseOutputFile(filePath: string): {
	output: string;
	usage: UsageStats;
	model?: string;
	stopReason?: string;
	errorMessage?: string;
} {
	const empty = {
		output: "",
		usage: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, cost: 0, contextTokens: 0, turns: 0 },
	};

	if (!fs.existsSync(filePath)) return empty;

	let content: string;
	try {
		content = fs.readFileSync(filePath, "utf-8");
	} catch {
		return empty;
	}

	const lines = content.split("\n").filter((l) => l.trim());
	const usage: UsageStats = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, cost: 0, contextTokens: 0, turns: 0 };
	let output = "";
	let model: string | undefined;
	let stopReason: string | undefined;
	let errorMessage: string | undefined;

	for (const line of lines) {
		let event: any;
		try {
			event = JSON.parse(line);
		} catch {
			continue;
		}

		if (event.type === "message_end" && event.message) {
			const msg = event.message as Message;
			if (msg.role === "assistant") {
				usage.turns++;
				const u = msg.usage;
				if (u) {
					usage.input += u.input || 0;
					usage.output += u.output || 0;
					usage.cacheRead += u.cacheRead || 0;
					usage.cacheWrite += u.cacheWrite || 0;
					usage.cost += u.cost?.total || 0;
					usage.contextTokens = u.totalTokens || 0;
				}
				if (msg.model) model = msg.model;
				if (msg.stopReason) stopReason = msg.stopReason;
				if (msg.errorMessage) errorMessage = msg.errorMessage;
				for (const part of msg.content) {
					if (part.type === "text") output = part.text;
				}
			}
		}
	}

	return { output, usage, model, stopReason, errorMessage };
}

// ──────────────────────── Process spawning ────────────────────────

type OnUpdateCallback = (partial: AgentToolResult<SubagentDetails>) => void;

async function runSingleAgent(
	defaultCwd: string,
	agents: AgentConfig[],
	agentName: string,
	task: string,
	resolvedModel: string,
	cwd: string | undefined,
	step: number | undefined,
	signal: AbortSignal | undefined,
	onUpdate: OnUpdateCallback | undefined,
	makeDetails: (results: SingleResult[]) => SubagentDetails,
): Promise<SingleResult> {
	const agent = agents.find((a) => a.name === agentName);

	if (!agent) {
		const available = agents.map((a) => `"${a.name}"`).join(", ") || "none";
		return {
			agent: agentName,
			agentSource: "unknown",
			task,
			exitCode: 1,
			messages: [],
			stderr: `Unknown agent: "${agentName}". Available agents: ${available}.`,
			usage: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, cost: 0, contextTokens: 0, turns: 0 },
			step,
		};
	}

	const args: string[] = ["--mode", "json", "-p", "--no-session"];
	args.push("--model", resolvedModel);
	if (agent.tools && agent.tools.length > 0) args.push("--tools", agent.tools.join(","));

	let tmpPromptDir: string | null = null;
	let tmpPromptPath: string | null = null;

	const currentResult: SingleResult = {
		agent: agentName,
		agentSource: agent.source,
		task,
		exitCode: 0,
		messages: [],
		stderr: "",
		usage: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, cost: 0, contextTokens: 0, turns: 0 },
		model: resolvedModel,
		step,
	};

	const emitUpdate = () => {
		if (onUpdate) {
			onUpdate({
				content: [{ type: "text", text: getFinalOutput(currentResult.messages) || "(running...)" }],
				details: makeDetails([currentResult]),
			});
		}
	};

	try {
		if (agent.systemPrompt.trim()) {
			const tmp = await writePromptToTempFile(agent.name, agent.systemPrompt);
			tmpPromptDir = tmp.dir;
			tmpPromptPath = tmp.filePath;
			args.push("--append-system-prompt", tmpPromptPath);
		}

		args.push(`Task: ${task}`);
		let wasAborted = false;

		const exitCode = await new Promise<number>((resolve) => {
			const invocation = getPiInvocation(args);
			const proc = spawn(invocation.command, invocation.args, {
				cwd: cwd ?? defaultCwd,
				shell: false,
				stdio: ["ignore", "pipe", "pipe"],
			});
			let buffer = "";

			const processLine = (line: string) => {
				if (!line.trim()) return;
				let event: any;
				try {
					event = JSON.parse(line);
				} catch {
					return;
				}

				if (event.type === "message_end" && event.message) {
					const msg = event.message as Message;
					currentResult.messages.push(msg);

					if (msg.role === "assistant") {
						currentResult.usage.turns++;
						const usage = msg.usage;
						if (usage) {
							currentResult.usage.input += usage.input || 0;
							currentResult.usage.output += usage.output || 0;
							currentResult.usage.cacheRead += usage.cacheRead || 0;
							currentResult.usage.cacheWrite += usage.cacheWrite || 0;
							currentResult.usage.cost += usage.cost?.total || 0;
							currentResult.usage.contextTokens = usage.totalTokens || 0;
						}
						if (msg.model) currentResult.model = msg.model;
						if (msg.stopReason) currentResult.stopReason = msg.stopReason;
						if (msg.errorMessage) currentResult.errorMessage = msg.errorMessage;
					}
					emitUpdate();
				}

				if (event.type === "tool_result_end" && event.message) {
					currentResult.messages.push(event.message as Message);
					emitUpdate();
				}
			};

			proc.stdout.on("data", (data) => {
				buffer += data.toString();
				const lines = buffer.split("\n");
				buffer = lines.pop() || "";
				for (const line of lines) processLine(line);
			});

			proc.stderr.on("data", (data) => {
				currentResult.stderr += data.toString();
			});

			proc.on("close", (code) => {
				if (buffer.trim()) processLine(buffer);
				resolve(code ?? 0);
			});

			proc.on("error", () => {
				resolve(1);
			});

			if (signal) {
				const killProc = () => {
					wasAborted = true;
					proc.kill("SIGTERM");
					setTimeout(() => {
						if (!proc.killed) proc.kill("SIGKILL");
					}, 5000);
				};
				if (signal.aborted) killProc();
				else signal.addEventListener("abort", killProc, { once: true });
			}
		});

		currentResult.exitCode = exitCode;
		if (wasAborted) throw new Error("Subagent was aborted");
		return currentResult;
	} finally {
		if (tmpPromptPath)
			try {
				fs.unlinkSync(tmpPromptPath);
			} catch {
				/* ignore */
			}
		if (tmpPromptDir)
			try {
				fs.rmdirSync(tmpPromptDir);
			} catch {
				/* ignore */
			}
	}
}

async function startBackgroundJob(
	defaultCwd: string,
	agents: AgentConfig[],
	agentName: string,
	task: string,
	resolvedModel: string,
	cwd: string | undefined,
): Promise<{ ok: true; jobId: string } | { ok: false; error: string }> {
	const agent = agents.find((a) => a.name === agentName);

	if (!agent) {
		const available = agents.map((a) => `"${a.name}"`).join(", ") || "none";
		return { ok: false, error: `Unknown agent: "${agentName}". Available agents: ${available}.` };
	}

	const jobId = `subagent-bg-${randomUUID().slice(0, 8)}`;
	const outFile = path.join(getJobDir(), `${jobId}.out`);
	const errFile = path.join(getJobDir(), `${jobId}.err`);

	const args: string[] = ["--mode", "json", "-p", "--no-session"];
	args.push("--model", resolvedModel);
	if (agent.tools && agent.tools.length > 0) args.push("--tools", agent.tools.join(","));

	let promptFile: string | null = null;
	let promptDir: string | null = null;

	if (agent.systemPrompt.trim()) {
		const tmp = await writePromptToTempFile(agent.name, agent.systemPrompt);
		promptDir = tmp.dir;
		promptFile = tmp.filePath;
		args.push("--append-system-prompt", promptFile);
	}

	args.push(`Task: ${task}`);

	const invocation = getPiInvocation(args);
	const proc = spawn(invocation.command, invocation.args, {
		cwd: cwd ?? defaultCwd,
		shell: false,
		stdio: ["ignore", "pipe", "pipe"],
	});

	const outStream = fs.createWriteStream(outFile);
	const errStream = fs.createWriteStream(errFile);
	proc.stdout.pipe(outStream);
	proc.stderr.pipe(errStream);

	const job: JobInfo = {
		id: jobId,
		agent: agentName,
		task,
		model: resolvedModel,
		pid: proc.pid ?? 0,
		startedAt: Date.now(),
		status: "running",
		outFile,
		errFile,
		promptFile,
		promptDir,
	};
	jobs.set(jobId, job);

	proc.on("close", (code) => {
		job.status = code === 0 ? "done" : "failed";
		outStream.end();
		errStream.end();
		// Clean up prompt temp file
		if (promptFile) {
			try { fs.unlinkSync(promptFile); } catch { /* ignore */ }
		}
		if (promptDir) {
			try { fs.rmdirSync(promptDir); } catch { /* ignore */ }
		}
		job.promptFile = null;
		job.promptDir = null;
	});

	proc.on("error", () => {
		job.status = "failed";
		outStream.end();
		errStream.end();
	});

	proc.unref();
	return { ok: true, jobId };
}

function cleanupJob(job: JobInfo) {
	if (job.status === "running") {
		try {
			process.kill(job.pid, "SIGTERM");
		} catch {
			/* already dead */
		}
		job.status = "aborted";
	}
	for (const f of [job.outFile, job.errFile, job.promptFile]) {
		if (f) {
			try { fs.unlinkSync(f); } catch { /* ignore */ }
		}
	}
	if (job.promptDir) {
		try { fs.rmdirSync(job.promptDir); } catch { /* ignore */ }
	}
}

// ──────────────────────── Tool parameters ────────────────────────

const TaskItem = Type.Object({
	agent: Type.String({ description: "Name of the agent to invoke" }),
	task: Type.String({ description: "Task to delegate to the agent" }),
	cwd: Type.Optional(Type.String({ description: "Working directory for the agent process" })),
});

const ChainItem = Type.Object({
	agent: Type.String({ description: "Name of the agent to invoke" }),
	task: Type.String({ description: "Task with optional {previous} placeholder for prior output" }),
	cwd: Type.Optional(Type.String({ description: "Working directory for the agent process" })),
});

const AgentScopeSchema = StringEnum(["user", "project", "both"] as const, {
	description: 'Which agent directories to use. Default: "user".',
	default: "user",
});

const SubagentParams = Type.Object({
	agent: Type.Optional(Type.String({ description: "Name of the agent to invoke (single mode)" })),
	task: Type.Optional(Type.String({ description: "Task to delegate (single mode)" })),
	tasks: Type.Optional(Type.Array(TaskItem, { description: "Array of {agent, task} for parallel execution" })),
	chain: Type.Optional(Type.Array(ChainItem, { description: "Array of {agent, task} for sequential execution" })),
	model: Type.String({
		description: 'REQUIRED. Model in "provider/model" format (e.g. "llm-simple-router-dev/glm-5.1"). Must be a scoped model.',
	}),
	background: Type.Optional(Type.Boolean({
		description: "Run in background (single mode only). Returns job ID immediately. Default: false.",
		default: false,
	})),
	agentScope: Type.Optional(AgentScopeSchema),
	confirmProjectAgents: Type.Optional(
		Type.Boolean({ description: "Prompt before running project-local agents. Default: true.", default: true }),
	),
	cwd: Type.Optional(Type.String({ description: "Working directory for the agent process (single mode)" })),
});

const CollectSubagentParams = Type.Object({
	jobId: Type.Optional(Type.String({
		description: "Job ID from background subagent. Omit to list all active jobs.",
	})),
});

// ──────────────────────── Extension entry ────────────────────────

export default function (pi: ExtensionAPI) {
	// ── Tool: subagent ──
	pi.registerTool({
		name: "subagent",
		label: "Subagent",
		description: [
			"Delegate tasks to specialized subagents with isolated context.",
			'The \"model\" parameter is REQUIRED and must be in \"provider/model\" format (e.g. \"llm-simple-router-dev/glm-5.1\").',
			"If model validation fails, the error will list all available models with their providers — use one from that list.",
			"Modes: single (agent + task), parallel (tasks array), chain (sequential with {previous} placeholder).",
			"Set background: true for single mode to run in background (collect with collect_subagent).",
			'Agent scope defaults to \"user\" (from ~/.pi/agent/agents).',
		].join(" "),
		parameters: SubagentParams,
		promptSnippet: "Delegate independent work to sub-agents with explicit model selection",
		promptGuidelines: [
			'subagent model is REQUIRED — must use "provider/model" format (NOT bare id like "glm-5.1", must be "llm-simple-router-dev/glm-5.1")',
			'If unsure which models are available, call subagent with any model — the validation error will list all scoped models with providers',
			"Choose cheaper/faster models for simple tasks, stronger models for complex analysis",
			"Set background: true to run a task without waiting for the result",
			"Use collect_subagent to retrieve background task results",
			"Agents provide specialized system prompts and tool restrictions",
		],

		async execute(_toolCallId, params, signal, onUpdate, ctx) {
			const modelParam = params.model as string;
			const isBackground = (params.background as boolean) ?? false;

			// ── Step 1: Resolve model ──
			const modelResult = await resolveModel(modelParam, ctx);
			if (!modelResult.ok) {
				return {
					content: [{ type: "text", text: (modelResult as { ok: false; error: string }).error }],
					details: { mode: "single" as const, resolvedModel: modelParam, agentScope: "user" as AgentScope, projectAgentsDir: null, results: [] },
					isError: true,
				};
			}
			const resolvedModel = modelResult.ref;

			// ── Step 2: Discover agents ──
			const agentScope: AgentScope = params.agentScope ?? "user";
			const discovery = discoverAgents(ctx.cwd, agentScope);
			const agents = discovery.agents;
			const confirmProjectAgents = params.confirmProjectAgents ?? true;

			// ── Step 3: Determine mode ──
			const hasChain = (params.chain?.length ?? 0) > 0;
			const hasTasks = (params.tasks?.length ?? 0) > 0;
			const hasSingle = Boolean(params.agent && params.task);
			const modeCount = Number(hasChain) + Number(hasTasks) + Number(hasSingle);

			const makeDetails =
				(mode: "single" | "parallel" | "chain" | "background") =>
				(results: SingleResult[]): SubagentDetails => ({
					mode,
					resolvedModel,
					agentScope,
					projectAgentsDir: discovery.projectAgentsDir,
					results,
				});

			if (modeCount !== 1) {
				const available = agents.map((a) => `${a.name} (${a.source})`).join(", ") || "none";
				return {
					content: [{ type: "text", text: `Invalid parameters. Provide exactly one mode.\nAvailable agents: ${available}` }],
					details: makeDetails("single")([]),
				};
			}

			// ── Step 4: Confirm project agents ──
			if ((agentScope === "project" || agentScope === "both") && confirmProjectAgents && ctx.hasUI) {
				const requestedAgentNames = new Set<string>();
				if (params.chain) for (const step of params.chain) requestedAgentNames.add(step.agent);
				if (params.tasks) for (const t of params.tasks) requestedAgentNames.add(t.agent);
				if (params.agent) requestedAgentNames.add(params.agent);

				const projectAgentsRequested = Array.from(requestedAgentNames)
					.map((name) => agents.find((a) => a.name === name))
					.filter((a): a is AgentConfig => a?.source === "project");

				if (projectAgentsRequested.length > 0) {
					const names = projectAgentsRequested.map((a) => a.name).join(", ");
					const dir = discovery.projectAgentsDir ?? "(unknown)";
					const ok = await ctx.ui.confirm(
						"Run project-local agents?",
						`Agents: ${names}\nSource: ${dir}\n\nProject agents are repo-controlled. Only continue for trusted repositories.`,
					);
					if (!ok)
						return {
							content: [{ type: "text", text: "Canceled: project-local agents not approved." }],
							details: makeDetails(hasChain ? "chain" : hasTasks ? "parallel" : "single")([]),
						};
				}
			}

			// ── Step 5: Background single mode ──
			if (isBackground) {
				if (!hasSingle) {
					return {
						content: [{ type: "text", text: "Background mode only supports single mode (agent + task)." }],
						details: makeDetails("background")([]),
						isError: true,
					};
				}

				const bgResult = await startBackgroundJob(
					ctx.cwd, agents, params.agent as string, params.task as string, resolvedModel, params.cwd as string | undefined,
				);

				if (!bgResult.ok) {
					return {
						content: [{ type: "text", text: (bgResult as { ok: false; error: string }).error }],
						details: makeDetails("background")([]),
						isError: true,
					};
				}

				return {
					content: [{
						type: "text",
						text: [
							`[Background subagent started]`,
							`  Job ID: ${bgResult.jobId}`,
							`  Agent:  ${params.agent}`,
							`  Model:  ${resolvedModel}`,
							`  Task:   ${(params.task as string).slice(0, 100)}`,
							``,
							`Use collect_subagent with jobId "${bgResult.jobId}" to get results.`,
						].join("\n"),
					}],
					details: makeDetails("background")([]),
				};
			}

			// ── Step 6: Foreground chain mode ──
			if (params.chain && params.chain.length > 0) {
				const results: SingleResult[] = [];
				let previousOutput = "";

				for (let i = 0; i < params.chain.length; i++) {
					const step = params.chain[i];
					const taskWithContext = step.task.replace(/\{previous\}/g, previousOutput);

					const chainUpdate: OnUpdateCallback | undefined = onUpdate
						? (partial) => {
								const currentResult = partial.details?.results[0];
								if (currentResult) {
									const allResults = [...results, currentResult];
									onUpdate({
										content: partial.content,
										details: makeDetails("chain")(allResults),
									});
								}
							}
						: undefined;

					const result = await runSingleAgent(
						ctx.cwd, agents, step.agent, taskWithContext,
						resolvedModel, step.cwd, i + 1, signal, chainUpdate, makeDetails("chain"),
					);
					results.push(result);

					const isError = result.exitCode !== 0 || result.stopReason === "error" || result.stopReason === "aborted";
					if (isError) {
						const errorMsg = result.errorMessage || result.stderr || getFinalOutput(result.messages) || "(no output)";
						return {
							content: [{ type: "text", text: `Chain stopped at step ${i + 1} (${step.agent}): ${errorMsg}` }],
							details: makeDetails("chain")(results),
							isError: true,
						};
					}
					previousOutput = getFinalOutput(result.messages);
				}
				return {
					content: [{ type: "text", text: getFinalOutput(results[results.length - 1].messages) || "(no output)" }],
					details: makeDetails("chain")(results),
				};
			}

			// ── Step 7: Foreground parallel mode ──
			if (params.tasks && params.tasks.length > 0) {
				if (params.tasks.length > MAX_PARALLEL_TASKS)
					return {
						content: [{ type: "text", text: `Too many parallel tasks (${params.tasks.length}). Max is ${MAX_PARALLEL_TASKS}.` }],
						details: makeDetails("parallel")([]),
					};

				const allResults: SingleResult[] = new Array(params.tasks.length);
				for (let i = 0; i < params.tasks.length; i++) {
					allResults[i] = {
						agent: params.tasks[i].agent,
						agentSource: "unknown",
						task: params.tasks[i].task,
						exitCode: -1,
						messages: [],
						stderr: "",
						usage: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, cost: 0, contextTokens: 0, turns: 0 },
					};
				}

				const emitParallelUpdate = () => {
					if (onUpdate) {
						const running = allResults.filter((r) => r.exitCode === -1).length;
						const done = allResults.filter((r) => r.exitCode !== -1).length;
						onUpdate({
							content: [{ type: "text", text: `Parallel: ${done}/${allResults.length} done, ${running} running...` }],
							details: makeDetails("parallel")([...allResults]),
						});
					}
				};

				const results = await mapWithConcurrencyLimit(params.tasks, MAX_CONCURRENCY, async (t, index) => {
					const result = await runSingleAgent(
						ctx.cwd, agents, t.agent, t.task,
						resolvedModel, t.cwd, undefined, signal,
						(partial) => {
							if (partial.details?.results[0]) {
								allResults[index] = partial.details.results[0];
								emitParallelUpdate();
							}
						},
						makeDetails("parallel"),
					);
					allResults[index] = result;
					emitParallelUpdate();
					return result;
				});

				const successCount = results.filter((r) => r.exitCode === 0).length;
				const summaries = results.map((r) => {
					const output = getFinalOutput(r.messages);
					const preview = output.slice(0, 100) + (output.length > 100 ? "..." : "");
					return `[${r.agent}] ${r.exitCode === 0 ? "completed" : "failed"}: ${preview || "(no output)"}`;
				});
				return {
					content: [{
						type: "text",
						text: `Parallel: ${successCount}/${results.length} succeeded\n\n${summaries.join("\n\n")}`,
					}],
					details: makeDetails("parallel")(results),
				};
			}

			// ── Step 8: Foreground single mode ──
			if (params.agent && params.task) {
				const result = await runSingleAgent(
					ctx.cwd, agents, params.agent, params.task,
					resolvedModel, params.cwd, undefined, signal, onUpdate, makeDetails("single"),
				);
				const isError = result.exitCode !== 0 || result.stopReason === "error" || result.stopReason === "aborted";
				if (isError) {
					const errorMsg = result.errorMessage || result.stderr || getFinalOutput(result.messages) || "(no output)";
					return {
						content: [{ type: "text", text: `Agent ${result.stopReason || "failed"}: ${errorMsg}` }],
						details: makeDetails("single")([result]),
						isError: true,
					};
				}
				return {
					content: [{ type: "text", text: getFinalOutput(result.messages) || "(no output)" }],
					details: makeDetails("single")([result]),
				};
			}

			const available = agents.map((a) => `${a.name} (${a.source})`).join(", ") || "none";
			return {
				content: [{ type: "text", text: `Invalid parameters. Available agents: ${available}` }],
				details: makeDetails("single")([]),
			};
		},

		renderCall(args, theme, _context) {
			const scope: AgentScope = args.agentScope ?? "user";
			const model = args.model || "?";
			const bg = args.background ? theme.fg("warning", " [bg]") : "";

			if (args.chain && args.chain.length > 0) {
				let text =
					theme.fg("toolTitle", theme.bold("subagent ")) +
					theme.fg("accent", `chain (${args.chain.length} steps)`) +
					theme.fg("muted", ` [${scope}]`) +
					theme.fg("dim", ` ${model}`) +
					bg;
				for (let i = 0; i < Math.min(args.chain.length, 3); i++) {
					const step = args.chain[i];
					const cleanTask = step.task.replace(/\{previous\}/g, "").trim();
					const preview = cleanTask.length > 40 ? `${cleanTask.slice(0, 40)}...` : cleanTask;
					text += "\n  " + theme.fg("muted", `${i + 1}.`) + " " + theme.fg("accent", step.agent) + theme.fg("dim", ` ${preview}`);
				}
				if (args.chain.length > 3) text += `\n  ${theme.fg("muted", `... +${args.chain.length - 3} more`)}`;
				return new Text(text, 0, 0);
			}
			if (args.tasks && args.tasks.length > 0) {
				let text =
					theme.fg("toolTitle", theme.bold("subagent ")) +
					theme.fg("accent", `parallel (${args.tasks.length} tasks)`) +
					theme.fg("muted", ` [${scope}]`) +
					theme.fg("dim", ` ${model}`) +
					bg;
				for (const t of args.tasks.slice(0, 3)) {
					const preview = t.task.length > 40 ? `${t.task.slice(0, 40)}...` : t.task;
					text += `\n  ${theme.fg("accent", t.agent)}${theme.fg("dim", ` ${preview}`)}`;
				}
				if (args.tasks.length > 3) text += `\n  ${theme.fg("muted", `... +${args.tasks.length - 3} more`)}`;
				return new Text(text, 0, 0);
			}
			const agentName = args.agent || "...";
			const preview = args.task ? (args.task.length > 60 ? `${args.task.slice(0, 60)}...` : args.task) : "...";
			let text =
				theme.fg("toolTitle", theme.bold("subagent ")) +
				theme.fg("accent", agentName) +
				theme.fg("muted", ` [${scope}]`) +
				theme.fg("dim", ` ${model}`) +
				bg;
			text += `\n  ${theme.fg("dim", preview)}`;
			return new Text(text, 0, 0);
		},

		renderResult(result, { expanded }, theme, _context) {
			const details = result.details as SubagentDetails | undefined;
			if (!details || details.results.length === 0) {
				const text = result.content[0];
				return new Text(text?.type === "text" ? text.text : "(no output)", 0, 0);
			}

			const mdTheme = getMarkdownTheme();

			const renderDisplayItems = (items: DisplayItem[], limit?: number) => {
				const toShow = limit ? items.slice(-limit) : items;
				const skipped = limit && items.length > limit ? items.length - limit : 0;
				let text = "";
				if (skipped > 0) text += theme.fg("muted", `... ${skipped} earlier items\n`);
				for (const item of toShow) {
					if (item.type === "text") {
						const preview = expanded ? item.text : item.text.split("\n").slice(0, 3).join("\n");
						text += `${theme.fg("toolOutput", preview)}\n`;
					} else {
						text += `${theme.fg("muted", "→ ") + formatToolCall(item.name, item.args, theme.fg.bind(theme))}\n`;
					}
				}
				return text.trimEnd();
			};

			if (details.mode === "single" && details.results.length === 1) {
				const r = details.results[0];
				const isError = r.exitCode !== 0 || r.stopReason === "error" || r.stopReason === "aborted";
				const icon = isError ? theme.fg("error", "✗") : theme.fg("success", "✓");
				const displayItems = getDisplayItems(r.messages);
				const finalOutput = getFinalOutput(r.messages);

				if (expanded) {
					const container = new Container();
					let header = `${icon} ${theme.fg("toolTitle", theme.bold(r.agent))}${theme.fg("muted", ` (${r.agentSource})`)}`;
					header += ` ${theme.fg("dim", details.resolvedModel)}`;
					if (isError && r.stopReason) header += ` ${theme.fg("error", `[${r.stopReason}]`)}`;
					container.addChild(new Text(header, 0, 0));
					if (isError && r.errorMessage)
						container.addChild(new Text(theme.fg("error", `Error: ${r.errorMessage}`), 0, 0));
					container.addChild(new Spacer(1));
					container.addChild(new Text(theme.fg("muted", "─── Task ───"), 0, 0));
					container.addChild(new Text(theme.fg("dim", r.task), 0, 0));
					container.addChild(new Spacer(1));
					container.addChild(new Text(theme.fg("muted", "─── Output ───"), 0, 0));
					if (displayItems.length === 0 && !finalOutput) {
						container.addChild(new Text(theme.fg("muted", "(no output)"), 0, 0));
					} else {
						for (const item of displayItems) {
							if (item.type === "toolCall")
								container.addChild(
									new Text(theme.fg("muted", "→ ") + formatToolCall(item.name, item.args, theme.fg.bind(theme)), 0, 0),
								);
						}
						if (finalOutput) {
							container.addChild(new Spacer(1));
							container.addChild(new Markdown(finalOutput.trim(), 0, 0, mdTheme));
						}
					}
					const usageStr = formatUsageStats(r.usage, r.model);
					if (usageStr) {
						container.addChild(new Spacer(1));
						container.addChild(new Text(theme.fg("dim", usageStr), 0, 0));
					}
					return container;
				}

				let text = `${icon} ${theme.fg("toolTitle", theme.bold(r.agent))}${theme.fg("muted", ` (${r.agentSource})`)}`;
				text += ` ${theme.fg("dim", details.resolvedModel)}`;
				if (isError && r.stopReason) text += ` ${theme.fg("error", `[${r.stopReason}]`)}`;
				if (isError && r.errorMessage) text += `\n${theme.fg("error", `Error: ${r.errorMessage}`)}`;
				else if (displayItems.length === 0) text += `\n${theme.fg("muted", "(no output)")}`;
				else {
					text += `\n${renderDisplayItems(displayItems, COLLAPSED_ITEM_COUNT)}`;
					if (displayItems.length > COLLAPSED_ITEM_COUNT) text += `\n${theme.fg("muted", "(Ctrl+O to expand)")}`;
				}
				const usageStr = formatUsageStats(r.usage, r.model);
				if (usageStr) text += `\n${theme.fg("dim", usageStr)}`;
				return new Text(text, 0, 0);
			}

			const aggregateUsage = (results: SingleResult[]) => {
				const total = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, cost: 0, turns: 0 };
				for (const r of results) {
					total.input += r.usage.input;
					total.output += r.usage.output;
					total.cacheRead += r.usage.cacheRead;
					total.cacheWrite += r.usage.cacheWrite;
					total.cost += r.usage.cost;
					total.turns += r.usage.turns;
				}
				return total;
			};

			if (details.mode === "chain") {
				const successCount = details.results.filter((r) => r.exitCode === 0).length;
				const icon = successCount === details.results.length ? theme.fg("success", "✓") : theme.fg("error", "✗");

				if (expanded) {
					const container = new Container();
					container.addChild(
						new Text(
							icon +
								" " + theme.fg("toolTitle", theme.bold("chain ")) +
								theme.fg("accent", `${successCount}/${details.results.length} steps`) +
								theme.fg("dim", ` ${details.resolvedModel}`),
							0, 0,
						),
					);

					for (const r of details.results) {
						const rIcon = r.exitCode === 0 ? theme.fg("success", "✓") : theme.fg("error", "✗");
						const displayItems = getDisplayItems(r.messages);
						const finalOutput = getFinalOutput(r.messages);

						container.addChild(new Spacer(1));
						container.addChild(
							new Text(`${theme.fg("muted", `─── Step ${r.step}: `) + theme.fg("accent", r.agent)} ${rIcon}`, 0, 0),
						);
						container.addChild(new Text(theme.fg("muted", "Task: ") + theme.fg("dim", r.task), 0, 0));

						for (const item of displayItems) {
							if (item.type === "toolCall") {
								container.addChild(
									new Text(theme.fg("muted", "→ ") + formatToolCall(item.name, item.args, theme.fg.bind(theme)), 0, 0),
								);
							}
						}

						if (finalOutput) {
							container.addChild(new Spacer(1));
							container.addChild(new Markdown(finalOutput.trim(), 0, 0, mdTheme));
						}

						const stepUsage = formatUsageStats(r.usage, r.model);
						if (stepUsage) container.addChild(new Text(theme.fg("dim", stepUsage), 0, 0));
					}

					const usageStr = formatUsageStats(aggregateUsage(details.results));
					if (usageStr) {
						container.addChild(new Spacer(1));
						container.addChild(new Text(theme.fg("dim", `Total: ${usageStr}`), 0, 0));
					}
					return container;
				}

				let text =
					icon + " " + theme.fg("toolTitle", theme.bold("chain ")) +
					theme.fg("accent", `${successCount}/${details.results.length} steps`) +
					theme.fg("dim", ` ${details.resolvedModel}`);
				for (const r of details.results) {
					const rIcon = r.exitCode === 0 ? theme.fg("success", "✓") : theme.fg("error", "✗");
					const displayItems = getDisplayItems(r.messages);
					text += `\n\n${theme.fg("muted", `─── Step ${r.step}: `)}${theme.fg("accent", r.agent)} ${rIcon}`;
					if (displayItems.length === 0) text += `\n${theme.fg("muted", "(no output)")}`;
					else text += `\n${renderDisplayItems(displayItems, 5)}`;
				}
				const usageStr = formatUsageStats(aggregateUsage(details.results));
				if (usageStr) text += `\n\n${theme.fg("dim", `Total: ${usageStr}`)}`;
				text += `\n${theme.fg("muted", "(Ctrl+O to expand)")}`;
				return new Text(text, 0, 0);
			}

			if (details.mode === "parallel") {
				const running = details.results.filter((r) => r.exitCode === -1).length;
				const successCount = details.results.filter((r) => r.exitCode === 0).length;
				const failCount = details.results.filter((r) => r.exitCode > 0).length;
				const isRunning = running > 0;
				const icon = isRunning
					? theme.fg("warning", "⏳")
					: failCount > 0
						? theme.fg("warning", "◐")
						: theme.fg("success", "✓");
				const status = isRunning
					? `${successCount + failCount}/${details.results.length} done, ${running} running`
					: `${successCount}/${details.results.length} tasks`;

				if (expanded && !isRunning) {
					const container = new Container();
					container.addChild(
						new Text(
							`${icon} ${theme.fg("toolTitle", theme.bold("parallel "))}${theme.fg("accent", status)}` +
							theme.fg("dim", ` ${details.resolvedModel}`),
							0, 0,
						),
					);

					for (const r of details.results) {
						const rIcon = r.exitCode === 0 ? theme.fg("success", "✓") : theme.fg("error", "✗");
						const displayItems = getDisplayItems(r.messages);
						const finalOutput = getFinalOutput(r.messages);

						container.addChild(new Spacer(1));
						container.addChild(new Text(`${theme.fg("muted", "─── ") + theme.fg("accent", r.agent)} ${rIcon}`, 0, 0));
						container.addChild(new Text(theme.fg("muted", "Task: ") + theme.fg("dim", r.task), 0, 0));

						for (const item of displayItems) {
							if (item.type === "toolCall") {
								container.addChild(
									new Text(theme.fg("muted", "→ ") + formatToolCall(item.name, item.args, theme.fg.bind(theme)), 0, 0),
								);
							}
						}

						if (finalOutput) {
							container.addChild(new Spacer(1));
							container.addChild(new Markdown(finalOutput.trim(), 0, 0, mdTheme));
						}

						const taskUsage = formatUsageStats(r.usage, r.model);
						if (taskUsage) container.addChild(new Text(theme.fg("dim", taskUsage), 0, 0));
					}

					const usageStr = formatUsageStats(aggregateUsage(details.results));
					if (usageStr) {
						container.addChild(new Spacer(1));
						container.addChild(new Text(theme.fg("dim", `Total: ${usageStr}`), 0, 0));
					}
					return container;
				}

				let text = `${icon} ${theme.fg("toolTitle", theme.bold("parallel "))}${theme.fg("accent", status)}` +
					theme.fg("dim", ` ${details.resolvedModel}`);
				for (const r of details.results) {
					const rIcon =
						r.exitCode === -1
							? theme.fg("warning", "⏳")
							: r.exitCode === 0
								? theme.fg("success", "✓")
								: theme.fg("error", "✗");
					const displayItems = getDisplayItems(r.messages);
					text += `\n\n${theme.fg("muted", "─── ")}${theme.fg("accent", r.agent)} ${rIcon}`;
					if (displayItems.length === 0)
						text += `\n${theme.fg("muted", r.exitCode === -1 ? "(running...)" : "(no output)")}`;
					else text += `\n${renderDisplayItems(displayItems, 5)}`;
				}
				if (!isRunning) {
					const usageStr = formatUsageStats(aggregateUsage(details.results));
					if (usageStr) text += `\n\n${theme.fg("dim", `Total: ${usageStr}`)}`;
				}
				if (!expanded) text += `\n${theme.fg("muted", "(Ctrl+O to expand)")}`;
				return new Text(text, 0, 0);
			}

			const text = result.content[0];
			return new Text(text?.type === "text" ? text.text : "(no output)", 0, 0);
		},
	});

	// ── Tool: collect_subagent ──
	pi.registerTool({
		name: "collect_subagent",
		label: "Collect Subagent",
		description: "Collect results from a background subagent. Omit jobId to list all active background jobs.",
		parameters: CollectSubagentParams,

		async execute(_toolCallId, params, signal, onUpdate, _ctx) {
			const jobId = params.jobId as string | undefined;

			// ── List all jobs (no jobId) ──
			if (!jobId) {
				const lines: string[] = ["[Active background jobs]"];
				for (const [id, job] of jobs) {
					const elapsed = ((Date.now() - job.startedAt) / 1000).toFixed(1);
					lines.push(`  ${id} | ${job.status} | ${job.model} | ${elapsed}s | "${job.task.slice(0, 50)}..."`);
				}
				if (lines.length === 1) lines.push("  (none)");
				return {
					content: [{ type: "text", text: lines.join("\n") }],
					details: { count: jobs.size },
				};
			}

			const job = jobs.get(jobId);
			if (!job) {
				return {
					content: [{ type: "text", text: `[Job not found: ${jobId}]` }],
					isError: true,
				};
			}

			// ── Internal polling with sleep until job completes ──
			// Progressive wait intervals (seconds): 5, 10, 15, 20, 30, then 30s repeated
			const WAIT_INTERVALS = [10, 20, 40, 80, 120];
			const MAX_WAIT = 120;
			let waitIndex = 0;

			while (job.status === "running") {
				const waitSec = waitIndex < WAIT_INTERVALS.length
					? WAIT_INTERVALS[waitIndex]
					: MAX_WAIT;
				waitIndex++;

				const elapsed = ((Date.now() - job.startedAt) / 1000).toFixed(1);
				onUpdate?.({
					content: [{
						type: "text",
						text: `[Job ${jobId.slice(0, 8)}... still running (${elapsed}s), waiting ${waitSec}s before next check...]`,
					}],
				});

				// Sleep with abort signal support
				const aborted = await new Promise<boolean>((resolve) => {
					const timer = setTimeout(() => resolve(false), waitSec * 1000);
					if (signal) {
						if (signal.aborted) { clearTimeout(timer); resolve(true); }
						else signal.addEventListener("abort", () => { clearTimeout(timer); resolve(true); }, { once: true });
					} else {
						resolve(false);
					}
				});

				if (aborted) {
					return {
						content: [{ type: "text", text: `[Job ${jobId.slice(0, 8)}... collection aborted by user]` }],
						isError: true,
					};
				}
			}

			// ── Job finished — parse and return result ──
			const elapsed = ((Date.now() - job.startedAt) / 1000).toFixed(1);
			const parsed = parseOutputFile(job.outFile);
			let stderr = "";
			try {
				if (fs.existsSync(job.errFile)) stderr = fs.readFileSync(job.errFile, "utf-8").trim();
			} catch { /* ignore */ }

			const label = job.status === "done" ? "completed" : job.status;
			const usageStr = formatUsageStats(parsed.usage, parsed.model);
			const parts = [
				`[Background job ${jobId.slice(0, 8)}... ${label} (${elapsed}s)]`,
				`  Agent: ${job.agent}`,
				`  Model: ${job.model}`,
			];
			if (usageStr) parts.push(`  Usage: ${usageStr}`);
			if (parsed.errorMessage) parts.push(`  Error: ${parsed.errorMessage}`);
			parts.push("", parsed.output || "(no output)");
			if (stderr) parts.push("", `[stderr]`, stderr);

			// Clean up output files after successful collect
			for (const f of [job.outFile, job.errFile]) {
				try { fs.unlinkSync(f); } catch { /* ignore */ }
			}
			jobs.delete(jobId);

			return {
				content: [{ type: "text", text: parts.join("\n") }],
			};
		},
	});

	// ── Cleanup on session shutdown ──
	pi.on("session_shutdown", async () => {
		for (const [id, job] of jobs) {
			cleanupJob(job);
		}
		jobs.clear();
	});
}
