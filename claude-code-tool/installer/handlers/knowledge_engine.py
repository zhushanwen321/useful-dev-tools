"""Knowledge engine — bun deps, hooks, crontab, marker file."""

import subprocess
from pathlib import Path

from installer import ui
from installer.utils import run_cmd, load_json, save_json

TITLE = "知识引擎"
RISK = "high"
TARGETS = [".claude"]
ENGINE_MARKER = ".engine_cli_path"


def configure(target: Path, script_dir: Path) -> bool:
    engine_dir = script_dir / "knowledge-engine"
    cli_path = engine_dir / "src" / "cli.ts"
    if not cli_path.exists():
        ui.warn("知识引擎源码不存在，跳过")
        return False

    result = run_cmd(["bun", "install", "--frozen-lockfile"], cwd=str(engine_dir))
    if result.returncode != 0:
        result = run_cmd(["bun", "install", "--no-save"], cwd=str(engine_dir))
        if result.returncode != 0:
            ui.error("知识引擎依赖安装失败")
            return False

    knowledge_dir = target / "knowledge"
    knowledge_dir.mkdir(parents=True, exist_ok=True)
    config_path = knowledge_dir / "config.json"
    if not config_path.exists():
        save_json(config_path, {
            "categories": ["architecture", "patterns", "domain", "troubleshooting"],
            "consolidateThreshold": 3,
            "excludePatterns": ["**/*.lock", "**/node_modules/**", ".env*"],
        }, perm=0o644)

    cli_abs = cli_path.resolve()
    record_cmd = f'bun "{cli_abs}" record'
    process_cmd = f'bun "{cli_abs}" process'
    inject_cmd = f'bun "{cli_abs}" inject-index'

    settings = target / "settings.json"
    data = load_json(settings) if settings.exists() else {}
    hooks = data.setdefault("hooks", {})

    post = [e for e in hooks.get("PostToolUse", [])
            if not any(h.get("command") == record_cmd for h in e.get("hooks", []))]
    post.append({"matcher": "Write|Edit", "hooks": [
        {"type": "command", "command": record_cmd, "async": True, "timeout": 5}]})
    hooks["PostToolUse"] = post

    stop = [e for e in hooks.get("Stop", [])
            if not any(h.get("command") == process_cmd for h in e.get("hooks", []))]
    stop.append({"hooks": [
        {"type": "command", "command": process_cmd, "async": True, "timeout": 120}]})
    hooks["Stop"] = stop

    start = [e for e in hooks.get("SessionStart", [])
             if not any(h.get("command") == inject_cmd for h in e.get("hooks", []))]
    start.append({"hooks": [
        {"type": "command", "command": inject_cmd, "timeout": 5}]})
    hooks["SessionStart"] = start

    save_json(settings, data)
    ui.success("知识引擎 hooks 已配置")
    (knowledge_dir / ENGINE_MARKER).write_text(str(cli_abs))
    _setup_crontab(engine_dir)
    return True


def _setup_crontab(engine_dir: Path) -> None:
    cron_script = engine_dir / "scripts" / "cron-maintenance.sh"
    marker = "# knowledge-engine-cron"
    entry = f"0 23 * * * {cron_script} >> ~/.claude/knowledge/maintenance.log 2>&1 {marker}"
    try:
        result = run_cmd(["crontab", "-l"])
        existing = result.stdout if result.returncode == 0 else ""
        lines = [l for l in existing.splitlines() if marker not in l]
        lines.append(entry)
        r = subprocess.run(["crontab", "-"], input="\n".join(lines) + "\n", text=True)
        if r.returncode == 0:
            ui.success("crontab 已配置")
        else:
            ui.warn(f"crontab 写入失败 (exit {r.returncode})")
    except Exception:
        ui.warn("crontab 配置失败")


def unconfigure(target: Path, script_dir: Path = None) -> None:
    settings = target / "settings.json"
    if not settings.exists():
        return

    marker_path = target / "knowledge" / ENGINE_MARKER
    if marker_path.is_file():
        cli_abs_str = marker_path.read_text().strip()
        cli_abs = Path(cli_abs_str)
        cmds = {f'bun "{cli_abs}" {c}' for c in ("record", "process", "inject-index")}
        data = load_json(settings)
        for hook_type in ("PostToolUse", "Stop", "SessionStart"):
            entries = data.get("hooks", {}).get(hook_type, [])
            cleaned = []
            for e in entries:
                hs = [h for h in e.get("hooks", []) if h.get("command") not in cmds]
                if hs:
                    e["hooks"] = hs
                    cleaned.append(e)
            data.setdefault("hooks", {})[hook_type] = cleaned
        save_json(settings, data)
        marker_path.unlink(missing_ok=True)
    else:
        data = load_json(settings)
        for hook_type in ("PostToolUse", "Stop", "SessionStart"):
            entries = data.get("hooks", {}).get(hook_type, [])
            data.setdefault("hooks", {})[hook_type] = [e for e in entries if e.get("hooks")]
        save_json(settings, data)

    marker = "knowledge-engine-cron"
    try:
        result = run_cmd(["crontab", "-l"])
        if result.returncode == 0 and marker in result.stdout:
            lines = [l for l in result.stdout.splitlines() if marker not in l]
            subprocess.run(["crontab", "-"], input="\n".join(lines) + "\n", text=True)
    except Exception:
        pass
