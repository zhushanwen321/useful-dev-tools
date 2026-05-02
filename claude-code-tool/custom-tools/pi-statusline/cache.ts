import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

// ── Paths ──────────────────────────────────────────────
const HOME = homedir();
const PI_DIR = join(HOME, ".pi");
const CACHE_PATH = join(PI_DIR, "statusline_cache.json");
const SPEED_DIR = join(PI_DIR, "token-stats");
const CACHE_TTL_MS = 120_000;

// ── Types ──────────────────────────────────────────────
export interface ZhipuData {
	label: string;
	tokensPct: number;
	timePct: number;
	timeCurrent: number;
	resetTime: string;
}

export interface TavilyData {
	available: number;
	total: number;
	planUsage: number;
	planLimit: number;
	planName: string;
	keyUsage: number;
	keyLimit: number;
	credits: number;
	requests: number;
}

export interface CacheData {
	updatedAt: number;
	zhipu: ZhipuData | null;
	tavily: TavilyData | null;
}

export interface SpeedData {
	current: number;
	day: number;
	d7: number;
	d30: number;
}

// ── Cache ──────────────────────────────────────────────

export function readCache(): CacheData {
	try {
		const raw = readFileSync(CACHE_PATH, "utf-8");
		const cache = JSON.parse(raw) as CacheData;
		if (Date.now() - cache.updatedAt > CACHE_TTL_MS) triggerUpdate();
		return cache;
	} catch {
		triggerUpdate();
		return { updatedAt: 0, zhipu: null, tavily: null };
	}
}

let updating = false;

export function triggerUpdate(): void {
	if (updating) return;
	updating = true;
	doUpdate()
		.finally(() => {
			updating = false;
		})
		.catch(() => {});
}

async function doUpdate(): Promise<void> {
	const old = readCacheSync();
	const cache: CacheData = { updatedAt: Date.now(), zhipu: null, tavily: null };

	const results = await Promise.allSettled([fetchZhipu(), readTavily()]);
	cache.zhipu =
		results[0].status === "fulfilled" ? results[0].value : old.zhipu;
	cache.tavily =
		results[1].status === "fulfilled" ? results[1].value : old.tavily;

	try {
		mkdirSync(PI_DIR, { recursive: true });
		writeFileSync(CACHE_PATH, JSON.stringify(cache, null, 2), "utf-8");
	} catch {}
}

function readCacheSync(): CacheData {
	try {
		return JSON.parse(readFileSync(CACHE_PATH, "utf-8")) as CacheData;
	} catch {
		return { updatedAt: 0, zhipu: null, tavily: null };
	}
}

// ── Zhipu ──────────────────────────────────────────────

async function fetchZhipu(): Promise<ZhipuData | null> {
	// 查找 auth token（优先 pi，兼容 claude）
	const tokenPaths = [
		join(HOME, ".pi", ".zhipu_auth_token"),
		join(HOME, ".claude", ".zhipu_auth_token"),
	];
	let token = "";
	for (const p of tokenPaths) {
		if (existsSync(p)) {
			token = readFileSync(p, "utf-8").trim();
			break;
		}
	}
	if (!token) return null;

	try {
		const resp = await fetch(
			"https://bigmodel.cn/api/monitor/usage/quota/limit",
			{
				headers: {
					accept: "application/json, text/plain, */*",
					authorization: token,
					"bigmodel-organization":
						"org-8F82302F73594F44B2bdCc5A57BCfD1f",
					"bigmodel-project":
						"proj_8E86D38C8211410Baa4852408071D1F2",
					referer:
						"https://bigmodel.cn/usercenter/glm-coding/usage",
					"user-agent": "Mozilla/5.0",
				},
				signal: AbortSignal.timeout(5000),
			},
		);
		if (!resp.ok) return null;
		const data = (await resp.json()) as any;
		return processZhipu(data);
	} catch {
		return null;
	}
}

function processZhipu(data: any): ZhipuData | null {
	if (!data?.success) return null;
	const d = data.data;
	const label = d?.level ? `Z.ai-${d.level}` : "Z.ai";

	let tokensPct = 0;
	let timePct = 0;
	let timeCurrent = 0;
	let resetMs = 0;

	for (const lim of d?.limits ?? []) {
		if (lim.type === "TOKENS_LIMIT") {
			tokensPct = lim.percentage ?? 0;
			if (lim.nextResetTime) resetMs = Number(lim.nextResetTime);
		} else if (lim.type === "TIME_LIMIT") {
			timePct = lim.percentage ?? 0;
			timeCurrent = lim.currentValue ?? 0;
			if (!resetMs && lim.nextResetTime)
				resetMs = Number(lim.nextResetTime);
		}
	}

	let resetTime = "";
	if (resetMs) {
		const rem =
			Math.floor(resetMs / 1000) - Math.floor(Date.now() / 1000);
		if (rem > 0) {
			const days = Math.floor(rem / 86400);
			const hrs = Math.floor((rem % 86400) / 3600);
			const mins = Math.floor((rem % 3600) / 60);
			if (days > 0) resetTime = `${days}d${hrs}h`;
			else if (hrs > 0) resetTime = `${hrs}h${mins}m`;
			else resetTime = `${mins}m`;
		}
	}

	return { label, tokensPct, timePct, timeCurrent, resetTime };
}

// ── Tavily ─────────────────────────────────────────────

async function readTavily(): Promise<TavilyData | null> {
	const stateFile = join(HOME, ".tavily", "state.json");
	try {
		const data = JSON.parse(readFileSync(stateFile, "utf-8")) as any;
		if (!data?.usage) return null;

		const total = Object.keys(data.usage).length;
		const exhausted = Object.keys(data.exhausted ?? {}).length;
		const entries = Object.values(data.usage) as any[];
		const credits = entries.reduce(
			(s: number, v: any) => s + (v.credits ?? 0),
			0,
		);
		const requests = entries.reduce(
			(s: number, v: any) => s + (v.requests ?? 0),
			0,
		);

		const apiEntries = Object.values(data.api_usage ?? {}) as any[];
		let planUsage = 0;
		let planLimit = 0;
		let keyUsage = 0;
		let keyLimit = 0;
		let planName = "";
		for (const v of apiEntries) {
			planUsage += v.plan_usage ?? 0;
			planLimit += v.plan_limit ?? 0;
			keyUsage += v.key_usage ?? 0;
			keyLimit += v.key_limit ?? 0;
			if (!planName) planName = v.plan_name ?? "";
		}

		return {
			available: total - exhausted,
			total,
			planUsage,
			planLimit,
			planName,
			keyUsage,
			keyLimit,
			credits,
			requests,
		};
	} catch {
		return null;
	}
}

// ── Token Speed ────────────────────────────────────────

// 每条记录存储 [outputTokens, durationMs]，用于正确计算加权平均速度
type Record = [number, number];

export function trackSpeed(
	outputTokens: number,
	durationMs: number,
	model: string,
): SpeedData {
	const current =
		durationMs > 0
			? Math.round((outputTokens / durationMs) * 1000)
			: 0;
	if (!model || current <= 0) return { current, day: 0, d7: 0, d30: 0 };

	const safeName = model.replace(/[/\\\s:]/g, "_");
	const filePath = join(SPEED_DIR, `${safeName}.json`);
	const today = new Date().toISOString().slice(0, 10);

	let records: Record<string, Record[]> = {};
	try {
		if (existsSync(filePath)) {
			const raw = JSON.parse(readFileSync(filePath, "utf-8"));
			// 兼容旧格式 (number[]) → 新格式 ([number, number][])  
			for (const [date, entries] of Object.entries(raw)) {
				if (entries.length > 0 && typeof entries[0] === "number") {
					// 旧格式只有速度值，无法还原 tokens/duration，丢弃
					continue;
			}
				records[date] = entries as Record[];
			}
		}
	} catch {}

	if (!records[today]) records[today] = [];
	records[today].push([outputTokens, durationMs]);

	// 清理 30 天前的数据
	const cutoff = new Date(Date.now() - 30 * 86_400_000)
		.toISOString()
		.slice(0, 10);
	for (const d of Object.keys(records)) {
		if (d < cutoff) delete records[d];
	}

	try {
		mkdirSync(SPEED_DIR, { recursive: true });
		writeFileSync(filePath, JSON.stringify(records));
	} catch {}

	// 加权平均：sum(tokens) / sum(duration) * 1000
	const avgSpeed = (entries: Record[]): number => {
		let totalTokens = 0;
		let totalDuration = 0;
		for (const [tokens, dur] of entries) {
			totalTokens += tokens;
			totalDuration += dur;
		}
		return totalDuration > 0
			? Math.round((totalTokens / totalDuration) * 1000)
			: 0;
	};

	const dayEntries: Record[] = [];
	const d7Entries: Record[] = [];
	const d30Entries: Record[] = [];
	const now = Date.now();

	for (const [date, entries] of Object.entries(records)) {
		d30Entries.push(...entries);
		if ((now - new Date(date).getTime()) / 86_400_000 < 7) {
			d7Entries.push(...entries);
		}
		if (date === today) {
			dayEntries.push(...entries);
		}
	}

	return {
		current,
		day: avgSpeed(dayEntries),
		d7: avgSpeed(d7Entries),
		d30: avgSpeed(d30Entries),
	};
}
