"""Statusline configuration — adds statusLine to settings.json."""

from pathlib import Path
from installer.utils import load_json, save_json

TITLE = "状态栏"
RISK = "low"
TARGETS = [".claude", ".opencode"]


def configure(target: Path, script_dir: Path) -> bool:
    settings = target / "settings.json"
    command = f'"{target}/custom-tools/statusline.sh"'

    if settings.exists():
        data = load_json(settings)
        if data.get("statusLine", {}).get("command", "") == command:
            return True
    else:
        data = {}

    data["statusLine"] = {"type": "command", "command": command}
    save_json(settings, data)
    return True


def unconfigure(target: Path, script_dir: Path = None) -> None:
    settings = target / "settings.json"
    if not settings.exists():
        return
    data = load_json(settings)
    if "statusLine" in data:
        del data["statusLine"]
        save_json(settings, data)
