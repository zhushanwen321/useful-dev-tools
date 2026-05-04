#!/usr/bin/env python3
"""Claude Code Tool 管理脚本 (Python 版)

用法:
  python3 install.py           # 交互模式
  python3 install.py --dry-run # 预览变更
"""

import sys
from pathlib import Path

# 确保能 import 同目录的 installer 包
sys.path.insert(0, str(Path(__file__).parent))

from installer.core import Installer


def main():
    script_dir = Path(__file__).parent.resolve()
    installer = Installer(script_dir)

    if "--dry-run" in sys.argv:
        # TODO: dry-run 模式
        print("Dry-run 模式开发中...")
        return

    installer.run()


if __name__ == "__main__":
    main()
