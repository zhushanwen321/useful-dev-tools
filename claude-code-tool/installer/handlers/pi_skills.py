"""Pi Skills — symlink skills/ to ~/.pi/agent/skills/."""

from pathlib import Path
from installer import ui
from installer.utils import backup_file, create_symlink, is_our_symlink
from installer.engine import EXCLUDE_PATTERNS

TITLE = "pi Skills"
RISK = "low"
TARGETS = ["pi"]


def configure(target: Path, script_dir: Path) -> bool:
    src_dir = script_dir / "skills"
    if not src_dir.is_dir():
        return True
    dest_dir = target / "skills"
    dest_dir.mkdir(parents=True, exist_ok=True)
    for child in sorted(src_dir.iterdir()):
        if child.name in EXCLUDE_PATTERNS or not child.exists():
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
    src_dir = (script_dir or Path()) / "skills"
    if not src_dir.is_dir():
        return
    for child in sorted(src_dir.iterdir()):
        dest = target / "skills" / child.name
        if dest.is_symlink() and is_our_symlink(dest, child):
            dest.unlink()
            ui.info(f"移除: {child.name}")
