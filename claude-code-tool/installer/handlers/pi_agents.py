"""Pi Agents — map agents/*/agent.md to ~/.pi/agent/agents/*.md."""

from pathlib import Path
from installer import ui
from installer.utils import backup_file, create_symlink, is_our_symlink
from installer.engine import EXCLUDE_PATTERNS

TITLE = "pi Agents"
RISK = "low"
TARGETS = ["pi"]


def configure(target: Path, script_dir: Path) -> bool:
    src_dir = script_dir / "agents"
    if not src_dir.is_dir():
        return True
    dest_dir = target / "agents"
    dest_dir.mkdir(parents=True, exist_ok=True)
    for child in sorted(src_dir.iterdir()):
        if child.name in EXCLUDE_PATTERNS:
            continue
        agent_md = child / "agent.md"
        if not child.is_dir() or not agent_md.exists():
            continue
        dest = dest_dir / f"{child.name}.md"
        if dest.is_symlink() and is_our_symlink(dest, agent_md):
            continue
        if dest.exists() and not dest.is_symlink():
            backup_file(dest, target / "bak")
        create_symlink(agent_md, dest)
        ui.success(f"链接: {child.name}.md")
    return True


def unconfigure(target: Path, script_dir: Path = None) -> None:
    src_dir = (script_dir or Path()) / "agents"
    if not src_dir.is_dir():
        return
    for child in sorted(src_dir.iterdir()):
        agent_md = child / "agent.md"
        dest = target / "agents" / f"{child.name}.md"
        if dest.is_symlink() and is_our_symlink(dest, agent_md):
            dest.unlink()
            ui.info(f"移除: {child.name}")
