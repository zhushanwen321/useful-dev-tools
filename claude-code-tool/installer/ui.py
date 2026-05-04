"""Claude Code Tool Installer - terminal UI helpers."""

import sys
from typing import Optional


# ── Colors (ANSI, safe for most terminals) ────────────────────

def _supports_color() -> bool:
    return hasattr(sys.stdout, "isatty") and sys.stdout.isatty()

def green(text: str) -> str:
    return f"\033[32m{text}\033[0m" if _supports_color() else text

def yellow(text: str) -> str:
    return f"\033[33m{text}\033[0m" if _supports_color() else text

def red(text: str) -> str:
    return f"\033[31m{text}\033[0m" if _supports_color() else text

def bold(text: str) -> str:
    return f"\033[1m{text}\033[0m" if _supports_color() else text

def dim(text: str) -> str:
    return f"\033[2m{text}\033[0m" if _supports_color() else text


# ── Interactive widgets ───────────────────────────────────────

def choose(prompt: str, options: list[tuple[str, str]]) -> Optional[str]:
    """Show a numbered menu, return chosen key or None (cancelled).
    
    options: [(key, label), ...]
    """
    print(f"\n{prompt}\n")
    for i, (_, label) in enumerate(options, 1):
        print(f"  {i}) {label}")
    print()

    while True:
        raw = input("请输入选项: ").strip()
        if raw.lower() in ("q", "quit", ""):
            return None
        try:
            idx = int(raw) - 1
            if 0 <= idx < len(options):
                return options[idx][0]
        except ValueError:
            pass
        print(red("  无效输入，请重试"))


def multi_select(
    prompt: str,
    items: list[tuple[str, str, str]],  # (key, label, risk)
    defaults: set[str],
    unavailable: Optional[dict[str, str]] = None,
) -> set[str]:
    """Show a toggle-style checklist, return selected keys.
    
    items: [(key, label, risk_level), ...]
    defaults: keys selected by default
    unavailable: key -> reason string for unavailable items
    """
    unavailable = unavailable or {}

    print(f"\n{prompt}\n")

    for i, (key, label, risk) in enumerate(items, 1):
        selected = key in defaults
        marker = green("[✓]") if selected else "[ ]"
        risk_label = {"low": "低风险", "medium": "中风险", "high": "高风险"}.get(risk, risk)
        suffix = ""
        if key in unavailable:
            suffix = dim(f" [不可用: {unavailable[key]}]")
            marker = dim("[ ]")
        print(f"  {i}) {marker} [{risk_label}] {label}{suffix}")

    print(f"\n  输入编号切换选择（如: 6 8），直接回车确认。")
    raw = input("  选择: ").strip()

    selected = set(defaults)
    if raw:
        for tok in raw.split():
            try:
                idx = int(tok) - 1
                if 0 <= idx < len(items):
                    key = items[idx][0]
                    if key in unavailable:
                        continue
                    if key in selected:
                        selected.discard(key)
                    else:
                        selected.add(key)
            except ValueError:
                pass

    # Show final selection
    print()
    for key, label, _ in items:
        if key in selected:
            print(f"    {green('[✓]')} {label}")
        else:
            print(f"    [ ] {label}")

    return selected


def confirm(prompt: str, default: bool = False) -> bool:
    """Ask yes/no question."""
    hint = "Y/n" if default else "y/N"
    raw = input(f"{prompt} [{hint}]: ").strip().lower()
    if not raw:
        return default
    return raw in ("y", "yes")


def info(msg: str) -> None:
    print(f"  {msg}")

def success(msg: str) -> None:
    print(f"  {green('✓')} {msg}")

def warn(msg: str) -> None:
    print(f"  {yellow('!')} {msg}")

def error(msg: str) -> None:
    print(f"  {red('✗')} {msg}")
