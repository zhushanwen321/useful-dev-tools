"""Skill injection hook — adds PreToolUse hook for Skill tool."""

from pathlib import Path
from installer.utils import load_json, save_json

TITLE = "Skill 注入 Hook"
RISK = "medium"
TARGETS = [".claude"]

HOOK_CMD = 'bash "$HOME/.claude/hooks/skill-inject.sh"'


def configure(target: Path, script_dir: Path) -> bool:
    settings = target / "settings.json"
    data = load_json(settings) if settings.exists() else {}

    hooks = data.setdefault("hooks", {})
    pre = hooks.setdefault("PreToolUse", [])

    for entry in pre:
        if entry.get("matcher") == "Skill":
            for h in entry.get("hooks", []):
                if h.get("command") == HOOK_CMD:
                    return True

    pre = [e for e in pre if e.get("matcher") != "Skill"]
    pre.append({"matcher": "Skill",
                "hooks": [{"type": "command", "command": HOOK_CMD, "timeout": 5}]})
    hooks["PreToolUse"] = pre
    save_json(settings, data)
    return True


def unconfigure(target: Path, script_dir: Path = None) -> None:
    settings = target / "settings.json"
    if not settings.exists():
        return
    data = load_json(settings)
    pre = data.get("hooks", {}).get("PreToolUse", [])
    pre = [e for e in pre
           if not (e.get("matcher") == "Skill"
                   and any(h.get("command") == HOOK_CMD for h in e.get("hooks", [])))]
    pre = [e for e in pre if e.get("hooks")]
    data.setdefault("hooks", {})["PreToolUse"] = pre
    save_json(settings, data)
