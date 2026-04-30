#!/usr/bin/env python3
"""Tavily Web Search — standalone CLI for Tavily API with multi-key rotation.

Usage:
  python tavily.py search <query> [--depth basic|advanced] [--topic general|news] [--max-results N] [--time-range day|week|month|year] [--include-images] [--include-raw]
  python tavily.py extract <urls...> [--depth basic|advanced]
  python tavily.py crawl <url> [--max-depth N] [--max-breadth N] [--limit N] [--instructions TEXT]
  python tavily.py map <url> [--max-depth N] [--max-breadth N] [--limit N]
  python tavily.py status

Environment:
  TAVILY_API_KEYS  Comma-separated API keys (required)

State persistence:
  ~/.tavily/state.json  Key exhaustion state, auto-recovers monthly
"""

import os, sys, json, time, logging, argparse
from pathlib import Path
from typing import Any

try:
    import httpx
except ImportError:
    print("错误: 缺少 httpx 依赖。请运行: pip3 install httpx", file=sys.stderr)
    sys.exit(1)

logging.basicConfig(
    level=logging.WARNING,
    format="%(asctime)s [%(name)s] %(levelname)s: %(message)s",
)
logger = logging.getLogger("tavily")

API_BASE = "https://api.tavily.com"
STATE_DIR = Path.home() / ".tavily"
STATE_FILE = STATE_DIR / "state.json"


# ── Key Pool (same logic as router.py) ──────────────────────

def _load_state() -> dict:
    if STATE_FILE.exists():
        try:
            return json.loads(STATE_FILE.read_text("utf-8"))
        except Exception:
            pass
    return {}

def _save_state(state: dict):
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(state, ensure_ascii=False, indent=2), "utf-8")

def _current_month() -> str:
    return time.strftime("%Y-%m")

class KeyPool:
    def __init__(self, keys: list[str]):
        self.keys = keys
        self._idx = 0
        state = _load_state()
        self.exhausted: dict[str, dict] = state.get("exhausted", {})
        self.usage: dict[str, dict] = state.get("usage", {})
        for key in keys:
            if key not in self.usage:
                self.usage[key] = {"credits": 0, "requests": 0, "last_used": None}
        self._recover()

    def _recover(self):
        now = _current_month()
        for k in list(self.exhausted.keys()):
            if self.exhausted[k].get("month") != now:
                del self.exhausted[k]

    def next_key(self) -> str | None:
        self._recover()
        for _ in range(len(self.keys)):
            key = self.keys[self._idx % len(self.keys)]
            self._idx += 1
            if key not in self.exhausted:
                return key
        return None

    def mark_exhausted(self, key: str, reason: str = ""):
        self.exhausted[key] = {"month": _current_month(), "reason": reason, "ts": time.time()}
        self._persist()

    def record_usage(self, key: str, credits: int):
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
        _save_state({"exhausted": self.exhausted, "usage": self.usage})

    def summary(self) -> str:
        lines = [f"当前月份: {_current_month()}", f"总 key 数: {len(self.keys)}", f"可用: {self.available_count}", ""]
        for key in self.keys:
            rep = f"...{key[-6:]}" if len(key) > 6 else key
            status = "可用" if key not in self.exhausted else f"耗尽 ({self.exhausted[key].get('reason', '?')})"
            u = self.usage.get(key, {})
            lines.append(f"  {rep} | {status} | credits={u.get('credits', 0)} reqs={u.get('requests', 0)}")
        return "\n".join(lines)


# ── API Call ────────────────────────────────────────────────

def _tavily_request(endpoint: str, payload: dict[str, Any], pool: KeyPool) -> dict:
    for _ in range(len(pool.keys)):
        key = pool.next_key()
        if key is None:
            return {"error": "所有 Tavily API key 已耗尽，请次月重试或添加新 key"}

        headers = {"Authorization": f"Bearer {key}", "Content-Type": "application/json"}
        try:
            resp = httpx.post(f"{API_BASE}/{endpoint}", json=payload, headers=headers, timeout=120.0)
        except Exception as e:
            logger.warning(f"请求失败: {e}")
            continue

        if resp.status_code == 429:
            continue  # rate limit → next key
        if resp.status_code in (432, 433):
            reason = f"HTTP {resp.status_code}"
            try:
                reason = resp.json().get("detail", {}).get("error", reason)
            except Exception:
                pass
            pool.mark_exhausted(key, reason)
            continue
        if resp.status_code >= 400:
            return {"error": f"Tavily API HTTP {resp.status_code}", "detail": resp.text}

        try:
            body = resp.json()
            credits = body.get("usage", {}).get("credits", 1)
            pool.record_usage(key, credits)
            return body
        except Exception:
            return resp.json()

    return {"error": "所有 Tavily API key 已耗尽，请次月重试或添加新 key"}


# ── CLI ─────────────────────────────────────────────────────

def main():
    raw_keys = os.environ.get("TAVILY_API_KEYS", "")
    keys = [k.strip() for k in raw_keys.split(",") if k.strip()]
    if not keys:
        print("错误: 请设置环境变量 TAVILY_API_KEYS (逗号分隔多个 key)")
        sys.exit(1)

    pool = KeyPool(keys)

    parser = argparse.ArgumentParser(description="Tavily Web Search CLI")
    sub = parser.add_subparsers(dest="command", required=True)

    # search
    p_search = sub.add_parser("search", help="搜索网络")
    p_search.add_argument("query", help="搜索关键词")
    p_search.add_argument("--depth", choices=["basic", "advanced"], default="basic")
    p_search.add_argument("--topic", choices=["general", "news"], default="general")
    p_search.add_argument("--max-results", type=int, default=10)
    p_search.add_argument("--include-images", action="store_true")
    p_search.add_argument("--include-raw", action="store_true")
    p_search.add_argument("--time-range", choices=["day", "week", "month", "year"])
    p_search.add_argument("--include-domains")
    p_search.add_argument("--exclude-domains")

    # extract
    p_extract = sub.add_parser("extract", help="提取网页内容")
    p_extract.add_argument("urls", nargs="+")
    p_extract.add_argument("--depth", choices=["basic", "advanced"], default="basic")

    # crawl
    p_crawl = sub.add_parser("crawl", help="抓取网站")
    p_crawl.add_argument("url")
    p_crawl.add_argument("--max-depth", type=int, default=1)
    p_crawl.add_argument("--max-breadth", type=int, default=20)
    p_crawl.add_argument("--limit", type=int, default=50)
    p_crawl.add_argument("--instructions", default="")

    # map
    p_map = sub.add_parser("map", help="映射网站结构")
    p_map.add_argument("url")
    p_map.add_argument("--max-depth", type=int, default=1)
    p_map.add_argument("--max-breadth", type=int, default=20)
    p_map.add_argument("--limit", type=int, default=50)

    # status
    sub.add_parser("status", help="查看 key 状态")

    args = parser.parse_args()

    if args.command == "status":
        print(pool.summary())
        return

    if args.command == "search":
        payload: dict[str, Any] = {
            "query": args.query,
            "search_depth": args.depth,
            "topic": args.topic,
            "max_results": args.max_results,
            "include_images": args.include_images,
            "include_raw_content": args.include_raw,
        }
        if args.time_range:
            payload["time_range"] = args.time_range
        if args.include_domains:
            payload["include_domains"] = [d.strip() for d in args.include_domains.split(",")]
        if args.exclude_domains:
            payload["exclude_domains"] = [d.strip() for d in args.exclude_domains.split(",")]

        result = _tavily_request("search", payload, pool)

    elif args.command == "extract":
        result = _tavily_request("extract", {
            "urls": args.urls,
            "extract_depth": args.depth,
        }, pool)

    elif args.command == "crawl":
        payload = {
            "url": args.url,
            "max_depth": args.max_depth,
            "max_breadth": args.max_breadth,
            "limit": args.limit,
        }
        if args.instructions:
            payload["instructions"] = args.instructions
        result = _tavily_request("crawl", payload, pool)

    elif args.command == "map":
        result = _tavily_request("map", {
            "url": args.url,
            "max_depth": args.max_depth,
            "max_breadth": args.max_breadth,
            "limit": args.limit,
        }, pool)

    else:
        parser.print_help()
        return

    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
