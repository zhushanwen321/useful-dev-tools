"""Claude Code Tool Installer - utility functions."""

import json
import os
import shutil
import subprocess
from datetime import datetime
from pathlib import Path
from typing import Any, Optional


def resolve_path(path: Path) -> Path:
    """Resolve a path, handling relative symlinks."""
    path = Path(path)
    return path.parent.resolve() / path.name


def is_our_symlink(target: Path, source: Path) -> bool:
    """Check if target is a symlink pointing to source.

    Uses resolved path comparison to handle both absolute and relative symlinks.
    Also checks if the raw readlink value matches str(source) as a fast path.
    """
    target = Path(target)
    source = Path(source)
    if not target.is_symlink():
        return False
    current = os.readlink(target)
    # Fast path: exact string match
    if current == str(source):
        return True
    # Resolve both sides for reliable comparison
    resolved_src = resolve_path(source)
    if not current.startswith("/"):
        resolved_current = (target.parent / current).resolve()
    else:
        resolved_current = Path(current).resolve()
    return resolved_current == resolved_src


def backup_file(path: Path, backup_dir: Path) -> Optional[Path]:
    """Backup a file, return backup path or None.

    Skips symlinks to prevent moving files from outside the expected tree.
    """
    path = Path(path)
    if not path.exists():
        return None
    # Safety: don't move symlinks (could point to sensitive files)
    if path.is_symlink():
        return None
    backup_dir = Path(backup_dir)
    backup_dir.mkdir(parents=True, exist_ok=True)
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup = backup_dir / f"{path.name}_{ts}"
    shutil.move(str(path), str(backup))
    return backup


def ensure_parent(path: Path) -> None:
    """Ensure parent directory exists, removing any parent that is a symlink."""
    parent = path.parent
    if parent.is_symlink():
        parent.unlink()
    parent.mkdir(parents=True, exist_ok=True)


def create_symlink(source: Path, target: Path) -> None:
    """Create a symlink target -> source atomically via tmp+rename.

    This avoids the TOCTOU race window between unlink() and symlink_to().
    """
    target = Path(target)
    source = Path(source)
    ensure_parent(target)
    # Atomic symlink: create as temp, then rename over target
    tmp = target.with_suffix(target.suffix + "..tmp")
    try:
        tmp.unlink(missing_ok=True)
        tmp.symlink_to(source)
        os.rename(str(tmp), str(target))
    except BaseException:
        tmp.unlink(missing_ok=True)
        raise


def cmd_exists(name: str) -> bool:
    """Check if a command is available in PATH."""
    return shutil.which(name) is not None


def run_cmd(cmd: list[str], **kwargs: Any) -> subprocess.CompletedProcess:
    """Run a command, return CompletedProcess."""
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


# ── JSON helpers ──────────────────────────────────────────────

def load_json(path: Path) -> dict:
    """Load JSON file, return empty dict if not found."""
    path = Path(path)
    if not path.exists():
        return {}
    with open(path) as f:
        return json.load(f)


def save_json(path: Path, data: dict, perm: int = 0o600) -> None:
    """Save JSON file with permissions."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    path.chmod(perm)


def update_settings(settings_path: Path, updater: callable) -> bool:
    """Load settings.json, apply updater function, save back.
    updater receives the dict and should modify it in-place.
    Returns True on success."""
    settings_path = Path(settings_path)
    data = load_json(settings_path)
    updater(data)
    save_json(settings_path, data)
    return True


# ── Logging ─────────────────────────────────────────────────────

def log_action(home_dir: Path, action: str, details: str) -> None:
    """Append an action to the install log."""
    log_file = home_dir / "bak" / "install.log"
    log_file.parent.mkdir(parents=True, exist_ok=True)
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with open(log_file, "a") as f:
        f.write(f"[{ts}] {action}: {details}\n")
