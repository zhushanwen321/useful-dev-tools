#!/usr/bin/env python3
"""Claude Code Tool 管理脚本 (Python 版)

用法:
  python3 install.py           # 交互模式
  python3 install.py --dry-run # 预览变更，不执行
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from installer.core import Installer


def main():
    script_dir = Path(__file__).parent.resolve()
    dry_run = "--dry-run" in sys.argv
    installer = Installer(script_dir, dry_run=dry_run)
    installer.run()


if __name__ == "__main__":
    main()
