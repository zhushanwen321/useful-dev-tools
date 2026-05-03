/**
 * Pi Statusline — 自定义状态栏
 *
 * 功能：
 * - 模型 + 目录 + Git 分支
 * - 上下文窗口使用率 + 负载率（带进度条）
 * - Zhipu 配额 / Tavily 用量（后台缓存刷新）
 * - Token 输出速度（当前 / 日均 / 7d / 30d）
 * - 会话运行时间、上次 LLM 响应、费用
 * - 宽屏/窄屏自适应
 *
 * 数据来源：
 * - ctx.sessionManager  → token / cost
 * - ctx.model            → 模型信息
 * - footerData           → Git 分支
 * - theme                → 主题感知着色
 * - 缓存文件             → Zhipu / Tavily
 */

import type { AssistantMessage } from "@mariozechner/pi-ai";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { truncateToWidth } from "@mariozechner/pi-tui";
import { readCache, triggerUpdate, trackSpeed, type SpeedData } from "./cache.js";

// ── 常量 ───────────────────────────────────────────────

const SEP = "│";
const DOT = "·";
const WIDE_THRESHOLD = 100; // 终端宽度 ≥ 100 才显示进度条
const RUN_UPDATE_MS = 5000;   // run 时间每 5s 才刷新一次，避免秒级闪烁

// ── ANSI 辅助 ──────────────────────────────────────────
// 进度条需要背景色，theme 不提供，用原始 ANSI

const R = "\x1b[0m";

function bgBar(pct: number, w = 8): string {
	const p = Math.max(0, Math.min(100, Math.round(pct)));
	const filled = Math.floor((p * w) / 100);
	const fillBg =
		p >= 80
			? "\x1b[48;5;196m"
			: p >= 60
				? "\x1b[48;5;208m"
				: p >= 40
					? "\x1b[48;5;220m"
					: "\x1b[48;5;114m";
	const emptyBg = "\x1b[48;5;239m";
	return `${fillBg}${" ".repeat(filled)}${emptyBg}${" ".repeat(w - filled)}${R}`;
}

function fmtDuration(ms: number): string {
	const s = Math.floor(ms / 1000);
	if (s < 60) return `${s}s`;
	const min = Math.floor(s / 60);
	if (min < 60) return `${min}m${String(s % 60).padStart(2, "0")}s`;
	return `${Math.floor(min / 60)}h${String(min % 60).padStart(2, "0")}m`;
}

// ── 状态 ───────────────────────────────────────────────

interface State {
	sessionStart: number;
	lastLlmTime: number;
	assistantStart: number;
	speed: SpeedData;
	lastRunUpdate: number;  // 上次刷新 run 时间的时间戳
	isAgentBusy: boolean;    // AI 是否正在处理中
	thinkingLevel: string;   // 当前 thinking level
	// 缓存汇总（只在 message_end 时更新，避免 model/thinking 切换时重扫 branch）
	totalInp: number;
	totalOut: number;
	totalCost: number;
	usedPct: number;
	loadPct: number;
}

// ── 扩展入口 ───────────────────────────────────────────

export default function (pi: ExtensionAPI) {
	const state: State = {
		sessionStart: 0,
		lastLlmTime: 0,
		assistantStart: 0,
		speed: { current: 0, day: 0, d7: 0, d30: 0 },
		lastRunUpdate: 0,
		isAgentBusy: false,
		thinkingLevel: "",
		totalInp: 0,
		totalOut: 0,
		totalCost: 0,
		usedPct: 0,
		loadPct: 0,
	};

	let tui: { requestRender(): void } | null = null;

	// ── session_start: 设置 footer ──
	pi.on("session_start", async (_event, ctx) => {
		state.sessionStart = Date.now();
		state.lastLlmTime = 0;
		state.speed = { current: 0, day: 0, d7: 0, d30: 0 };
		state.isAgentBusy = false;
		state.thinkingLevel = pi.getThinkingLevel();
		// 首次汇总 token/cost
		refreshTotals(state, ctx);

		ctx.ui.setFooter((t, theme, footerData) => {
			tui = t;
			const unsub = footerData.onBranchChange(() => t.requestRender());

			return {
				dispose() {
					unsub();
					tui = null;
				},
				invalidate() {},
				render(width: number) {
					return buildLines(ctx, theme, footerData, width, state);
				},
			};
		});

		// 首次后台刷新缓存
		triggerUpdate();
	});

	// ── message_start: 记录 LLM 开始时间 ──
	pi.on("message_start", async (event) => {
		if (event.message.role === "assistant") {
			state.assistantStart = Date.now();
			state.isAgentBusy = true;
		}
	});

	// ── message_end: 计算 token 速度，刷新缓存，更新汇总 ──
	pi.on("message_end", async (event, ctx) => {
		if (event.message.role === "assistant") {
			const msg = event.message as AssistantMessage;
			const dur = state.assistantStart ? Date.now() - state.assistantStart : 0;
			state.lastLlmTime = Date.now();
			// session 重放时所有消息瞬间回放，duration≈0，导致虚假极速
			// 输出>50tokens 但 duration<100ms → 跳过此条的速度记录
			const isBogusReplay = msg.usage.output > 50 && dur < 100;
			if (!isBogusReplay) {
				state.speed = trackSpeed(msg.usage.output, dur, ctx.model?.id ?? "");
			} else {
				state.speed = { current: 0, day: 0, d7: 0, d30: 0 };
			}
			// 增量更新汇总（避免全量扫描 session）
			state.totalInp += msg.usage.input;
			state.totalOut += msg.usage.output;
			state.totalCost += msg.usage.cost.total;
			refreshContextUsage(state, ctx);
			tui?.requestRender();
			triggerUpdate();
		}
	});

	// ── turn_end / agent_end: AI 结束/空闲时才刷新 run 时间 ──
	pi.on("turn_end", async () => {
		state.isAgentBusy = false;
		state.lastRunUpdate = Date.now();
		tui?.requestRender();
	});
	pi.on("agent_end", async () => {
		state.isAgentBusy = false;
		state.lastRunUpdate = Date.now();
		tui?.requestRender();
	});
	pi.on("model_select", async () => {
		state.thinkingLevel = pi.getThinkingLevel();
		tui?.requestRender();
	});

	// ── thinking_level_select: 记录 thinking level ──
	pi.on("thinking_level_select", async (event) => {
		state.thinkingLevel = event.level;
		// 如果 AI 不忙，刷新 footer；否则等空闲时再刷新
		if (!state.isAgentBusy) tui?.requestRender();
	});
}

// ── 渲染 ───────────────────────────────────────────────

/** 全量扫描 session 汇总 token/cost（仅 session_start 时调用） */
function refreshTotals(st: State, ctx: any): void {
	let inp = 0, out = 0, cost = 0;
	for (const e of ctx.sessionManager.getBranch()) {
		if (e.type === "message" && e.message.role === "assistant") {
			const u = (e.message as AssistantMessage).usage;
			inp += u.input;
			out += u.output;
			cost += u.cost.total;
		}
	}
	st.totalInp = inp;
	st.totalOut = out;
	st.totalCost = cost;
	refreshContextUsage(st, ctx);
}

/** 更新上下文使用率缓存 */
function refreshContextUsage(st: State, ctx: any): void {
	const model = ctx.model;
	const contextWindow = model?.contextWindow || 128_000;
	const usage = ctx.getContextUsage();
	const usedPct = usage
		? Math.min(Math.round((usage.tokens / contextWindow) * 100), 100)
		: 0;
	st.usedPct = usedPct;
	st.loadPct = Math.min(Math.round((usedPct * 100) / 84), 100);
}

function buildLines(
	ctx: any,
	theme: any,
	fd: any,
	width: number,
	st: State,
): string[] {
	const cache = readCache();

	// ── 1. 使用缓存汇总数据（在 message_end/session_start 时更新） ──
	const inp = st.totalInp;
	const out = st.totalOut;
	const cost = st.totalCost;

	// ── 2. 使用缓存的上下文使用率 + thinking level ──
	const model = ctx.model;
	const modelName = model?.name || model?.id || "unknown";
	const usedPct = st.usedPct;
	const loadPct = st.loadPct;

	// ── 3. 其他信息 ──
	const branch = fd.getGitBranch();
	const dir = ctx.cwd ? ctx.cwd.split("/").pop() || "" : "";
	const sid =
		ctx.sessionManager
			.getSessionFile()
			?.split("/")
			.pop()
			?.slice(-12) || "";

	// ── 主题颜色快捷函数 ──
	const fg = (color: string, text: string) => theme.fg(color, text);
	const d = (s: string) => fg("dim", s); // dim label
	const v = (s: string) => fg("text", s); // 普通值
	const g = (s: string) => fg("success", s); // 正常/绿色
	const w = (s: string) => fg("warning", s); // 警告/黄色
	const a = (s: string) => fg("accent", s); // 强调/蓝色
	const m = (s: string) => fg("muted", s); // 次要/灰色

	const wide = width >= WIDE_THRESHOLD;
	const lines: string[] = [];

	// ═══════════════════════════════════════════════════
	// Line 1: 身份 — 目录 · 分支 · 模型 + thinking level
	// ═══════════════════════════════════════════════════
	const idParts: string[] = [];
	if (dir) idParts.push(a(dir));
	if (branch) idParts.push(`⎇ ${g(branch)}`);
	if (usedPct > 80) idParts.push(w("⚠ ctx"));

	let line1 = idParts.join(` ${DOT} `);
	if (modelName) {
		const namePart = a(modelName);
		const tlPart = st.thinkingLevel ? m(`[${st.thinkingLevel}]`) : "";
		line1 += ` ${SEP} ${namePart} ${tlPart}`;
	}
	if (line1) lines.push(line1);

	// ═══════════════════════════════════════════════════
	// Line 2: 上下文 + Zhipu
	// ═══════════════════════════════════════════════════
	const ctxStr = wide
		? `${d("ctx")} ${bgBar(usedPct)} ${v(`${usedPct}%`)}`
		: `${d("ctx")} ${v(`${usedPct}%`)}`;
	const loadStr = wide
		? `${d("load")} ${bgBar(loadPct)} ${v(`${loadPct}%`)}`
		: `${d("load")} ${v(`${loadPct}%`)}`;

	let line2 = `${ctxStr} ${DOT} ${loadStr}`;

	const z = cache.zhipu;
	if (z) {
		const zBar = wide
			? ` ${bgBar(z.tokensPct, 6)} ${v(`${z.tokensPct}%`)}`
			: ` ${v(`${z.tokensPct}%`)}`;
		let zs = `${d(z.label)}${zBar}`;

		if (z.timePct) {
			const mBar = wide
				? ` ${bgBar(z.timePct, 6)} ${v(`${z.timePct}%`)}`
				: ` ${v(`${z.timePct}%`)}`;
			zs += ` ${DOT} ${d("mcp")}${mBar} ${m(`(${z.timeCurrent})`)}`;
		}
		if (z.resetTime) zs += ` ${DOT} ${d("reset")} ${w(z.resetTime)}`;

		line2 += ` ${SEP} ${zs}`;
	}
	lines.push(line2);

	// ═══════════════════════════════════════════════════
	// Line 3: Tavily（如果有）
	// ═══════════════════════════════════════════════════
	const tv = cache.tavily;
	if (tv) {
		const tp: string[] = [
			`${d("Tavily")} ${g(`${tv.available}/${tv.total}`)}`,
		];
		if (tv.planLimit > 0) {
			const pct = Math.round((tv.planUsage / tv.planLimit) * 100);
			const pBar = wide
				? `${bgBar(pct, 6)} ${v(`${pct}%`)} ${DOT} ${v(`${tv.planUsage}/${tv.planLimit}`)}`
				: `${v(`${tv.planUsage}/${tv.planLimit}`)}`;
			tp.push(`${d("plan")} ${pBar}`);
		}
		if (tv.keyLimit > 0)
			tp.push(`${d("key")} ${v(`${tv.keyUsage}/${tv.keyLimit}`)}`);
		if (tv.credits > 0 || tv.requests > 0) {
			tp.push(
				`${d("used")} ${w(`${tv.credits}`)}cr ${DOT} ${d("req")} ${g(`${tv.requests}`)}`,
			);
		}
		lines.push(tp.join(` ${SEP} `));
	}

	// ═══════════════════════════════════════════════════
	// Line 4: 速度 + 时间 + 费用 + 会话ID
	// ═══════════════════════════════════════════════════
	const sp: string[] = [];
	if (st.speed.current > 0) sp.push(`${g(`${st.speed.current}`)}t/s`);
	if (st.speed.day > 0) sp.push(`day ${g(`${st.speed.day}`)}`);
	if (st.speed.d7 > 0) sp.push(`7d ${g(`${st.speed.d7}`)}`);
	if (wide && st.speed.d30 > 0) sp.push(`30d ${m(`${st.speed.d30}`)}`);

	const tp: string[] = [];
	if (st.sessionStart) {
		const from = new Date(st.sessionStart);
		tp.push(
			`${d("from")} ${g(`${from.getHours()}:${String(from.getMinutes()).padStart(2, "0")}`)}`,
		);
	}
	// run 时间：AI 繁忙或距离上次更新时间 < RUN_UPDATE_MS 时不刷新（避免秒级闪烁）
	const runMs = st.sessionStart ? Date.now() - st.sessionStart : 0;
	const shouldRefreshRun = !st.isAgentBusy &&
		(st.lastRunUpdate === 0 || Date.now() - st.lastRunUpdate >= RUN_UPDATE_MS);
	if (shouldRefreshRun) {
		st.lastRunUpdate = Date.now();
	}
	const displayRunMs = st.lastRunUpdate ? st.lastRunUpdate - st.sessionStart : runMs;
	if (displayRunMs > 0) tp.push(`${d("run")} ${g(fmtDuration(displayRunMs))}`);
	if (st.lastLlmTime) {
		const ago = Math.floor((Date.now() - st.lastLlmTime) / 1000);
		tp.push(
			`${d("last")} ${w(ago < 60 ? `${ago}s` : `${Math.floor(ago / 60)}m${ago % 60}s`)}`,
		);
	}

	const info: string[] = [];
	if (sp.length) info.push(sp.join(` ${DOT} `));
	if (tp.length) info.push(tp.join(` ${DOT} `));
	if (cost > 0) info.push(`${d("cost")} ${w(`$${cost.toFixed(3)}`)}`);
	if (inp > 0 || out > 0) {
		const fmt = (n: number) => (n < 1000 ? `${n}` : `${(n / 1000).toFixed(1)}k`);
		info.push(`${d("↑↓")} ${v(fmt(inp))}/${v(fmt(out))}`);
	}
	if (sid) info.push(m(sid));

	if (info.length) lines.push(info.join(` ${SEP} `));

	return lines.map((l) => truncateToWidth(l, width));
}
