/**
 * DeepSeek Thinking Level Controller
 *
 * 三层保障：
 * 1. thinking_level_select 拦截 — 只允许 high / xhigh 级别
 * 2. before_provider_request 拦截 — 确保发给 DeepSeek 的 reasoning_effort 正确映射
 *    (high → "high", xhigh → "max")
 * 3. Ctrl+Shift+T 快捷键 — 手动切换 high ↔ xhigh
 */

import type { ExtensionAPI, ExtensionContext } from "@mariozechner/pi-coding-agent";

const DEEPSEEK_LEVELS = new Set(["high", "xhigh"]);

/** pi level → DeepSeek reasoning_effort 映射 */
const LEVEL_TO_EFFORT: Record<string, string> = {
  high: "high",
  xhigh: "max",
};

function isDeepseekModel(modelId: string): boolean {
  return modelId.toLowerCase().includes("deepseek");
}

function updateStatus(ctx: ExtensionContext, pi: ExtensionAPI): void {
  const model = ctx.model;
  if (!model) return;

  if (isDeepseekModel(model.id)) {
    const level = pi.getThinkingLevel();
    const effort = LEVEL_TO_EFFORT[level] ?? level;
    ctx.ui.setStatus(
      "deepseek-thinking",
      ctx.ui.theme.fg("accent", `🧠 DeepSeek ${level}→${effort}`)
    );
  } else {
    ctx.ui.setStatus("deepseek-thinking", undefined);
  }
}

export default function (pi: ExtensionAPI) {
  // ─── (1) 拦截 thinking level 变更 ─────────────────────────────────────
  pi.on("thinking_level_select", async (event, ctx) => {
    const model = ctx.model;
    if (!model) return;
    if (!isDeepseekModel(model.id)) {
      updateStatus(ctx, pi);
      return;
    }

    // 如果内置 cycling 切到了不支持级别，立即纠正
    if (!DEEPSEEK_LEVELS.has(event.level as string)) {
      const target =
        event.previousLevel === "high" ? "xhigh" : "high";
      pi.setThinkingLevel(target);
    }

    updateStatus(ctx, pi);
  });

  // ─── (2) 拦截 provider 请求，确保 reasoning_effort 映射正确 ─────────
  pi.on("before_provider_request", (event, ctx) => {
    const model = ctx.model;
    if (!model || !isDeepseekModel(model.id)) return;

    const payload = event.payload as Record<string, unknown>;
    const effort = payload.reasoning_effort as string | undefined;
    if (!effort) return;

    const mapped = LEVEL_TO_EFFORT[effort];
    if (mapped && mapped !== effort) {
      return { ...event.payload, reasoning_effort: mapped } as unknown as typeof event.payload;
    }
  });

  // ─── (3) Ctrl+Shift+T 快捷键 ─────────────────────────────────────────
  pi.registerShortcut("ctrl+shift+t", {
    description: "Toggle DeepSeek thinking (high ↔ xhigh)",
    handler: async (ctx) => {
      const model = ctx.model;
      if (!model) return;

      if (isDeepseekModel(model.id)) {
        const current = pi.getThinkingLevel();
        const next = current === "xhigh" ? "high" : "xhigh";
        pi.setThinkingLevel(next);
        ctx.ui.notify(`DeepSeek thinking: ${next} → effort ${LEVEL_TO_EFFORT[next]}`, "info");
      } else {
        ctx.ui.notify("Not a DeepSeek model", "warning");
      }
      updateStatus(ctx, pi);
    },
  });

  // ─── 启动 & 模型切换时更新状态 ──────────────────────────────────────
  pi.on("session_start", async (_event, ctx) => {
    updateStatus(ctx, pi);
  });

  pi.on("model_select", async (_event, ctx) => {
    updateStatus(ctx, pi);
  });
}
