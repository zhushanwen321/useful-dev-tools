"""Pi Statusline — symlink custom-tools/pi-statusline/ to ~/.pi/agent/extensions/statusline/."""

from pathlib import Path
from installer import ui
from installer.utils import backup_file, create_symlink, is_our_symlink

TITLE = "pi 状态栏"
RISK = "low"
TARGETS = ["pi"]


def configure(target: Path, script_dir: Path) -> bool:
    src_dir = script_dir / "custom-tools" / "pi-statusline"
    if not src_dir.is_dir():
        return True
    dest_dir = target / "extensions" / "statusline"
    dest_dir.mkdir(parents=True, exist_ok=True)
    for child in sorted(src_dir.iterdir()):
        if not child.is_file():
            continue
        dest = dest_dir / child.name
        if dest.is_symlink() and is_our_symlink(dest, child):
            continue
        if dest.exists() and not dest.is_symlink():
            backup_file(dest, target / "bak")
        create_symlink(child, dest)
        ui.success(f"链接: {child.name}")
    return True


def unconfigure(target: Path, script_dir: Path = None) -> None:
    src_dir = (script_dir or Path()) / "custom-tools" / "pi-statusline"
    dest_dir = target / "extensions" / "statusline"
    if not src_dir.is_dir() or not dest_dir.is_dir():
        return
    for child in sorted(src_dir.iterdir()):
        dest = dest_dir / child.name
        if dest.is_symlink() and is_our_symlink(dest, child):
            dest.unlink()
            ui.info(f"移除: {child.name}")
