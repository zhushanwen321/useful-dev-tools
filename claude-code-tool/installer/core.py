"""Claude Code Tool Installer - main installer logic."""

from pathlib import Path
from typing import Optional

from . import ui
from .modules import (
    Module, UserLevelModule, SettingsModule,
    Action, SymlinkAction, BackupAction, MessageAction,
    create_all_modules, AGENTS_ONLY, PI_ONLY,
)
from .utils import backup_file


class Installer:
    """Main installer orchestrator."""

    def __init__(self, script_dir: Path):
        self.script_dir = script_dir
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
            print(f"\n{ui.bold('=== Claude Code Tool 管理脚本 (Python) ===')}\n")
            print("请选择操作:")
            print("  1) 安装")
            print("  2) 卸载")
            print("  3) 退出\n")

            choice = ui.choose("", [
                ("1", "安装"),
                ("2", "卸载"),
                ("3", "退出"),
            ])
            if choice == "1":
                self._install_flow()
            elif choice == "2":
                self._uninstall_flow()
            elif choice == "3" or choice is None:
                print("\n再见!\n")
                break

    # ── Install flow ─────────────────────────────────────────

    def _install_flow(self) -> None:
        # [1/4] Select targets
        selected_targets = self._select_targets()
        if not selected_targets:
            return

        # [2/4] Select modules
        selected_modules = self._select_modules(selected_targets)
        if not selected_modules:
            return

        # [3/4] Plan
        plan = self._plan(selected_targets, selected_modules)
        if not plan:
            print("\n无需变更，所有选中模块已是最新状态。")
            return

        self._show_plan(plan)

        # [4/4] Confirm & execute
        if not ui.confirm("\n确认执行以上变更?", default=False):
            print("已取消。")
            return

        self._execute(selected_targets, selected_modules)
        print(f"\n{ui.green('安装完成。')}")

    def _select_targets(self) -> list[Path]:
        """Let user choose target directories."""
        options = [
            ("1", "Claude Code (~/.claude)"),
            ("2", "OpenCode (~/.opencode)"),
            ("3", "Agent Skills (~/.agents)"),
            ("4", "pi (~/.pi/agent)"),
            ("5", "全部"),
        ]
        choice = ui.choose("--- [1/4] 选择目标平台 ---", options)
        if choice is None:
            return []

        mapping = {
            "1": ["claude"],
            "2": ["opencode"],
            "3": ["agents"],
            "4": ["pi"],
            "5": ["claude", "opencode", "agents", "pi"],
        }
        keys = mapping.get(choice, [])
        targets = [self.targets[k] for k in keys if k in self.targets]

        # Filter: opencode must exist
        if self.targets["opencode"] in targets and not self.targets["opencode"].is_dir():
            targets.remove(self.targets["opencode"])

        return targets

    def _select_modules(self, targets: list[Path]) -> dict[str, Module]:
        """Let user choose modules, return {name: Module}."""
        # Build module list based on applicable targets
        items = []
        defaults = set()
        unavailable = {}

        for mod in self.modules:
            # Check if applicable for at least one target
            applicable = any(mod.is_applicable(t) for t in targets)
            if isinstance(mod, UserLevelModule):
                applicable = True  # User-level always shown

            if not applicable:
                continue

            # Check prerequisites
            missing = mod.check_prerequisites()
            if missing:
                unavailable[mod.name] = ", ".join(missing.keys())
                items.append((mod.name, mod.description, mod.risk))
            else:
                items.append((mod.name, mod.description, mod.risk))
                if mod.risk == "low":
                    defaults.add(mod.name)

        if not items:
            print("没有可用的模块。")
            return {}

        selected_names = ui.multi_select(
            "--- [2/4] 选择要安装的模块 ---",
            items, defaults, unavailable,
        )

        return {name: self._get_module(name) for name in selected_names
                if self._get_module(name) is not None}

    def _get_module(self, name: str) -> Optional[Module]:
        for mod in self.modules:
            if mod.name == name:
                return mod
        return None

    def _plan(self, targets: list[Path], selected: dict[str, Module]) -> list[Action]:
        """Generate plan for all selected modules across all targets."""
        all_actions: list[Action] = []

        # Per-target modules
        for target in targets:
            for mod in selected.values():
                if isinstance(mod, UserLevelModule):
                    continue
                if not mod.is_applicable(target):
                    continue
                actions = mod.plan(target, self.script_dir)
                all_actions.extend(actions)

        # User-level modules (once)
        for mod in selected.values():
            if isinstance(mod, UserLevelModule):
                actions = mod.plan_standalone(self.script_dir)
                all_actions.extend(actions)

        return all_actions

    def _show_plan(self, actions: list[Action]) -> None:
        """Display planned actions."""
        print(f"\n{ui.bold('=== 变更计划 ===')}\n")
        symlink_count = backup_count = other_count = 0

        for action in actions:
            if isinstance(action, SymlinkAction):
                ui.info(f"+ {action.description}")
                symlink_count += 1
            elif isinstance(action, BackupAction):
                ui.info(f"△ 备份: {action.original.name}")
                backup_count += 1
            elif isinstance(action, MessageAction):
                ui.info(f"  {action.description}")
            else:
                ui.info(f"* {action.description}")
                other_count += 1

        print(f"\n摘要: {symlink_count} 个链接, {backup_count} 个备份, {other_count} 个其他操作")

    def _execute(self, targets: list[Path], selected: dict[str, Module]) -> None:
        """Execute the installation."""
        # Per-target: symlinks + file modules
        for target in targets:
            print(f"\n--- 安装到 ~/{target.relative_to(Path.home())} ---")
            target.mkdir(parents=True, exist_ok=True)
            backup_dir = target / "bak"

            for mod in selected.values():
                if isinstance(mod, UserLevelModule):
                    continue
                if not mod.is_applicable(target):
                    continue

                # Settings modules have special execute
                if isinstance(mod, SettingsModule):
                    settings = target / "settings.json"
                    if settings.exists():
                        backup_file(settings, backup_dir)
                    mod.configure(target, self.script_dir)
                else:
                    actions = mod.plan(target, self.script_dir)
                    mod.execute(actions, backup_dir)

        # User-level modules (once)
        for mod in selected.values():
            if isinstance(mod, UserLevelModule):
                print(f"\n--- {mod.description} ---")
                actions = mod.plan_standalone(self.script_dir)
                backup_dir = Path.home() / ".local" / "bak"
                mod.execute(actions, backup_dir)

    # ── Uninstall flow ───────────────────────────────────────

    def _uninstall_flow(self) -> None:
        options = [
            ("1", "~/.claude"),
            ("2", "~/.opencode"),
            ("3", "~/.agents"),
            ("4", "~/.pi/agent"),
            ("5", "全部"),
        ]
        choice = ui.choose("选择要卸载的目标:", options)
        if choice is None:
            return

        mapping = {"1": ["claude"], "2": ["opencode"], "3": ["agents"], "4": ["pi"], "5": ["claude", "opencode", "agents", "pi"]}
        keys = mapping.get(choice, [])

        for key in keys:
            target = self.targets[key]
            if key == "opencode" and not target.is_dir():
                continue
            print(f"\n--- 从 ~/{target.relative_to(Path.home())} 卸载 ---")
            for mod in self.modules:
                if isinstance(mod, UserLevelModule):
                    if key == "claude" or choice == "5":
                        mod.uninstall_standalone()
                    continue
                if mod.is_applicable(target):
                    mod.uninstall(target, self.script_dir)
                # Settings unconfigure
                if isinstance(mod, SettingsModule):
                    mod.unconfigure(target)

        print(f"\n{ui.green('卸载完成。')}")
