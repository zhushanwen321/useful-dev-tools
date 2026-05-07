"""自动发现引擎：目录即模块 + Handler 插件。"""

import importlib
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

EXCLUDE_DIRS = {"__pycache__", ".DS_Store", ".git", "node_modules", "bak",
                "knowledge-engine", "installer"}
EXCLUDE_FILES = {".DS_Store", ".gitignore", "README.md"}
SYMLINK_SUFFIX = (".md",)


@dataclass
class ModuleInfo:
    """一个已发现的模块。"""
    name: str
    title: str
    risk: str = "low"
    module_type: str = "symlink"      # symlink | file | handler | user-handler
    source: Optional[Path] = None     # symlink/file: 源目录或源文件
    handler: Optional[object] = None  # handler: Python 模块对象
    targets: Optional[list[str]] = None  # None = 所有 target

    @property
    def is_user_level(self) -> bool:
        return self.module_type == "user-handler"


def discover_all(script_dir: Path) -> list[ModuleInfo]:
    """扫描 script_dir + handlers/ 目录，发现所有模块。"""
    modules = []

    # 第一层：目录即 symlink 模块
    for child in sorted(script_dir.iterdir()):
        if child.name.startswith('.') or child.name in EXCLUDE_DIRS:
            continue
        if child.is_dir():
            modules.append(ModuleInfo(
                name=child.name,
                title=f"{child.name}/ 目录",
                module_type="symlink",
                source=child,
            ))
        elif child.is_file() and child.suffix in SYMLINK_SUFFIX:
            modules.append(ModuleInfo(
                name=child.stem,
                title=child.name,
                risk="medium",
                module_type="file",
                source=child,
            ))

    # 第二层：Handler 插件
    handler_dir = Path(__file__).parent / "handlers"
    if handler_dir.is_dir():
        for py in sorted(handler_dir.glob("*.py")):
            if py.name.startswith("_"):
                continue
            mod = importlib.import_module(f".handlers.{py.stem}", package="installer")
            targets = getattr(mod, "TARGETS", [])
            modules.append(ModuleInfo(
                name=py.stem.replace("_", "-"),
                title=getattr(mod, "TITLE", py.stem),
                risk=getattr(mod, "RISK", "low"),
                module_type="user-handler" if not targets else "handler",
                handler=mod,
                targets=targets if targets else None,
            ))

    return modules
