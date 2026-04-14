#!/usr/bin/env python3
"""Statusline Cache Updater

后台运行：并行获取 zhipu/tavily 数据并写入缓存。
成功的部分覆盖缓存，失败的保留旧数据。
"""

import json
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import URLError

CACHE_FILE = Path.home() / ".claude" / "statusline_cache.json"


# ═══════════════════════════════════════════════════════════════
# IO
# ═══════════════════════════════════════════════════════════════
def load_cache() -> dict:
    try:
        return json.loads(CACHE_FILE.read_text("utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}


def save_cache(cache: dict):
    """原子写入：先写临时文件再 rename，防止 statusline 读到半写数据"""
    import os, tempfile
    CACHE_FILE.parent.mkdir(parents=True, exist_ok=True)
    content = json.dumps(cache, ensure_ascii=False, indent=2)
    fd, tmp = tempfile.mkstemp(dir=str(CACHE_FILE.parent), suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(content)
        os.rename(tmp, str(CACHE_FILE))
    except OSError:
        os.unlink(tmp) if os.path.exists(tmp) else None


# ═══════════════════════════════════════════════════════════════
# Zhipu — HTTP 获取 + 处理
# ═══════════════════════════════════════════════════════════════
def fetch_zhipu() -> dict | None:
    token_file = Path.home() / ".claude" / ".zhipu_auth_token"
    if not token_file.exists():
        return None
    token = token_file.read_text().strip()
    if not token:
        return None
    try:
        req = Request(
            "https://bigmodel.cn/api/monitor/usage/quota/limit",
            headers={
                "accept": "application/json, text/plain, */*",
                "authorization": token,
                "bigmodel-organization": "org-8F82302F73594F44B2bdCc5A57BCfD1f",
                "bigmodel-project": "proj_8E86D38C8211410Baa4852408071D1F2",
                "referer": "https://bigmodel.cn/usercenter/glm-coding/usage",
                "user-agent": "Mozilla/5.0",
            },
        )
        with urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read())
        return _process_zhipu(data)
    except (URLError, OSError, json.JSONDecodeError):
        return None


def _process_zhipu(data: dict) -> dict | None:
    if not data.get("success"):
        return None
    d = data["data"]
    level = d.get("level", "")
    label = f"Z.ai-{level}" if level else "Z.ai"

    tokens_pct = reset_ms = 0
    time_pct = time_current = 0

    for lim in d.get("limits", []):
        lt = lim.get("type", "")
        if lt == "TOKENS_LIMIT":
            tokens_pct = lim.get("percentage", 0)
            v = lim.get("nextResetTime")
            if v:
                reset_ms = int(v)
        elif lt == "TIME_LIMIT":
            time_pct = lim.get("percentage", 0)
            time_current = lim.get("currentValue", 0)
            v = lim.get("nextResetTime")
            if v and not reset_ms:
                reset_ms = int(v)

    reset_time = ""
    if reset_ms:
        rem = reset_ms // 1000 - int(time.time())
        if rem > 0:
            rd, rr = divmod(rem, 86400)
            rh, rm = divmod(rr, 3600)
            if rd > 0:
                reset_time = f"{rd}d{rh}h"
            elif rh > 0:
                reset_time = f"{rh}h{rm // 60}m"
            else:
                reset_time = f"{rm // 60}m"

    return {
        "label": label,
        "tokens_pct": tokens_pct,
        "time_pct": time_pct,
        "time_current": time_current,
        "reset_time": reset_time,
    }


# ═══════════════════════════════════════════════════════════════
# Tavily — 读 state.json，叠加所有 key 的用量
# ═══════════════════════════════════════════════════════════════
def fetch_tavily() -> dict | None:
    state_file = Path.home() / ".tavily" / "state.json"
    try:
        data = json.loads(state_file.read_text("utf-8"))
    except (OSError, json.JSONDecodeError):
        return None

    if not data or not data.get("usage"):
        return None

    total = len(data["usage"])
    exhausted = len(data.get("exhausted", {}))
    credits = sum(v.get("credits", 0) for v in data["usage"].values())
    requests = sum(v.get("requests", 0) for v in data["usage"].values())

    # 叠加所有 key 的 usage（不同 key 可能属于不同账户）
    api = data.get("api_usage", {})
    plan_usage = plan_limit = key_usage = key_limit = 0
    plan_name = ""
    for v in api.values():
        plan_usage += v.get("plan_usage") or 0
        plan_limit += v.get("plan_limit") or 0
        key_usage += v.get("key_usage") or 0
        key_limit += v.get("key_limit") or 0
        if not plan_name:
            plan_name = v.get("plan_name", "")

    return {
        "available": total - exhausted,
        "total": total,
        "plan_usage": plan_usage,
        "plan_limit": plan_limit,
        "plan_name": plan_name,
        "key_usage": key_usage,
        "key_limit": key_limit,
        "credits": credits,
        "requests": requests,
    }


# ═══════════════════════════════════════════════════════════════
# Main — partial update（成功覆盖，失败保留旧数据）
# ═══════════════════════════════════════════════════════════════
def main():
    old = load_cache()
    new = {"updated_at": time.time()}

    with ThreadPoolExecutor(max_workers=2) as pool:
        f_zhipu = pool.submit(fetch_zhipu)
        f_tavily = pool.submit(fetch_tavily)

    zhipu = f_zhipu.result()
    tavily = f_tavily.result()

    new["zhipu"] = zhipu if zhipu is not None else old.get("zhipu")
    new["tavily"] = tavily if tavily is not None else old.get("tavily")

    save_cache(new)


if __name__ == "__main__":
    main()
