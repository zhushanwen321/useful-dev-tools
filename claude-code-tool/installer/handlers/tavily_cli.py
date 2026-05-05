"""Tavily CLI — user-level search/extract/crawl tool."""

import shutil
import subprocess
import sys
from pathlib import Path

from installer import ui
from installer.utils import run_cmd
from installer.engine import DeployFileAction, GenerateFileAction, PipInstallAction, execute_actions

TITLE = "Tavily CLI 工具 (search/extract/crawl)"
RISK = "low"
TARGETS = []  # user-level

TAVILY_LIB = Path.home() / ".local" / "share" / "tavily"
TAVILY_BIN = Path.home() / ".local" / "bin" / "tavily"


def _wrapper_script() -> str:
    return (
        '#!/usr/bin/env python3\n'
        '"""tavily — wrapper that sources shell env if needed."""\n'
        'import os, sys\n'
        '\n'
        'if os.environ.get("TAVILY_API_KEYS"):\n'
        '    os.execvp(sys.executable, [sys.executable,\n'
        '        os.path.expanduser("~/.local/share/tavily/tavily.py")] + sys.argv[1:])\n'
        '\n'
        'tavily_sh = os.path.expanduser("~/.shell/tavily.sh")\n'
        'if os.path.isfile(tavily_sh):\n'
        '    with open(tavily_sh) as f:\n'
        '        for line in f:\n'
        '            line = line.strip()\n'
        '            if line.startswith("export TAVILY_API_KEYS="):\n'
        '                val = line.split("=", 1)[1].strip().strip(\'"\').strip("\'")\n'
        '                os.environ["TAVILY_API_KEYS"] = val\n'
        '                break\n'
        '\n'
        'if os.environ.get("TAVILY_API_KEYS"):\n'
        '    os.execvp(sys.executable, [sys.executable,\n'
        '        os.path.expanduser("~/.local/share/tavily/tavily.py")] + sys.argv[1:])\n'
        'else:\n'
        '    print("错误: 请设置 TAVILY_API_KEYS 环境变量", file=sys.stderr)\n'
        '    sys.exit(1)\n'
    )


def configure(target: Path, script_dir: Path) -> bool:
    src = script_dir / "skills" / "tavily-web-search" / "scripts" / "tavily.py"
    if not src.exists():
        ui.warn("Tavily CLI: 源码不存在")
        return False

    actions = [
        DeployFileAction(description="部署 tavily.py", source=src,
                         target=TAVILY_LIB / "tavily.py"),
        GenerateFileAction(description="部署 tavily wrapper",
                           target=TAVILY_BIN,
                           content=_wrapper_script(), executable=True),
    ]
    result = run_cmd(["python3", "-c", "import httpx"])
    if result.returncode != 0:
        actions.append(PipInstallAction(description="安装 httpx", package="httpx"))

    execute_actions(actions, Path.home() / ".local" / "bak")
    return True


def unconfigure(target: Path, script_dir: Path = None) -> None:
    if TAVILY_BIN.exists():
        TAVILY_BIN.unlink()
        ui.info("已移除 ~/.local/bin/tavily")
    if TAVILY_LIB.is_dir():
        shutil.rmtree(TAVILY_LIB)
        ui.info("已移除 ~/.local/share/tavily/")
    ui.info("注意: httpx 依赖未卸载")
