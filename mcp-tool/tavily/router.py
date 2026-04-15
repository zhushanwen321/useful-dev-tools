#!/usr/bin/env python3
"""Tavily API Key Router — MCP Server

将多个 Tavily API key 池化，round-robin 轮询。
遇到额度耗尽（432/433）或速率限制（429）自动切换到下一个 key。
key 状态持久化到 ~/.tavily/state.json，次月自动恢复额度。
"""

import os
import json
import time
import logging
from pathlib import Path
from typing import Any

import httpx
from mcp.server.fastmcp import FastMCP

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(name)s] %(levelname)s: %(message)s")
logger = logging.getLogger("tavily-router")

API_BASE = "https://api.tavily.com"
STATE_DIR = Path.home() / ".tavily"
STATE_FILE = STATE_DIR / "state.json"

# ── 持久化 ────────────────────────────────────────────────────

def _load_state() -> dict:
    """从 ~/.tavily/state.json 加载持久化状态。"""
    if STATE_FILE.exists():
        try:
            return json.loads(STATE_FILE.read_text("utf-8"))
        except Exception:
            logger.warning("state.json 解析失败，使用空状态")
    return {}

def _save_state(state: dict):
    """将状态写入 ~/.tavily/state.json。"""
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(state, ensure_ascii=False, indent=2), "utf-8")

def _current_month() -> str:
    """返回当前年月字符串，如 '2026-04'。"""
    return time.strftime("%Y-%m")

def _key_repr(key: str) -> str:
    """脱敏展示 key，如 '...a1b2'。"""
    return f"...{key[-6:]}" if len(key) > 6 else key

# ── Key 池管理 ──────────────────────────────────────────────

class KeyPool:
    """Round-robin key 选择，按月跟踪耗尽状态并持久化。"""

    def __init__(self, keys: list[str]):
        self.keys = keys
        self._idx = 0
        # 从持久化文件恢复状态
        state = _load_state()
        # exhausted: key → {"month": "2026-04", "reason": "...", "ts": 1713000000}
        self.exhausted: dict[str, dict] = state.get("exhausted", {})
        # usage: key → {"credits": 0, "requests": 0, "last_used": "2026-04-14T..."}
        self.usage: dict[str, dict] = state.get("usage", {})
        # 确保 state.json 中有所有 key 的 usage 条目
        for key in keys:
            if key not in self.usage:
                self.usage[key] = {"credits": 0, "requests": 0, "last_used": None}
        # API 返回的权威用量（与 key 级别对应，非累计）
        self.api_usage: dict[str, dict] = state.get("api_usage", {})
        # usage API 调用缓存（内存级，不持久化，5 分钟 TTL）
        self._usage_cache: dict[str, dict] = {}

        self._maybe_recover()

    def _maybe_recover(self):
        """检查耗尽的 key 是否到了新月份，自动恢复。"""
        now_month = _current_month()
        recovered = [k for k, v in self.exhausted.items() if v.get("month") != now_month]
        for k in recovered:
            del self.exhausted[k]
            logger.info(f"Key {_key_repr(k)} 已随月度重置恢复（上次耗尽于 {now_month}）")

    def next_key(self) -> str | None:
        self._maybe_recover()
        for _ in range(len(self.keys)):
            key = self.keys[self._idx % len(self.keys)]
            self._idx += 1
            if key not in self.exhausted:
                return key
        return None

    def mark_exhausted(self, key: str, reason: str = ""):
        self.exhausted[key] = {
            "month": _current_month(),
            "reason": reason,
            "ts": time.time(),
        }
        logger.warning(f"Key {_key_repr(key)} 已标记耗尽 ({reason})，将在次月自动恢复")
        self._persist()

    async def verify_exhausted(self, key: str) -> bool:
        """调用 Tavily Usage API 确认 key 是否真的耗尽，避免误判。"""
        # 缓存：同一个 key 在 5 分钟内不重复查询（usage API 限 10次/10min）
        cache = self._usage_cache.get(key)
        if cache and time.time() - cache["ts"] < 300:
            logger.info(f"Key {_key_repr(key)} 使用缓存 usage 结果")
            return cache["exhausted"]

        try:
            async with httpx.AsyncClient(timeout=15.0) as client:
                resp = await client.get(
                    f"{API_BASE}/usage",
                    headers={"Authorization": f"Bearer {key}"},
                )
            if resp.status_code != 200:
                logger.warning(f"Usage API 返回 HTTP {resp.status_code}，跳过校验")
                return False

            data = resp.json()
            key_info = data.get("key", {})
            acct_info = data.get("account", {})

            # 持久化 API 返回的权威用量数据
            self.api_usage[key] = {
                "fetched_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
                "key_usage": key_info.get("usage", 0),
                "key_limit": key_info.get("limit", 0),
                "plan_usage": acct_info.get("plan_usage", 0),
                "plan_limit": acct_info.get("plan_limit", 0),
                "plan_name": acct_info.get("current_plan", "unknown"),
            }
            self._persist()

            # 判断是否真正耗尽
            key_exhausted = key_info.get("usage", 0) >= key_info.get("limit", 1)
            acct_exhausted = acct_info.get("plan_usage", 0) >= acct_info.get("plan_limit", 1)
            is_exhausted = key_exhausted or acct_exhausted

            detail_parts = []
            if key_exhausted:
                detail_parts.append(f"key {key_info.get('usage')}/{key_info.get('limit')}")
            if acct_exhausted:
                detail_parts.append(f"plan {acct_info.get('plan_usage')}/{acct_info.get('plan_limit')}")
            logger.info(f"Key {_key_repr(key)} usage 校验: {'耗尽' if is_exhausted else '未耗尽'} ({', '.join(detail_parts)})")

            self._usage_cache[key] = {"exhausted": is_exhausted, "ts": time.time()}
            return is_exhausted
        except Exception as e:
            logger.warning(f"Usage API 调用失败: {e}，跳过校验")
            return False

    def record_usage(self, key: str, credits: int):
        """记录一次成功的请求消耗。"""
        entry = self.usage.get(key, {"credits": 0, "requests": 0, "last_used": None})
        entry["credits"] += credits
        entry["requests"] += 1
        entry["last_used"] = time.strftime("%Y-%m-%dT%H:%M:%S")
        self.usage[key] = entry
        self._persist()

    @property
    def available_count(self) -> int:
        return sum(1 for k in self.keys if k not in self.exhausted)

    def _persist(self):
        """将当前状态写入磁盘。"""
        _save_state({
            "exhausted": self.exhausted,
            "usage": self.usage,
            "api_usage": self.api_usage,
        })

    def get_summary(self) -> str:
        """返回所有 key 的状态摘要，包含 API 权威用量。"""
        now_month = _current_month()
        lines = [f"当前月份: {now_month}", f"总 key 数: {len(self.keys)}", f"可用: {self.available_count}", ""]
        for key in self.keys:
            status = "可用" if key not in self.exhausted else f"耗尽 ({self.exhausted[key].get('reason', '?')})"
            u = self.usage.get(key, {})
            au = self.api_usage.get(key, {})
            api_str = ""
            if au:
                api_str = f" | API: {au.get('key_usage', '?')}/{au.get('key_limit', '?')} (plan {au.get('plan_usage', '?')}/{au.get('plan_limit', '?')}) [{au.get('plan_name', '?')}]"
            lines.append(f"  {_key_repr(key)} | {status} | credits={u.get('credits', 0)} reqs={u.get('requests', 0)}{api_str}")
        return "\n".join(lines)

# ── 初始化 ──────────────────────────────────────────────────

_raw_keys = os.environ.get("TAVILY_API_KEYS", "")
API_KEYS = [k.strip() for k in _raw_keys.split(",") if k.strip()]

if not API_KEYS:
    raise SystemExit("请设置环境变量 TAVILY_API_KEYS，多个 key 用逗号分隔")

pool = KeyPool(API_KEYS)
logger.info(f"已加载 {len(API_KEYS)} 个 API key，可用 {pool.available_count} 个")

# 启动时刷新所有 key 的 usage 数据，写入 state.json 供 statusline 等外部工具读取
def _refresh_all_usage_sync():
    with httpx.Client(timeout=5.0) as client:
        for key in pool.keys:
            try:
                resp = client.get(f"{API_BASE}/usage", headers={"Authorization": f"Bearer {key}"})
                if resp.status_code == 200:
                    data = resp.json()
                    pool.api_usage[key] = {
                        "fetched_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
                        "key_usage": data.get("key", {}).get("usage", 0),
                        "key_limit": data.get("key", {}).get("limit", 0),
                        "plan_usage": data.get("account", {}).get("plan_usage", 0),
                        "plan_limit": data.get("account", {}).get("plan_limit", 0),
                        "plan_name": data.get("account", {}).get("current_plan", "unknown"),
                    }
            except Exception as e:
                logger.warning(f"启动刷新 key {_key_repr(key)} usage 失败: {e}")
    pool._persist()

_refresh_all_usage_sync()

mcp = FastMCP("tavily-router")

# ── API 请求层 ──────────────────────────────────────────────

async def _tavily_request(endpoint: str, payload: dict[str, Any]) -> dict:
    """发送请求到 Tavily API，自动轮换 key。429 仅轮换，432/433 先确认再标记。"""
    EXHAUSTION_CODES = {432, 433}  # 额度耗尽
    RATE_LIMIT_CODE = 429           # 速率限制

    for _ in range(len(pool.keys)):
        key = pool.next_key()
        if key is None:
            return {"error": "所有 API key 已耗尽，请次月重试或添加新 key"}

        headers = {"Authorization": f"Bearer {key}", "Content-Type": "application/json"}
        async with httpx.AsyncClient(timeout=120.0) as client:
            resp = await client.post(f"{API_BASE}/{endpoint}", json=payload, headers=headers)

        if resp.status_code == RATE_LIMIT_CODE:
            # 速率限制：轮换到下一个 key，但不标记为耗尽
            logger.info(f"Key {_key_repr(key)} 触发速率限制 (429)，轮换到下一个 key")
            continue

        if resp.status_code in EXHAUSTION_CODES:
            reason = f"HTTP {resp.status_code}"
            try:
                reason = resp.json().get("detail", {}).get("error", reason)
            except Exception:
                pass
            # 调用 usage API 确认是否真的耗尽
            truly_exhausted = await pool.verify_exhausted(key)
            if truly_exhausted:
                pool.mark_exhausted(key, reason)
                logger.info(f"尝试下一个 key（剩余 {pool.available_count} 个可用）")
                continue
            else:
                # API 返回 432/433 但 usage 显示未耗尽，可能是瞬时状态，重试当前 key
                logger.info(f"Key {_key_repr(key)} 返回 {resp.status_code} 但 usage 未耗尽，重试当前 key")
                async with httpx.AsyncClient(timeout=120.0) as client:
                    resp = await client.post(f"{API_BASE}/{endpoint}", json=payload, headers=headers)
                if resp.status_code >= 400:
                    # 重试仍失败，跳过这个 key
                    logger.info(f"Key {_key_repr(key)} 重试仍返回 HTTP {resp.status_code}，跳过")
                    continue

        if resp.status_code >= 400:
            return {"error": f"Tavily API HTTP {resp.status_code}", "detail": resp.text}

        # 从响应中提取 usage 并记录
        try:
            body = resp.json()
            credits = body.get("usage", {}).get("credits", 1)
            pool.record_usage(key, credits)
            return body
        except Exception:
            return resp.json()

    return {"error": "所有 API key 已耗尽，请次月重试或添加新 key"}

# ── MCP 工具 ────────────────────────────────────────────────

@mcp.tool()
async def tavily_search(
    query: str,
    search_depth: str = "basic",
    topic: str = "general",
    max_results: int = 10,
    include_images: bool = False,
    include_raw_content: bool = False,
    include_domains: list[str] | None = None,
    exclude_domains: list[str] | None = None,
    time_range: str | None = None,
    country: str | None = None,
) -> dict:
    """Search the web using Tavily."""
    payload: dict[str, Any] = {
        "query": query, "search_depth": search_depth, "topic": topic,
        "max_results": max_results, "include_images": include_images,
        "include_raw_content": include_raw_content,
    }
    if include_domains: payload["include_domains"] = include_domains
    if exclude_domains: payload["exclude_domains"] = exclude_domains
    if time_range: payload["time_range"] = time_range
    if country: payload["country"] = country
    return await _tavily_request("search", payload)

@mcp.tool()
async def tavily_extract(
    urls: list[str], extract_depth: str = "basic",
    format: str = "markdown", include_images: bool = False,
) -> dict:
    """Extract raw content from URLs."""
    return await _tavily_request("extract", {
        "urls": urls, "extract_depth": extract_depth,
        "format": format, "include_images": include_images,
    })

@mcp.tool()
async def tavily_crawl(
    url: str, max_depth: int = 1, max_breadth: int = 20, limit: int = 50,
    extract_depth: str = "basic", format: str = "markdown",
    select_paths: list[str] | None = None, select_domains: list[str] | None = None,
    allow_external: bool = True, instructions: str = "", include_favicon: bool = False,
) -> dict:
    """Crawl a website starting from a URL."""
    payload: dict[str, Any] = {
        "url": url, "max_depth": max_depth, "max_breadth": max_breadth,
        "limit": limit, "extract_depth": extract_depth, "format": format,
        "allow_external": allow_external, "include_favicon": include_favicon,
    }
    if instructions: payload["instructions"] = instructions
    if select_paths: payload["select_paths"] = select_paths
    if select_domains: payload["select_domains"] = select_domains
    return await _tavily_request("crawl", payload)

@mcp.tool()
async def tavily_map(
    url: str, max_depth: int = 1, max_breadth: int = 20, limit: int = 50,
    select_paths: list[str] | None = None, select_domains: list[str] | None = None,
    allow_external: bool = True, instructions: str = "", include_favicon: bool = False,
) -> dict:
    """Map a website's structure."""
    payload: dict[str, Any] = {
        "url": url, "max_depth": max_depth, "max_breadth": max_breadth,
        "limit": limit, "allow_external": allow_external, "include_favicon": include_favicon,
    }
    if instructions: payload["instructions"] = instructions
    if select_paths: payload["select_paths"] = select_paths
    if select_domains: payload["select_domains"] = select_domains
    return await _tavily_request("map", payload)

@mcp.tool()
async def tavily_key_status():
    """查看当前 API key 池的状态，包括各 key 的可用性和用量统计。"""
    return pool.get_summary()

if __name__ == "__main__":
    mcp.run()
