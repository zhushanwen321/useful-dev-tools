"""Claude Code Tool Installer — main installer logic."""

import shutil
from pathlib import Path
from typing import Optional

from . import ui
from .engine import (
    Action, SymlinkAction, BackupAction, MessageAction,
    UndoStack, plan_symlinks, plan_file,
    execute_actions, snapshot_settings, restore_or_delete_settings,
)
from .registry import discover_all, ModuleInfo
from .utils import backup_file, is_our_symlink, log_action


class Installer:
    """Main installer orchestrator."""

    def __init__(self, script_dir: Path, dry_run: bool = False):
        self.script_dir = script_dir
        self.dry_run = dry_run
        self.all_modules = discover_all(script_dir)
        self.targets: dict[str, Path] = {
            "claude": Path.home() / ".claude",
            "opencode": Path.home() / ".opencode",
            "agents": Path.home() / ".agents",
            "pi": Path.home() / ".pi" / "agent",
        }

    def run(self) -> None:
        """Main menu loop."""
        while True:
            mode = " (dry-run)" if self.dry_run else ""
            choice = ui.choose(
                f"=== Claude Code Tool 管理脚本{mode} ===\n请选择操作:",
                [("1", "安装"), ("2", "卸载"), ("3", "退出")],
            )
            if choice == "1":
                self._install_flow()
            elif choice == "2":
                self._uninstall_flow()
            else:
                print("\n再见!\n")
                break

    # ── Install ──────────────────────────────────────────────

    def _install_flow(self) -> None:
        selected_targets = self._select_targets()
        if not selected_targets:
            return

        selected_modules = self._select_modules(selected_targets)
        if not selected_modules:
            return

        plan_data = self._build_plan(selected_targets, selected_modules)
        real = [a for a in plan_data["actions"] if not isinstance(a, MessageAction)]
        if not real:
            print("\n无需变更，所有选中模块已是最新状态。")
            return

        self._show_plan(plan_data["actions"])

        if self.dry_run:
            print("\n[dry-run] 仅展示计划，不执行变更。")
            return

        if not ui.confirm("\n确认执行以上变更?", default=False):
            print("已取消。")
            return

        self._execute(plan_data)

        backups = [a for a in plan_data["actions"] if isinstance(a, BackupAction)]
        if backups:
            print(f"\n{ui.dim('回滚指令 (如需撤销):')}")
            for ba in backups:
                print(ui.dim(f"  cp {ba.backup} {ba.original}"))

        for t in selected_targets:
            log_action(t, "INSTALL", ", ".join(m.name for m in selected_modules))

        print(f"\n{ui.green('安装完成。')}")

    def _select_targets(self) -> list[Path]:
        choice = ui.choose("--- [1/4] 选择目标平台 ---", [
            ("1", "Claude Code (~/.claude)"),
            ("2", "OpenCode (~/.opencode)"),
            ("3", "Agent Skills (~/.agents)"),
            ("4", "pi (~/.pi/agent)"),
            ("5", "全部"),
        ])
        if choice is None:
            return []
        mapping = {
            "1": ["claude"], "2": ["opencode"],
            "3": ["agents"], "4": ["pi"],
            "5": ["claude", "opencode", "agents", "pi"],
        }
        keys = mapping.get(choice, [])
        targets = [self.targets[k] for k in keys]
        if self.targets["opencode"] in targets and not self.targets["opencode"].is_dir():
            targets.remove(self.targets["opencode"])
        return targets

    def _select_modules(self, targets: list[Path]) -> list[ModuleInfo]:
        items = []
        defaults = set()
        unavailable = {}

        for mod in self.all_modules:
            if not self._is_applicable(mod, targets):
                continue
            items.append((mod.name, mod.title, mod.risk))
            if mod.risk == "low":
                defaults.add(mod.name)

        if not items:
            print("没有可用的模块。")
            return []

        selected_names = ui.multi_select(
            "--- [2/4] 选择要安装的模块 ---", items, defaults, unavailable)
        return [m for m in self.all_modules if m.name in selected_names]

    def _is_applicable(self, mod: ModuleInfo, targets: list[Path]) -> bool:
        if mod.is_user_level:
            return True
        if mod.targets:
            return any(t.name in mod.targets for t in targets)
        return True

    # ── Plan ─────────────────────────────────────────────────

    def _build_plan(self, targets: list[Path],
                    selected: list[ModuleInfo]) -> dict:
        actions = []
        per_target_data = {}

        for target in targets:
            target_actions = []
            for mod in selected:
                if mod.is_user_level:
                    continue
                if mod.targets and target.name not in mod.targets:
                    continue

                if mod.module_type == "symlink":
                    acts = plan_symlinks(mod.source, target / mod.name, target / "bak")
                    target_actions.extend(acts)
                elif mod.module_type == "file":
                    acts = plan_file(mod.source, target / mod.source.name, target / "bak")
                    target_actions.extend(acts)
                elif mod.module_type == "handler":
                    target_actions.append(MessageAction(description=f"配置 {mod.title}"))

            per_target_data[target] = target_actions
            actions.extend(target_actions)

        # User-level
        for mod in selected:
            if mod.is_user_level:
                actions.append(MessageAction(description=f"配置 {mod.title}"))

        return {"actions": actions, "per_target_data": per_target_data, "selected": selected}

    def _show_plan(self, actions: list) -> None:
        print(f"\n{ui.bold('=== 变更计划 ===')}\n")
        symlinks = backups = others = 0
        for a in actions:
            if isinstance(a, SymlinkAction):
                ui.info(f"+ {a.description}")
                symlinks += 1
            elif isinstance(a, BackupAction):
                ui.info(f"△ 备份: {a.original.name}")
                backups += 1
            elif isinstance(a, MessageAction):
                ui.info(f"  {a.description}")
            else:
                ui.info(f"* {a.description}")
                others += 1
        print(f"\n摘要: {symlinks} 个链接, {backups} 个备份, {others} 个其他操作")

    # ── Execute ──────────────────────────────────────────────

    def _execute(self, plan_data: dict) -> None:
        selected = plan_data["selected"]
        undo_stack = UndoStack()

        try:
            for target, target_actions in plan_data["per_target_data"].items():
                if not target_actions:
                    continue
                rel = "~/" + str(target.relative_to(Path.home()))
                print(f"\n--- 安装到 {rel} ---")
                target.mkdir(parents=True, exist_ok=True)
                backup_dir = target / "bak"

                self._migrate_legacy(target, undo_stack)

                snap = snapshot_settings(target, backup_dir)

                for mod in selected:
                    if mod.is_user_level:
                        continue
                    if mod.targets and target.name not in mod.targets:
                        continue

                    if mod.module_type in ("symlink", "file"):
                        mod_acts = [a for a in target_actions
                                    if isinstance(a, (SymlinkAction, BackupAction))
                                    and a.description.startswith(mod.name)]
                        execute_actions(mod_acts, backup_dir, undo_stack)
                    elif mod.module_type == "handler":
                        mod.handler.configure(target, self.script_dir)

                restore_or_delete_settings(target, snap, undo_stack)

            # User-level
            for mod in selected:
                if mod.is_user_level:
                    print(f"\n--- {mod.title} ---")
                    mod.handler.configure(Path.home(), self.script_dir)

        except Exception as e:
            ui.error(f"安装失败: {e}")
            print(f"\n{ui.bold('=== 自动回滚 ===')}")
            count = undo_stack.rollback()
            print(f"\n{ui.yellow(f'已回滚 {count} 个操作。')}" if count
                  else "\n没有需要回滚的操作。")
            raise

        undo_stack.clear()

    # ── Uninstall ────────────────────────────────────────────

    def _uninstall_flow(self) -> None:
        choice = ui.choose("选择要卸载的目标:", [
            ("1", "~/.claude"), ("2", "~/.opencode"),
            ("3", "~/.agents"), ("4", "~/.pi/agent"), ("5", "全部"),
        ])
        if choice is None:
            return
        mapping = {
            "1": ["claude"], "2": ["opencode"],
            "3": ["agents"], "4": ["pi"],
            "5": ["claude", "opencode", "agents", "pi"],
        }
        keys = mapping.get(choice, [])

        if not self.dry_run and not ui.confirm("确认卸载?", default=False):
            print("已取消。")
            return

        # User-level first
        for mod in self.all_modules:
            if mod.is_user_level and hasattr(mod.handler, "unconfigure"):
                if self.dry_run:
                    ui.info(f"[dry-run] 将卸载 {mod.title}")
                else:
                    mod.handler.unconfigure(Path.home(), self.script_dir)
                break

        for key in keys:
            target = self.targets[key]
            if key == "opencode" and not target.is_dir():
                continue
            rel = "~/" + str(target.relative_to(Path.home()))
            print(f"\n--- 从 {rel} 卸载 ---")

            for mod in self.all_modules:
                if mod.is_user_level:
                    continue
                if mod.targets and target.name not in mod.targets:
                    continue
                if not self.dry_run:
                    if mod.handler:
                        mod.handler.unconfigure(target, self.script_dir)
                    else:
                        self._uninstall_symlinks(mod, target)

        if not self.dry_run:
            for key in keys:
                log_action(self.targets[key], "UNINSTALL", "all")
            print(f"\n{ui.green('卸载完成。')}")

    def _uninstall_symlinks(self, mod: ModuleInfo, target: Path) -> None:
        if mod.module_type == "symlink" and mod.source and mod.source.is_dir():
            dest_dir = target / mod.name
            for child in sorted(mod.source.iterdir()):
                dest = dest_dir / child.name
                if dest.is_symlink() and is_our_symlink(dest, child):
                    dest.unlink()
                    ui.info(f"移除: {dest.name}")

    # ── Legacy migration ─────────────────────────────────────

    def _migrate_legacy(self, target: Path, undo_stack: UndoStack) -> None:
        migrated = 0
        for item_name in ("skills", "agents", "commands", "hooks", "custom-tools"):
            item_path = target / item_name
            if not item_path.is_symlink() or not item_path.is_dir():
                continue
            source_dir = self.script_dir / item_name
            if not source_dir.is_dir():
                continue
            ui.info(f"迁移老安装: {item_name}")
            old_target = str(item_path.resolve())
            undo_stack.push(f"恢复老安装 {item_name}",
                            lambda p=item_path, r=old_target: (
                                shutil.rmtree(str(p)) if p.is_dir() else p.unlink(missing_ok=True),
                                p.symlink_to(r))[-1])
            item_path.unlink()
            item_path.mkdir(parents=True, exist_ok=True)
            for child in sorted(source_dir.iterdir()):
                if child.exists() and child.name not in {"__pycache__", ".DS_Store", ".git"}:
                    (item_path / child.name).symlink_to(child)
            migrated += 1
        if migrated:
            ui.success(f"已迁移 {migrated} 个目录从老安装方式")
