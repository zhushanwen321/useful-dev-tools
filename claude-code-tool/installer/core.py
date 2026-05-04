"""Claude Code Tool Installer - main installer logic."""

import shutil
from pathlib import Path
from typing import Optional

from . import ui
from .modules import (
    Module, UserLevelModule, SettingsModule,
    Action, SymlinkAction, BackupAction, MessageAction,
    UndoStack, create_all_modules,
)
from .utils import backup_file, log_action


class Installer:
    """Main installer orchestrator."""

    def __init__(self, script_dir: Path, dry_run: bool = False):
        self.script_dir = script_dir
        self.dry_run = dry_run
        self.modules = create_all_modules()
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
            print(f"\n{ui.bold(f'=== Claude Code Tool 管理脚本{mode} ===')}\n")
            print("请选择操作:")
            print("  1) 安装")
            print("  2) 卸载")
            print("  3) 退出\n")

            choice = ui.choose("", [
                ("1", "安装"), ("2", "卸载"), ("3", "退出"),
            ])
            if choice == "1":
                self._install_flow()
            elif choice == "2":
                self._uninstall_flow()
            else:
                print("\n再见!\n")
                break

    # ── Install ──────────────────────────────────────────────

    def _install_flow(self) -> None:
        # [1/4] Target
        selected_targets = self._select_targets()
        if not selected_targets:
            return

        # [2/4] Modules
        selected_modules = self._select_modules(selected_targets)
        if not selected_modules:
            return

        # [3/4] Plan (store per-target + user-level)
        plan_data = self._build_plan(selected_targets, selected_modules)
        real_actions = [a for a in plan_data["all_actions"]
                        if not isinstance(a, MessageAction)]
        if not real_actions:
            print("\n无需变更，所有选中模块已是最新状态。")
            return

        self._show_plan(plan_data["all_actions"])

        # [4/4] Confirm & execute
        if self.dry_run:
            print("\n[dry-run] 仅展示计划，不执行变更。")
            return

        if not ui.confirm("\n确认执行以上变更?", default=False):
            print("已取消。")
            return

        self._execute(plan_data)

        # Rollback hints
        backups = [a for a in plan_data["all_actions"] if isinstance(a, BackupAction)]
        if backups:
            print(f"\n{ui.dim('回滚指令 (如需撤销):')}")
            for ba in backups:
                orig_name = ba.original.name
                print(ui.dim(f"  cp {ba.backup} {ba.original}"))

        # Log
        for target in selected_targets:
            log_action(target, "INSTALL", ", ".join(selected_modules.keys()))

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
        # opencode only if dir exists
        if self.targets["opencode"] in targets and not self.targets["opencode"].is_dir():
            targets.remove(self.targets["opencode"])
        return targets

    def _select_modules(self, targets: list[Path]) -> dict[str, Module]:
        items: list[tuple[str, str, str]] = []
        defaults: set[str] = set()
        unavailable: dict[str, str] = {}

        for mod in self.modules:
            # Check if applicable for at least one target
            applicable = isinstance(mod, UserLevelModule) or any(mod.is_applicable(t) for t in targets)
            if not applicable:
                continue

            missing = mod.check_prerequisites()
            items.append((mod.name, mod.description, mod.risk))
            if missing:
                unavailable[mod.name] = ", ".join(missing.keys())
            elif mod.risk == "low":
                defaults.add(mod.name)

        if not items:
            print("没有可用的模块。")
            return {}

        selected_names = ui.multi_select(
            "--- [2/4] 选择要安装的模块 ---",
            items, defaults, unavailable,
        )
        return {n: self._find(n) for n in selected_names if self._find(n)}

    def _find(self, name: str) -> Optional[Module]:
        for mod in self.modules:
            if mod.name == name:
                return mod
        return None

    # ── Plan ─────────────────────────────────────────────────

    def _build_plan(self, targets: list[Path],
                    selected: dict[str, Module]) -> dict:
        """Build plan, returning structured data for execution."""
        per_target: dict[Path, list[Action]] = {}
        user_level: list[Action] = []
        all_actions: list[Action] = []

        # Per-target
        for target in targets:
            target_actions: list[Action] = []
            for mod in selected.values():
                if isinstance(mod, UserLevelModule):
                    continue
                if not mod.is_applicable(target):
                    continue
                actions = mod.plan(target, self.script_dir)
                target_actions.extend(actions)
            per_target[target] = target_actions
            all_actions.extend(target_actions)

        # User-level (once)
        for mod in selected.values():
            if isinstance(mod, UserLevelModule):
                actions = mod.plan_standalone(self.script_dir)
                user_level.extend(actions)
                all_actions.extend(actions)

        return {
            "per_target": per_target,
            "user_level": user_level,
            "all_actions": all_actions,
            "selected": selected,
        }

    def _show_plan(self, actions: list[Action]) -> None:
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
        from .modules import UndoStack
        import shutil as _shutil
        undo_stack = UndoStack()

        try:
            for target, actions in plan_data["per_target"].items():
                if not actions:
                    continue
                rel = "~/" + str(target.relative_to(Path.home()))
                print(f"\n--- 安装到 {rel} ---")
                target.mkdir(parents=True, exist_ok=True)
                backup_dir = target / "bak"

                self._migrate_legacy(target)

                for mod in selected.values():
                    if isinstance(mod, UserLevelModule) or not mod.is_applicable(target):
                        continue

                    if isinstance(mod, SettingsModule):
                        settings = target / "settings.json"
                        had_settings = settings.exists()
                        if had_settings:
                            backup_file(settings, backup_dir)
                        mod.configure(target, self.script_dir)
                        # Record undo for settings
                        if had_settings:
                            backups = sorted(backup_dir.glob("settings.json_*"), reverse=True)
                            if backups:
                                bak = backups[0]
                                undo_stack.push(f"恢复 {rel}/settings.json",
                                                lambda s=settings, b=bak: _shutil.copy2(str(b), str(s)))
                        else:
                            undo_stack.push(f"删除 {rel}/settings.json",
                                            lambda s=settings: s.unlink(missing_ok=True))
                    else:
                        mod.execute(actions, backup_dir, undo_stack)

            # User-level (once)
            user_actions = plan_data["user_level"]
            if user_actions:
                for mod in selected.values():
                    if isinstance(mod, UserLevelModule):
                        print(f"\n--- {mod.description} ---")
                        mod.execute(user_actions, Path.home() / ".local" / "bak", undo_stack)

        except Exception as e:
            ui.error(f"安装失败: {e}")
            print(f"\n{ui.bold('=== 自动回滚 ===')}")
            count = undo_stack.rollback()
            if count > 0:
                print(f"\n{ui.yellow(f'已回滚 {count} 个操作。')}")
            else:
                print("\n没有需要回滚的操作。")
            raise

        self._last_undo_stack = undo_stack

    # ── Uninstall ────────────────────────────────────────────

    def _uninstall_flow(self) -> None:
        choice = ui.choose("选择要卸载的目标:", [
            ("1", "~/.claude"),
            ("2", "~/.opencode"),
            ("3", "~/.agents"),
            ("4", "~/.pi/agent"),
            ("5", "全部"),
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

        user_level_done = False

        for key in keys:
            target = self.targets[key]
            if key == "opencode" and not target.is_dir():
                continue
            rel = "~/" + str(target.relative_to(Path.home()))
            print(f"\n--- 从 {rel} 卸载 ---")

            for mod in self.modules:
                if isinstance(mod, UserLevelModule):
                    # User-level: only run once (for claude or "全部")
                    if not user_level_done and key in ("claude",) or choice == "5":
                        if self.dry_run:
                            ui.info(f"[dry-run] 将卸载 {mod.description}")
                        else:
                            mod.uninstall_standalone()
                        user_level_done = True
                    continue

                if not mod.is_applicable(target):
                    continue

                if self.dry_run:
                    ui.info(f"[dry-run] 将卸载 {mod.name}")
                else:
                    mod.uninstall(target, self.script_dir)
                    # SettingsModule.uninstall() already calls unconfigure()

        if not self.dry_run:
            log_action(target, "UNINSTALL", "all")
            print(f"\n{ui.green('卸载完成。')}")

    # ── Legacy migration ─────────────────────────────────────

    def _migrate_legacy(self, target: Path) -> None:
        """Migrate old directory-level symlinks to new per-item symlinks."""
        from .utils import is_our_symlink
        migrated = 0
        for item_name in ("skills", "agents", "commands", "hooks", "custom-tools"):
            item_path = target / item_name
            if not item_path.is_symlink() or not item_path.is_dir():
                continue
            old_target = item_path.resolve()
            source_dir = self.script_dir / item_name
            if not source_dir.is_dir():
                continue
            ui.info(f"迁移老安装: {item_name} (目录级 symlink)")
            item_path.unlink()
            item_path.mkdir(parents=True, exist_ok=True)
            for child in sorted(source_dir.iterdir()):
                if child.exists() and child.name not in {"__pycache__", ".DS_Store", ".git"}:
                    (item_path / child.name).symlink_to(child)
            migrated += 1
        if migrated:
            ui.success(f"已迁移 {migrated} 个目录从老安装方式")
