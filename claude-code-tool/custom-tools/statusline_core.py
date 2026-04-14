#!/usr/bin/env python3
"""Claude Code Statusline — 渲染器

读缓存 + 本地计算 + 渲染输出。不做 HTTP 调用。
TTL 过期时后台启动 statusline_updater.py 更新缓存。
"""

import json
import os
import subprocess
import sys
import time
from pathlib import Path


# ═══════════════════════════════════════════════════════════════
# ANSI Colors
# ═══════════════════════════════════════════════════════════════
class C:
    D = '\033[0m'
    R = '\033[31m'; G = '\033[32m'; Y = '\033[33m'
    B = '\033[34m'; M = '\033[35m'; W = '\033[37m'
    BG = '\033[1;32m'; BY = '\033[1;33m'; BB = '\033[1;34m'
    BC = '\033[1;36m'; BM = '\033[1;35m'
    DG = '\033[38;5;65m'; CY = '\033[38;5;180m'
    WH = '\033[38;5;254m'; GM = '\033[38;5;245m'
    BGB = '\033[38;5;117m'; BGC = '\033[38;5;152m'
    BGG = '\033[1;38;5;150m'
    SEP = f'\033[38;5;245m│\033[0m'
    NSEP = f'\033[38;5;245m·\033[0m'


# ═══════════════════════════════════════════════════════════════
# Cache
# ═══════════════════════════════════════════════════════════════
CACHE_FILE = Path.home() / ".claude" / "statusline_cache.json"
CACHE_TTL = 120  # 秒


def read_cache() -> dict:
    try:
        data = json.loads(CACHE_FILE.read_text("utf-8"))
        if time.time() - data.get("updated_at", 0) > CACHE_TTL:
            _trigger_update()
        return data
    except (OSError, json.JSONDecodeError):
        _trigger_update()
        return {}


def _trigger_update():
    """后台启动 updater，不阻塞当前渲染"""
    updater = Path(__file__).parent / "statusline_updater.py"
    try:
        subprocess.Popen(
            [sys.executable, str(updater)],
            start_new_session=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except OSError:
        pass


# ═══════════════════════════════════════════════════════════════
# Utility Functions
# ═══════════════════════════════════════════════════════════════
def build_bar(pct: int, width: int = 8) -> str:
    pct = max(0, min(100, pct))
    filled = pct * width // 100
    if pct >= 80: fill_bg = '\033[48;5;196m'
    elif pct >= 60: fill_bg = '\033[48;5;208m'
    elif pct >= 40: fill_bg = '\033[48;5;220m'
    else: fill_bg = '\033[48;5;114m'
    empty_bg = '\033[48;5;239m'
    return f'{fill_bg}{" " * filled}{empty_bg}{" " * (width - filled)}{C.D}'


def format_duration(ms: int) -> str:
    s = ms // 1000
    h, rem = divmod(s, 3600)
    m, sec = divmod(rem, 60)
    if h > 0: return f'{h}h{m:02d}m'
    if m > 0: return f'{m}m{sec:02d}s'
    return f'{sec}s'


# ═══════════════════════════════════════════════════════════════
# Token Speed — 增量缓存
# ═══════════════════════════════════════════════════════════════
TOKEN_DIR = Path.home() / ".claude" / "token-stats"


def _today_str() -> str:
    return time.strftime("%Y-%m-%d")


def _model_filename(model: str) -> str:
    return model.replace("/", "_").replace(" ", "_")


def update_token_speed(output_tokens: int, api_duration_ms: int,
                       model: str) -> tuple[int, int, int, int]:
    """返回 (current_speed, today_avg, 7d_avg, 30d_avg)"""
    current_speed = 0
    if api_duration_ms and api_duration_ms > 0:
        current_speed = int(output_tokens / api_duration_ms * 1000)

    if not model or current_speed <= 0:
        return current_speed, 0, 0, 0

    today = _today_str()
    day_dir = TOKEN_DIR / today
    day_dir.mkdir(parents=True, exist_ok=True)
    fname = _model_filename(model)
    day_file = day_dir / f"{fname}.csv"
    with open(day_file, "a") as f:
        f.write(f"{int(time.time())},{output_tokens},{api_duration_ms},{current_speed}\n")

    summary_file = TOKEN_DIR / f"summary_{fname}.json"
    summary = _load_json(summary_file)

    if summary and summary.get("cache_date") == today:
        for key in ("today", "seven_day", "thirty_day"):
            summary[key]["sum"] += current_speed
            summary[key]["count"] += 1
    else:
        summary = _rebuild_summary(fname)

    _save_json(summary_file, summary)

    def _avg(k: str) -> int:
        d = summary.get(k, {})
        return int(d["sum"] / d["count"]) if d.get("count", 0) > 0 else 0

    return current_speed, _avg("today"), _avg("seven_day"), _avg("thirty_day")


def _rebuild_summary(fname: str) -> dict:
    from datetime import datetime, timedelta
    today = _today_str()
    today_sum = today_count = seven_sum = seven_count = 0
    thirty_sum = thirty_count = 0

    for i in range(30):
        d = (datetime.now() - timedelta(days=i)).strftime("%Y-%m-%d")
        day_file = TOKEN_DIR / d / f"{fname}.csv"
        if not day_file.exists():
            continue
        ds, dc = _sum_csv(day_file)
        thirty_sum += ds; thirty_count += dc
        if i < 7: seven_sum += ds; seven_count += dc
        if d == today: today_sum = ds; today_count = dc

    return {
        "cache_date": today,
        "today": {"sum": today_sum, "count": today_count},
        "seven_day": {"sum": seven_sum, "count": seven_count},
        "thirty_day": {"sum": thirty_sum, "count": thirty_count},
    }


def _sum_csv(path: Path) -> tuple[int, int]:
    total = count = 0
    try:
        for line in path.read_text().strip().splitlines():
            parts = line.split(",")
            if len(parts) >= 4:
                total += int(parts[3]); count += 1
    except (OSError, ValueError):
        pass
    return total, count


def _load_json(path: Path) -> dict | None:
    try:
        return json.loads(path.read_text("utf-8"))
    except (OSError, json.JSONDecodeError):
        return None


def _save_json(path: Path, data: dict):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), "utf-8")


# ═══════════════════════════════════════════════════════════════
# Session Info（本地文件读写）
# ═══════════════════════════════════════════════════════════════
def get_session_info(transcript_path: str | None,
                     session_id: str | None) -> dict:
    now = int(time.time())
    info = {"start": "", "last_llm": "", "last_resp": ""}

    if transcript_path:
        try:
            st = os.stat(transcript_path)
            ts = st.st_birthtime if hasattr(st, 'st_birthtime') else st.st_ctime
            info["start"] = time.strftime("%H:%M:%S", time.localtime(ts))
        except OSError:
            pass

    if session_id:
        state_file = Path(f"/tmp/claude-statusline-{session_id}.time")
        if state_file.exists():
            try:
                last_ts = int(state_file.read_text().strip())
                elapsed = now - last_ts
                if elapsed < 60: info["last_llm"] = f"{elapsed}s"
                else: info["last_llm"] = f"{elapsed // 60}m{elapsed % 60}s"
                info["last_resp"] = time.strftime("%H:%M:%S", time.localtime(last_ts))
            except (OSError, ValueError):
                pass
        state_file.write_text(str(now))

    return info


# ═══════════════════════════════════════════════════════════════
# Formatting — 读预处理后的缓存数据，直接格式化
# ═══════════════════════════════════════════════════════════════
def _fmt_zhipu(z: dict | None) -> str:
    if not z:
        return ""
    label = z.get("label", "Z.ai")
    tp = z.get("tokens_pct", 0)
    s = f"{C.DG}{label}{C.D} {build_bar(tp, 6)} {C.WH}{tp}%{C.D}"

    t_pct = z.get("time_pct", 0)
    if t_pct:
        tc = z.get("time_current", 0)
        s += f" {C.NSEP} {C.DG}mcp{C.D} {build_bar(t_pct, 6)} {C.WH}{t_pct}%{C.D} {C.GM}({tc}){C.D}"

    rt = z.get("reset_time", "")
    if rt:
        s += f" {C.NSEP} {C.DG}reset{C.D} {C.Y}{rt}{C.D}"

    return s


def _fmt_tavily(t: dict | None) -> str:
    if not t:
        return ""
    avail = t.get("available", 0)
    total = t.get("total", 0)
    parts = [f"{C.DG}Tavily{C.D} {C.BGG}{avail}/{total}{C.D}"]

    plan_usage = t.get("plan_usage", 0)
    plan_limit = t.get("plan_limit", 0)
    if plan_limit > 0:
        pct = int(plan_usage / plan_limit * 100)
        parts.append(f"{C.DG}plan{C.D} {build_bar(pct, 6)} {C.WH}{pct}%{C.D} {C.NSEP} {C.WH}{plan_usage}/{plan_limit}{C.D}")

    key_usage = t.get("key_usage", 0)
    key_limit = t.get("key_limit", 0)
    if key_limit > 0:
        parts.append(f"{C.DG}key{C.D} {C.WH}{key_usage}/{key_limit}{C.D}")

    credits = t.get("credits", 0)
    requests = t.get("requests", 0)
    if credits > 0 or requests > 0:
        parts.append(f"{C.DG}used{C.D} {C.Y}{credits}{C.D}cr {C.NSEP} {C.DG}req{C.D} {C.BC}{requests}{C.D}")

    return f" {C.SEP} ".join(parts)


# ═══════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════
def main():
    data = json.load(sys.stdin)
    ws = data.get("workspace", {})
    cw = data.get("context_window", {})
    cost = data.get("cost", {})
    wt = data.get("worktree", {})

    project_dir = ws.get("project_dir", "")
    current_dir = ws.get("current_dir") or data.get("cwd", "")
    model = data.get("model", {}).get("display_name", "Unknown")
    used_pct = cw.get("used_percentage") or 0
    agent_name = data.get("agent", {}).get("name", "")
    worktree_name = wt.get("name", "")
    worktree_branch = wt.get("branch", "")
    total_dur = cost.get("total_duration_ms") or 0
    total_api_dur = cost.get("total_api_duration_ms") or 0
    output_tokens = cw.get("total_output_tokens") or 0
    session_id = data.get("session_id", "")
    transcript_path = data.get("transcript_path", "")

    # --- 读缓存（无 HTTP，纯文件读取）---
    cache = read_cache()
    zhipu = cache.get("zhipu")
    tavily = cache.get("tavily")

    # --- 本地计算 ---
    cur_spd, day_avg, d7_avg, d30_avg = update_token_speed(
        output_tokens, total_api_dur, model)
    sess = get_session_info(transcript_path, session_id)

    dir_display = _dir_display(project_dir, current_dir)
    buf = 16
    usable = 100 - buf
    load_pct = min(int(used_pct * 100 / usable), 100) if usable > 0 else 100

    git_branch = _get_git_branch(current_dir, worktree_name, worktree_branch)

    # --- 格式化输出 ---
    identity = _build_identity(dir_display, worktree_name, worktree_branch,
                               git_branch, agent_name, model)

    ctx = f"{C.DG}ctx{C.D} {build_bar(used_pct, 8)} {C.WH}{used_pct}%{C.D}"
    load = f"{C.DG}load{C.D} {build_bar(load_pct, 8)} {C.WH}{load_pct}%{C.D}"
    metrics = f"{ctx} {C.NSEP} {load}"
    zhipu_str = _fmt_zhipu(zhipu)
    if zhipu_str:
        metrics += f" {C.SEP} {zhipu_str}"

    tavily_line = _fmt_tavily(tavily)
    line3 = _build_line3(cur_spd, day_avg, d7_avg, d30_avg, sess,
                         total_dur, session_id)

    lines = [l for l in [identity, metrics, tavily_line, line3] if l]
    print("\n".join(lines))


def _dir_display(project_dir: str, current_dir: str) -> str:
    if not current_dir:
        return ""
    if project_dir:
        pname = os.path.basename(project_dir)
        if current_dir == project_dir:
            return pname
        rel = current_dir.removeprefix(project_dir + "/")
        return f"{pname}/{rel}" if rel != current_dir else os.path.basename(current_dir)
    return os.path.basename(current_dir)


def _get_git_branch(current_dir: str, wt_name: str, wt_branch: str) -> str:
    if wt_name or wt_branch or not current_dir:
        return ""
    try:
        r = subprocess.run(["git", "-C", current_dir, "branch", "--show-current"],
                           capture_output=True, text=True, timeout=2)
        if r.returncode == 0 and r.stdout.strip():
            return r.stdout.strip()
        r = subprocess.run(["git", "-C", current_dir, "rev-parse", "--short", "HEAD"],
                           capture_output=True, text=True, timeout=2)
        return r.stdout.strip() if r.returncode == 0 else ""
    except (subprocess.TimeoutExpired, OSError):
        return ""


def _build_identity(dir_disp, wt_name, wt_branch, git_br, agent, model) -> str:
    parts = []
    if dir_disp: parts.append(f"{C.BG}{dir_disp}{C.D}")
    br = wt_name or wt_branch or git_br
    if br: parts.append(f"⎇ {C.BC}{br}{C.D}")
    if agent: parts.append(f"{C.BY}{agent}{C.D}")
    identity = f" {C.NSEP} ".join(parts)
    if model: identity += f" {C.SEP} {C.BGB}{model}{C.D}"
    return identity


def _build_line3(cur_spd, day_avg, d7, d30, sess, total_dur, session_id) -> str:
    parts = []
    sp = []
    if cur_spd > 0: sp.append(f"{C.G}{cur_spd}{C.D}t/s")
    if day_avg > 0: sp.append(f"day {C.BC}{day_avg}{C.D}")
    if d7 > 0: sp.append(f"7d {C.CY}{d7}{C.D}")
    if d30 > 0: sp.append(f"30d {C.M}{d30}{C.D}")
    if sp: parts.append(f" {C.NSEP} ".join(sp))

    tp = []
    if sess["start"]: tp.append(f"{C.DG}from{C.D} {C.BC}{sess['start']}{C.D}")
    if total_dur > 0: tp.append(f"{C.DG}run{C.D} {C.G}{format_duration(total_dur)}{C.D}")
    if sess["last_llm"]:
        t = f"{C.DG}last{C.D} {C.Y}{sess['last_llm']}{C.D}"
        if sess["last_resp"]:
            t += f" {C.NSEP} {C.DG}resp{C.D} {C.BC}{sess['last_resp']}{C.D}"
        tp.append(t)
    if tp: parts.append(f" {C.NSEP} ".join(tp))
    if session_id: parts.append(f"{C.GM}{session_id}{C.D}")

    return f" {C.SEP} ".join(parts)


if __name__ == "__main__":
    main()
