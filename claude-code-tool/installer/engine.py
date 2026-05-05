"""通用执行引擎：plan → execute → undo。"""

import json
import shutil
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Optional

from . import ui
from .utils import backup_file, create_symlink, is_our_symlink, load_json, save_json

EXCLUDE_PATTERNS = {"__pycache__", ".DS_Store", ".git"}


class UndoStack:
    def __init__(self):
        self._items: list[tuple[str, callable]] = []

    def push(self, description: str, undo_fn: callable) -> None:
        self._items.append((description, undo_fn))

    def rollback(self) -> int:
        count = 0
        for desc, undo_fn in reversed(self._items):
            try:
                undo_fn()
                ui.info(f"  ↩ 回滚: {desc}")
                count += 1
            except Exception as e:
                ui.warn(f"  ↩ 回滚失败: {desc} ({e})")
        self._items.clear()
        return count

    def clear(self) -> None:
        self._items.clear()


@dataclass
class Action:
    description: str

@dataclass
class SymlinkAction(Action):
    source: Path
    target: Path

@dataclass
class BackupAction(Action):
    original: Path
    backup: Path

@dataclass
class MessageAction(Action):
    pass

@dataclass
class DeployFileAction(Action):
    source: Path
    target: Path

@dataclass
class GenerateFileAction(Action):
    target: Path
    content: str
    executable: bool = False

@dataclass
class PipInstallAction(Action):
    package: str


def plan_symlinks(source_dir: Path, target_dir: Path, backup_dir: Path) -> list[Action]:
    if not source_dir.is_dir():
        return []
    actions = []
    for child in sorted(source_dir.iterdir()):
        if child.name in EXCLUDE_PATTERNS or not child.exists():
            continue
        dest = target_dir / child.name
        if dest.is_symlink() and is_our_symlink(dest, child):
            continue
        if dest.exists() and not dest.is_symlink():
            ts = datetime.now().strftime("%Y%m%d_%H%M%S")
            actions.append(BackupAction(
                description=f"备份 {child.name}",
                original=dest, backup=backup_dir / f"{child.name}_{ts}"))
        actions.append(SymlinkAction(
            description=f"{source_dir.name}/{child.name}",
            source=child, target=dest))
    return actions


def plan_file(source: Path, target: Path, backup_dir: Path) -> list[Action]:
    if not source.exists():
        return []
    actions = []
    if target.is_symlink() and is_our_symlink(target, source):
        return []
    if target.exists() and not target.is_symlink():
        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        actions.append(BackupAction(
            description=f"备份 {source.name}",
            original=target, backup=backup_dir / f"{source.name}_{ts}"))
        if target.is_file():
            try:
                import difflib
                old = target.read_text().splitlines(keepends=True)
                new = source.read_text().splitlines(keepends=True)
                diff = list(difflib.unified_diff(old, new,
                                                  fromfile=str(target), tofile=str(source)))
                if diff:
                    actions.append(MessageAction(description=f"{source.name} 有差异:"))
                    for line in diff[:20]:
                        actions.append(MessageAction(description=f"  {line.rstrip()}"))
            except Exception:
                pass
    actions.append(SymlinkAction(description=source.name, source=source, target=target))
    return actions


def execute_action(action, backup_dir: Path, undo_stack: Optional[UndoStack] = None) -> None:
    if isinstance(action, SymlinkAction):
        if action.target.exists() and not action.target.is_symlink():
            backup_file(action.target, backup_dir)
        create_symlink(action.source, action.target)
        ui.success(f"链接: {action.target.name}")
        if undo_stack:
            undo_stack.push(f"移除链接 {action.target.name}",
                            lambda t=action.target: t.unlink())

    elif isinstance(action, BackupAction):
        backup_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(str(action.original), str(action.backup))

    elif isinstance(action, DeployFileAction):
        action.target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(str(action.source), str(action.target))
        ui.success(f"部署: {action.target}")
        if undo_stack:
            undo_stack.push(f"移除部署 {action.target.name}",
                            lambda t=action.target: t.unlink(missing_ok=True))

    elif isinstance(action, GenerateFileAction):
        action.target.parent.mkdir(parents=True, exist_ok=True)
        action.target.write_text(action.content)
        if action.executable:
            action.target.chmod(0o755)
        ui.success(f"生成: {action.target}")
        if undo_stack:
            undo_stack.push(f"移除生成文件 {action.target.name}",
                            lambda t=action.target: t.unlink(missing_ok=True))

    elif isinstance(action, PipInstallAction):
        ui.info(f"安装 {action.package}...")
        result = subprocess.run(
            [sys.executable, "-m", "pip", "install", action.package],
            capture_output=True, text=True)
        if result.returncode == 0:
            ui.success(f"{action.package} 安装完成")
        else:
            ui.error(f"{action.package} 安装失败")
            raise RuntimeError(f"pip install {action.package} failed")

    elif isinstance(action, MessageAction):
        ui.info(action.description)


def execute_actions(actions: list, backup_dir: Path,
                    undo_stack: Optional[UndoStack] = None) -> None:
    for action in actions:
        execute_action(action, backup_dir, undo_stack)


def snapshot_settings(target: Path, backup_dir: Path) -> Optional[dict]:
    settings = target / "settings.json"
    if settings.exists():
        data = load_json(settings)
        backup_file(settings, backup_dir)
        return json.loads(json.dumps(data))
    return None


def restore_or_delete_settings(target: Path, snapshot: Optional[dict],
                                undo_stack: UndoStack) -> None:
    rel = "~/" + str(target.relative_to(Path.home()))
    settings = target / "settings.json"
    if snapshot is not None:
        snap = snapshot
        undo_stack.push(f"恢复 {rel}/settings.json",
                        lambda s=settings, d=snap: save_json(s, d))
    else:
        undo_stack.push(f"删除 {rel}/settings.json",
                        lambda s=settings: s.unlink(missing_ok=True))
