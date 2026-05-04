"""Claude Code Tool Installer - module definitions.

Each module is a class that knows how to plan, execute, and undo its installation.
Modules are either PerTarget (run once per target directory) or UserLevel (run once).
"""

import json
import os
import shutil
import subprocess
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from pathlib import Path
from typing import List, Optional, Dict, Any

from . import ui
from .utils import (
    backup_file, create_symlink, is_our_symlink, resolve_path,
    cmd_exists, run_cmd, load_json, save_json, update_settings,
)


# ── Actions (planned changes) ────────────────────────────────

@dataclass
class Action:
    """Base action."""
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
    """Informational only, no execution needed."""
    pass

@dataclass
class DeployFileAction(Action):
    """Copy a file to a destination."""
    source: Path
    target: Path

@dataclass
class GenerateFileAction(Action):
    """Generate a file with content."""
    target: Path
    content: str
    executable: bool = False

@dataclass
class PipInstallAction(Action):
    package: str

@dataclass
class ShellAction(Action):
    """Run a shell command."""
    command: list[str]


# ── Base module classes ───────────────────────────────────────

class Module(ABC):
    """Base class for all installable modules."""
    name: str = ""
    description: str = ""
    risk: str = "low"  # low, medium, high
    dep_tools: list[str] = []  # External commands required

    @property
    def risk_label(self) -> str:
        return {"low": "低风险", "medium": "中风险", "high": "高风险"}.get(self.risk, self.risk)

    def check_prerequisites(self) -> dict[str, str]:
        """Return {tool: install_hint} for missing tools."""
        missing = {}
        for tool in self.dep_tools:
            if not cmd_exists(tool):
                hints = {
                    "bun": "curl -fsSL https://bun.sh/install | bash",
                    "jq": "brew install jq / apt install jq",
                }
                missing[tool] = hints.get(tool, f"请安装 {tool}")
        return missing

    def is_applicable(self, target_home: Path) -> bool:
        """Whether this module can be installed for the given target."""
        return True

    @abstractmethod
    def plan(self, target_home: Path, script_dir: Path) -> list[Action]:
        """Return planned actions for this target."""
        ...

    def execute(self, actions: list[Action], backup_dir: Path) -> None:
        """Execute planned actions."""
        for action in actions:
            self._execute_one(action, backup_dir)

    def _execute_one(self, action: Action, backup_dir: Path) -> None:
        if isinstance(action, SymlinkAction):
            if action.target.exists() and not action.target.is_symlink():
                backup_file(action.target, backup_dir)
            create_symlink(action.source, action.target)
            ui.success(f"链接: {action.target.name}")

        elif isinstance(action, BackupAction):
            shutil.copy2(str(action.original), str(action.backup))

        elif isinstance(action, DeployFileAction):
            action.target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(str(action.source), str(action.target))
            ui.success(f"部署: {action.target}")

        elif isinstance(action, GenerateFileAction):
            action.target.parent.mkdir(parents=True, exist_ok=True)
            action.target.write_text(action.content)
            if action.executable:
                action.target.chmod(0o755)
            ui.success(f"生成: {action.target}")

        elif isinstance(action, PipInstallAction):
            ui.info(f"安装 {action.package}...")
            result = subprocess.run(
                [sys.executable, "-m", "pip", "install", action.package],
                capture_output=True, text=True,
            )
            if result.returncode == 0:
                ui.success(f"{action.package} 安装完成")
            else:
                ui.error(f"{action.package} 安装失败")

        elif isinstance(action, ShellAction):
            result = subprocess.run(action.command, capture_output=True, text=True)
            if result.returncode != 0:
                ui.warn(f"命令执行失败: {' '.join(action.command)}")

        elif isinstance(action, MessageAction):
            ui.info(action.description)

    @abstractmethod
    def uninstall(self, target_home: Path, script_dir: Path) -> None:
        ...


import sys  # needed for sys.executable in PipInstallAction handler


# ── Symlink modules (per-target) ─────────────────────────────

class SymlinkModule(Module):
    """Creates symlinks from script_dir/<dir_name>/* into target_home/<dir_name>/*."""
    dir_name: str = ""  # subdirectory name (e.g. "skills", "agents")

    def is_applicable(self, target_home: Path) -> bool:
        return True

    def _source_dir(self, script_dir: Path) -> Path:
        return script_dir / self.dir_name

    def _items(self, script_dir: Path) -> list[Path]:
        src = self._source_dir(script_dir)
        if not src.is_dir():
            return []
        return sorted([p for p in src.iterdir() if p.exists()])

    def plan(self, target_home: Path, script_dir: Path) -> list[Action]:
        actions: list[Action] = []
        for child in self._items(script_dir):
            child_name = child.name
            target = target_home / self.dir_name / child_name
            if target.is_symlink() and is_our_symlink(target, child):
                continue  # already linked correctly
            if target.exists() and not target.is_symlink():
                ts = datetime.now().strftime("%Y%m%d_%H%M%S")  # noqa
                actions.append(BackupAction(
                    description=f"备份 {child_name}",
                    original=target,
                    backup=target_home / "bak" / f"{child_name}_{ts}",
                ))
            actions.append(SymlinkAction(
                description=f"{self.dir_name}/{child_name}",
                source=child,
                target=target,
            ))
        return actions

    def uninstall(self, target_home: Path, script_dir: Path) -> None:
        for child in self._items(script_dir):
            target = target_home / self.dir_name / child.name
            if target.is_symlink() and is_our_symlink(target, child):
                target.unlink()
                ui.info(f"移除: {target.name}")


# ── File module (per-target) ─────────────────────────────────

class FileModule(Module):
    """Installs a single file as symlink (e.g. CLAUDE.md)."""
    file_name: str = ""

    def _source(self, script_dir: Path) -> Path:
        return script_dir / self.file_name

    def plan(self, target_home: Path, script_dir: Path) -> list[Action]:
        src = self._source(script_dir)
        if not src.exists():
            return []
        target = target_home / self.file_name
        actions: list[Action] = []
        if target.is_symlink() and is_our_symlink(target, src):
            return []
        if target.exists() and not target.is_symlink():
            from datetime import datetime
            ts = datetime.now().strftime("%Y%m%d_%H%M%S")
            actions.append(BackupAction(
                description=f"备份 {self.file_name}",
                original=target,
                backup=target_home / "bak" / f"{self.file_name}_{ts}",
            ))
        actions.append(SymlinkAction(
            description=self.file_name,
            source=src,
            target=target,
        ))
        return actions

    def uninstall(self, target_home: Path, script_dir: Path) -> None:
        src = self._source(script_dir)
        target = target_home / self.file_name
        if target.is_symlink() and is_our_symlink(target, src):
            target.unlink()
            ui.info(f"移除: {target}")


# ── Settings modules (per-target, modify settings.json) ──────

class SettingsModule(Module):
    """Base for modules that modify target_home/settings.json."""
    def plan(self, target_home: Path, script_dir: Path) -> list[Action]:
        return [MessageAction(description=f"配置 {self.name}")]

    @abstractmethod
    def configure(self, target_home: Path, script_dir: Path) -> bool:
        """Actually configure. Return True on success."""
        ...

    def execute(self, actions: list[Action], backup_dir: Path) -> None:
        # Settings modules override execute because they don't use standard actions
        pass

    @abstractmethod
    def unconfigure(self, target_home: Path) -> None:
        ...

    def uninstall(self, target_home: Path, script_dir: Path) -> None:
        self.unconfigure(target_home)


class StatuslineModule(SettingsModule):
    name = "statusline"
    description = "状态栏"
    risk = "low"

    def is_applicable(self, target_home: Path) -> bool:
        return target_home.name == ".claude" or target_home.name == ".opencode"

    def configure(self, target_home: Path, script_dir: Path) -> bool:
        settings_path = target_home / "settings.json"
        command = f'"{target_home}/custom-tools/statusline.sh"'

        data = load_json(settings_path)
        current = data.get("statusLine", {}).get("command", "")
        if current == command:
            ui.info("statusline 已配置，跳过")
            return True

        data["statusLine"] = {"type": "command", "command": command}
        save_json(settings_path, data)
        ui.success("statusline 已配置")
        return True

    def unconfigure(self, target_home: Path) -> None:
        settings_path = target_home / "settings.json"
        data = load_json(settings_path)
        if "statusLine" in data:
            del data["statusLine"]
            save_json(settings_path, data)
            ui.info("statusline 配置已移除")


class SkillInjectModule(SettingsModule):
    name = "skill-inject"
    description = "Skill 注入 Hook"
    risk = "medium"

    HOOK_CMD = 'bash "$HOME/.claude/hooks/skill-inject.sh"'

    def is_applicable(self, target_home: Path) -> bool:
        return target_home.name == ".claude"

    def configure(self, target_home: Path, script_dir: Path) -> bool:
        settings_path = target_home / "settings.json"
        data = load_json(settings_path)

        hooks = data.setdefault("hooks", {})
        pre_tool_use = hooks.setdefault("PreToolUse", [])

        # Check if already configured
        for entry in pre_tool_use:
            if entry.get("matcher") == "Skill":
                for h in entry.get("hooks", []):
                    if h.get("command") == self.HOOK_CMD:
                        ui.info("Skill 注入 Hook 已配置，跳过")
                        return True

        # Remove old Skill matcher if exists
        pre_tool_use = [e for e in pre_tool_use if e.get("matcher") != "Skill"]
        pre_tool_use.append({
            "matcher": "Skill",
            "hooks": [{"type": "command", "command": self.HOOK_CMD, "timeout": 5}],
        })
        hooks["PreToolUse"] = pre_tool_use
        save_json(settings_path, data)
        ui.success("Skill 注入 Hook 已配置")
        return True

    def unconfigure(self, target_home: Path) -> None:
        settings_path = target_home / "settings.json"
        data = load_json(settings_path)

        pre_tool_use = data.get("hooks", {}).get("PreToolUse", [])
        pre_tool_use = [
            e for e in pre_tool_use
            if not (e.get("matcher") == "Skill" and
                    any(h.get("command") == self.HOOK_CMD for h in e.get("hooks", [])))
        ]
        # Clean empty hook lists
        pre_tool_use = [e for e in pre_tool_use if e.get("hooks")]
        data.setdefault("hooks", {})["PreToolUse"] = pre_tool_use
        save_json(settings_path, data)
        ui.info("Skill 注入 Hook 已移除")


class KnowledgeEngineModule(SettingsModule):
    name = "knowledge-engine"
    description = "知识引擎"
    risk = "high"
    dep_tools = ["bun", "jq"]

    def is_applicable(self, target_home: Path) -> bool:
        return target_home.name == ".claude"

    def configure(self, target_home: Path, script_dir: Path) -> bool:
        engine_dir = script_dir / "knowledge-engine"
        cli_path = engine_dir / "src" / "cli.ts"
        if not cli_path.exists():
            ui.warn("知识引擎源码不存在，跳过")
            return False

        # Install deps
        ui.info("安装知识引擎依赖...")
        result = run_cmd(["bun", "install", "--frozen-lockfile"], cwd=str(engine_dir))
        if result.returncode != 0:
            run_cmd(["bun", "install", "--no-save"], cwd=str(engine_dir))

        # Create knowledge dir + config
        knowledge_dir = target_home / "knowledge"
        knowledge_dir.mkdir(parents=True, exist_ok=True)
        config_path = knowledge_dir / "config.json"
        if not config_path.exists():
            save_json(config_path, {
                "categories": ["architecture", "patterns", "domain", "troubleshooting"],
                "consolidateThreshold": 3,
                "excludePatterns": ["**/*.lock", "**/node_modules/**", ".env*"],
            }, perm=0o644)

        # Update settings.json hooks
        cli_abs = cli_path.resolve()
        record_cmd = f'bun "{cli_abs}" record'
        process_cmd = f'bun "{cli_abs}" process'
        inject_cmd = f'bun "{cli_abs}" inject-index'

        settings_path = target_home / "settings.json"
        data = load_json(settings_path)

        hooks = data.setdefault("hooks", {})

        # PostToolUse
        post = [e for e in hooks.get("PostToolUse", [])
                if not any(h.get("command") == record_cmd for h in e.get("hooks", []))]
        post.append({"matcher": "Write|Edit", "hooks": [
            {"type": "command", "command": record_cmd, "async": True, "timeout": 5}
        ]})
        hooks["PostToolUse"] = post

        # Stop
        stop = [e for e in hooks.get("Stop", [])
                if not any(h.get("command") == process_cmd for h in e.get("hooks", []))]
        stop.append({"hooks": [
            {"type": "command", "command": process_cmd, "async": True, "timeout": 120}
        ]})
        hooks["Stop"] = stop

        # SessionStart
        start = [e for e in hooks.get("SessionStart", [])
                 if not any(h.get("command") == inject_cmd for h in e.get("hooks", []))]
        start.append({"hooks": [
            {"type": "command", "command": inject_cmd, "timeout": 5}
        ]})
        hooks["SessionStart"] = start

        save_json(settings_path, data)
        ui.success("知识引擎 hooks 已配置")

        # Crontab
        cron_script = engine_dir / "scripts" / "cron-maintenance.sh"
        cron_entry = f"0 23 * * * {cron_script} >> ~/.claude/knowledge/maintenance.log 2>&1 # knowledge-engine-cron"
        try:
            result = run_cmd(["crontab", "-l"])
            existing = result.stdout if result.returncode == 0 else ""
            lines = [l for l in existing.splitlines() if "knowledge-engine-cron" not in l]
            lines.append(cron_entry)
            proc = subprocess.run(["crontab", "-"], input="\n".join(lines) + "\n", text=True)
            if proc.returncode == 0:
                ui.success("crontab 已配置 (每天 23:00)")
        except Exception:
            ui.warn("crontab 配置失败")

        return True

    def unconfigure(self, target_home: Path) -> None:
        settings_path = target_home / "settings.json"
        data = load_json(settings_path)
        # Simplified: remove knowledge-engine hooks by command pattern
        for hook_type in ("PostToolUse", "Stop", "SessionStart"):
            entries = data.get("hooks", {}).get(hook_type, [])
            entries = [e for e in entries if e.get("hooks")]
            data.setdefault("hooks", {})[hook_type] = entries
        save_json(settings_path, data)
        ui.info("知识引擎 hooks 已移除")
        ui.info("注意: 知识库数据未删除")


# ── Pi-specific modules (per-target for ~/.pi/agent) ──────────

class PiSkillsModule(Module):
    name = "pi-skills"
    description = "pi Skills (→ ~/.pi/agent/skills)"
    risk = "low"

    def is_applicable(self, target_home: Path) -> bool:
        return target_home.name == "agent" and target_home.parent.name == ".pi"

    def plan(self, target_home: Path, script_dir: Path) -> list[Action]:
        from datetime import datetime
        src_dir = script_dir / "skills"
        if not src_dir.is_dir():
            return []
        actions: list[Action] = []
        for child in sorted(src_dir.iterdir()):
            if not child.exists():
                continue
            target = target_home / "skills" / child.name
            if target.is_symlink() and is_our_symlink(target, child):
                continue
            if target.exists() and not target.is_symlink():
                ts = datetime.now().strftime("%Y%m%d_%H%M%S")
                actions.append(BackupAction(
                    description=f"备份 {child.name}",
                    original=target,
                    backup=target_home / "bak" / f"{child.name}_{ts}",
                ))
            actions.append(SymlinkAction(
                description=f"pi/skills/{child.name}",
                source=child, target=target,
            ))
        return actions

    def uninstall(self, target_home: Path, script_dir: Path) -> None:
        src_dir = script_dir / "skills"
        for child in sorted(src_dir.iterdir()):
            target = target_home / "skills" / child.name
            if target.is_symlink() and is_our_symlink(target, child):
                target.unlink()
                ui.info(f"移除 pi skill: {child.name}")


class PiAgentsModule(Module):
    name = "pi-agents"
    description = "pi Agents (→ ~/.pi/agent/agents)"
    risk = "low"

    def is_applicable(self, target_home: Path) -> bool:
        return target_home.name == "agent" and target_home.parent.name == ".pi"

    def plan(self, target_home: Path, script_dir: Path) -> list[Action]:
        from datetime import datetime
        src_dir = script_dir / "agents"
        if not src_dir.is_dir():
            return []
        actions: list[Action] = []
        for child in sorted(src_dir.iterdir()):
            agent_md = child / "agent.md"
            if not child.is_dir() or not agent_md.exists():
                continue
            target = target_home / "agents" / f"{child.name}.md"
            if target.is_symlink() and is_our_symlink(target, agent_md):
                continue
            if target.exists() and not target.is_symlink():
                ts = datetime.now().strftime("%Y%m%d_%H%M%S")
                actions.append(BackupAction(
                    description=f"备份 {child.name}.md",
                    original=target,
                    backup=target_home / "bak" / f"{child.name}.md_{ts}",
                ))
            actions.append(SymlinkAction(
                description=f"pi/agents/{child.name}",
                source=agent_md, target=target,
            ))
        return actions

    def uninstall(self, target_home: Path, script_dir: Path) -> None:
        src_dir = script_dir / "agents"
        for child in sorted(src_dir.iterdir()):
            agent_md = child / "agent.md"
            target = target_home / "agents" / f"{child.name}.md"
            if target.is_symlink() and is_our_symlink(target, agent_md):
                target.unlink()
                ui.info(f"移除 pi agent: {child.name}")


class PiStatuslineModule(Module):
    name = "pi-statusline"
    description = "pi 状态栏 Extension"
    risk = "low"

    def is_applicable(self, target_home: Path) -> bool:
        return target_home.name == "agent" and target_home.parent.name == ".pi"

    def plan(self, target_home: Path, script_dir: Path) -> list[Action]:
        from datetime import datetime
        src_dir = script_dir / "custom-tools" / "pi-statusline"
        if not src_dir.is_dir():
            return []
        actions: list[Action] = []
        for child in sorted(src_dir.iterdir()):
            if not child.is_file():
                continue
            target = target_home / "extensions" / "statusline" / child.name
            if target.is_symlink() and is_our_symlink(target, child):
                continue
            if target.exists() and not target.is_symlink():
                ts = datetime.now().strftime("%Y%m%d_%H%M%S")
                actions.append(BackupAction(
                    description=f"备份 {child.name}",
                    original=target,
                    backup=target_home / "bak" / f"statusline_{child.name}_{ts}",
                ))
            actions.append(SymlinkAction(
                description=f"pi/extensions/statusline/{child.name}",
                source=child, target=target,
            ))
        return actions

    def uninstall(self, target_home: Path, script_dir: Path) -> None:
        src_dir = script_dir / "custom-tools" / "pi-statusline"
        target_dir = target_home / "extensions" / "statusline"
        if not target_dir.is_dir():
            return
        for child in sorted(src_dir.iterdir()):
            target = target_dir / child.name
            if target.is_symlink() and is_our_symlink(target, child):
                target.unlink()
                ui.info(f"移除 pi statusline: {child.name}")


# ── User-level modules (run once, not per-target) ────────────

class UserLevelModule(Module):
    """Base for modules that are user-level, not per-target."""
    def is_applicable(self, target_home: Path) -> bool:
        return False  # Never per-target

    def plan(self, target_home: Path, script_dir: Path) -> list[Action]:
        return []  # User-level modules don't use per-target plan

    @abstractmethod
    def plan_standalone(self, script_dir: Path) -> list[Action]:
        """Plan actions (user-level, no target)."""
        ...

    @abstractmethod
    def uninstall_standalone(self) -> None:
        ...

    def uninstall(self, target_home: Path, script_dir: Path) -> None:
        self.uninstall_standalone()


class TavilyCliModule(UserLevelModule):
    name = "tavily-cli"
    description = "Tavily CLI 工具 (search/extract/crawl)"
    risk = "low"

    def check_prerequisites(self) -> dict[str, str]:
        missing = super().check_prerequisites()
        if not cmd_exists("python3"):
            missing["python3"] = "apt install python3 / brew install python3"
        return missing

    def plan_standalone(self, script_dir: Path) -> list[Action]:
        src = script_dir / "skills" / "tavily-web-search" / "scripts" / "tavily.py"
        if not src.exists():
            return [MessageAction(description="Tavily CLI: 源码不存在，跳过")]

        actions: list[Action] = []
        tavily_lib = Path.home() / ".local" / "share" / "tavily"
        tavily_bin = Path.home() / ".local" / "bin" / "tavily"

        if tavily_bin.exists() and tavily_lib.is_dir():
            actions.append(MessageAction(description="Tavily CLI 已安装，将更新"))
        else:
            actions.append(MessageAction(description="Tavily CLI: 部署到 ~/.local/"))

        actions.append(DeployFileAction(
            description="部署 tavily.py",
            source=src,
            target=tavily_lib / "tavily.py",
        ))
        actions.append(GenerateFileAction(
            description="部署 tavily wrapper",
            target=tavily_bin,
            content=self._wrapper_script(),
            executable=True,
        ))

        # Check httpx
        result = run_cmd(["python3", "-c", "import httpx"])
        if result.returncode != 0:
            actions.append(PipInstallAction(
                description="安装 httpx 依赖",
                package="httpx",
            ))

        return actions

    def _wrapper_script(self) -> str:
        return '''#!/usr/bin/env python3
"""tavily — wrapper that sources shell env if needed, then runs the real script."""
import os, sys

if os.environ.get("TAVILY_API_KEYS"):
    os.execvp(sys.executable, [sys.executable,
        os.path.expanduser("~/.local/share/tavily/tavily.py")] + sys.argv[1:])

tavily_sh = os.path.expanduser("~/.shell/tavily.sh")
if os.path.isfile(tavily_sh):
    with open(tavily_sh) as f:
        for line in f:
            line = line.strip()
            if line.startswith("export TAVILY_API_KEYS="):
                val = line.split("=", 1)[1].strip().strip(\'"\').strip("\'")
                os.environ["TAVILY_API_KEYS"] = val
                break

if os.environ.get("TAVILY_API_KEYS"):
    os.execvp(sys.executable, [sys.executable,
        os.path.expanduser("~/.local/share/tavily/tavily.py")] + sys.argv[1:])
else:
    print("错误: 请设置环境变量 TAVILY_API_KEYS (逗号分隔多个 key)", file=sys.stderr)
    sys.exit(1)
'''

    def uninstall_standalone(self) -> None:
        tavily_bin = Path.home() / ".local" / "bin" / "tavily"
        tavily_lib = Path.home() / ".local" / "share" / "tavily"
        if tavily_bin.exists():
            tavily_bin.unlink()
            ui.info("已移除 ~/.local/bin/tavily")
        if tavily_lib.is_dir():
            shutil.rmtree(tavily_lib)
            ui.info("已移除 ~/.local/share/tavily/")
        ui.info("注意: httpx 依赖未卸载")


# ── Module registry ───────────────────────────────────────────

# Platform constraints
AGENTS_ONLY = {"skills"}
PI_ONLY = {"pi-skills", "pi-agents", "pi-statusline"}

def create_all_modules() -> list[Module]:
    """Create all module instances."""
    return [
        # Symlink modules (per-target)
        SymlinkModule.__class__(  # type: ignore
            name="skills", description="Skills 技能集合",
            dir_name="skills", risk="low",
        ) if False else _make_symlink("skills", "Skills 技能集合", "low"),
        _make_symlink("agents", "Agent 子代理", "low"),
        _make_symlink("commands", "自定义命令", "low"),
        _make_symlink("hooks", "Hook 脚本", "low"),
        _make_symlink("custom-tools", "自定义工具", "low"),

        # File modules (per-target)
        FileModule.__class__(  # type: ignore
            name="claude-md", description="CLAUDE.md 全局配置",
            file_name="CLAUDE.md", risk="medium",
        ) if False else _make_file("claude-md", "CLAUDE.md 全局配置", "CLAUDE.md", "medium"),

        # Settings modules (per-target)
        StatuslineModule(),
        SkillInjectModule(),
        KnowledgeEngineModule(),

        # Pi modules (per-target, only for ~/.pi/agent)
        PiSkillsModule(),
        PiAgentsModule(),
        PiStatuslineModule(),

        # User-level modules (run once)
        TavilyCliModule(),
    ]


def _make_symlink(dir_name: str, description: str, risk: str) -> SymlinkModule:
    """Create a SymlinkModule with custom attributes."""
    mod = SymlinkModule()
    mod.name = dir_name
    mod.description = description
    mod.dir_name = dir_name
    mod.risk = risk
    return mod

def _make_file(name: str, description: str, file_name: str, risk: str) -> FileModule:
    """Create a FileModule with custom attributes."""
    mod = FileModule()
    mod.name = name
    mod.description = description
    mod.file_name = file_name
    mod.risk = risk
    return mod
