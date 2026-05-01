#!/usr/bin/env python3
"""
Whitespace Fixer — Normalize indentation and whitespace in source files.

Usage:
    # Dry-run: show what would change (default)
    python3 fix_whitespace.py <file>

    # Actually fix the file in-place
    python3 fix_whitespace.py --fix <file>

    # Fix multiple files
    python3 fix_whitespace.py --fix file1.ts file2.py file3.rs

    # Detect only (exit 1 if issues found, useful for CI)
    python3 fix_whitespace.py --check <file>

    # Only fix specific issues
    python3 fix_whitespace.py --fix --issues tabs,trailing <file>

    # Normalize to tabs instead of spaces
    python3 fix_whitespace.py --fix --use-tabs <file>

    # Custom indent size
    python3 fix_whitespace.py --fix --indent-size 2 <file>

Supported languages: Python, Rust, TypeScript, JavaScript, Java, Go, C/C++, Ruby, Vue, JSX/TSX
Auto-detected from file extension. Falls back to generic handling for unknown types.

Issues fixed:
    1. tabs           — Hard tabs converted to spaces (or vice versa with --use-tabs)
    2. trailing       — Trailing whitespace on non-blank lines removed
    3. mixed-indent   — Lines that mix tabs and spaces in leading whitespace
    4. final-newline  — Ensures file ends with exactly one newline
    5. crlf           — Windows CRLF line endings converted to LF
    6. blank-lines    — Collapses runs of 3+ blank lines to 2

Exit codes:
    0 — No issues found (or --fix applied successfully)
    1 — Issues found (when using --check)
    2 — Error (file not found, etc.)
"""

import argparse
import os
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional


# ── Language config ──────────────────────────────────────────────────

@dataclass
class LangConfig:
    """Per-language whitespace conventions."""
    default_indent: int = 4          # spaces per indent level
    use_tabs: bool = False           # prefer hard tabs
    has_multiline_strings: bool = False  # whether language has multiline strings
    extensions: tuple = ()

    @property
    def effective_indent(self) -> int:
        return self.default_indent


LANG_CONFIGS = {
    "python":     LangConfig(default_indent=4, has_multiline_strings=True,
                             extensions=(".py", ".pyw", ".pyi")),
    "rust":       LangConfig(default_indent=4, has_multiline_strings=True,
                             extensions=(".rs",)),
    "typescript": LangConfig(default_indent=2, has_multiline_strings=True,
                             extensions=(".ts", ".tsx")),
    "javascript": LangConfig(default_indent=2, has_multiline_strings=True,
                             extensions=(".js", ".jsx", ".mjs", ".cjs")),
    "java":       LangConfig(default_indent=4, extensions=(".java",)),
    "go":         LangConfig(default_indent=4, use_tabs=True, extensions=(".go",)),
    "c":          LangConfig(default_indent=4, extensions=(".c", ".h")),
    "cpp":        LangConfig(default_indent=4, extensions=(".cpp", ".hpp", ".cc", ".cxx", ".hxx")),
    "ruby":       LangConfig(default_indent=2, has_multiline_strings=True,
                             extensions=(".rb",)),
    "vue":        LangConfig(default_indent=2, has_multiline_strings=True,
                             extensions=(".vue",)),
    "svelte":     LangConfig(default_indent=2, has_multiline_strings=True,
                             extensions=(".svelte",)),
    "css":        LangConfig(default_indent=2, extensions=(".css", ".scss", ".less", ".sass")),
    "html":       LangConfig(default_indent=2, extensions=(".html", ".htm", ".xml", ".svg")),
    "yaml":       LangConfig(default_indent=2, extensions=(".yml", ".yaml")),
    "toml":       LangConfig(default_indent=2, extensions=(".toml",)),
    "json":       LangConfig(default_indent=2, extensions=(".json",)),
    "markdown":   LangConfig(default_indent=4, extensions=(".md", ".mdx")),
    "shell":      LangConfig(default_indent=4, has_multiline_strings=True,
                             extensions=(".sh", ".bash", ".zsh")),
}

# Extension → language name lookup
EXT_MAP: dict[str, str] = {}
for lang, cfg in LANG_CONFIGS.items():
    for ext in cfg.extensions:
        EXT_MAP[ext] = lang


def detect_language(filepath: str) -> str:
    """Detect language from file extension."""
    ext = Path(filepath).suffix.lower()
    return EXT_MAP.get(ext, "unknown")


# ── Multi-line string tracking ──────────────────────────────────────

def _find_python_multiline(lines: list[str], inside_ranges: set[int]) -> None:
    """Find Python triple-quote string ranges."""
    i = 0
    while i < len(lines):
        line = lines[i]
        for quote in ('"""', "'''"):
            start_col = 0
            while True:
                pos = line.find(quote, start_col)
                if pos == -1:
                    break
                # Check if it's escaped
                if pos > 0 and line[pos - 1] == '\\':
                    n_backslashes = 0
                    p = pos - 1
                    while p >= 0 and line[p] == '\\':
                        n_backslashes += 1
                        p -= 1
                    if n_backslashes % 2 == 1:
                        start_col = pos + len(quote)
                        continue

                rest_of_line = line[pos + 3:]
                close_pos = rest_of_line.find(quote)
                if close_pos != -1:
                    start_col = pos + 3 + close_pos + 3
                    continue

                inside_ranges.add(i)
                j = i + 1
                while j < len(lines):
                    inside_ranges.add(j)
                    if quote in lines[j]:
                        break
                    j += 1
                i = j
                break
            else:
                continue
            break
        i += 1


def _find_rust_multiline(lines: list[str], inside_ranges: set[int]) -> None:
    """Find Rust raw string r#"..."# and regular string ranges."""
    # Track raw strings: r#"..."#, r##"..."##, etc.
    i = 0
    while i < len(lines):
        line = lines[i]
        # Find raw string openings: r#", r##", etc.
        col = 0
        while col < len(line):
            # Look for r#" pattern
            idx = line.find('r#"', col)
            if idx == -1:
                break
            # Count hashes
            hash_start = idx + 1
            n_hashes = 0
            p = hash_start
            while p < len(line) and line[p] == '#':
                n_hashes += 1
                p += 1
            if p >= len(line) or line[p] != '"':
                col = idx + 1
                continue

            close_marker = '"' + '#' * n_hashes
            rest = line[p + 1:]  # after the opening "
            close_pos = rest.find(close_marker)
            if close_pos != -1:
                col = p + 1 + close_pos + len(close_marker)
                continue  # same-line close

            inside_ranges.add(i)
            j = i + 1
            while j < len(lines):
                inside_ranges.add(j)
                if close_marker in lines[j]:
                    break
                j += 1
            i = j
            break
        else:
            i += 1
            continue
        i += 1


def _find_template_literals(lines: list[str], inside_ranges: set[int]) -> None:
    """Find JS/TS template literal `...` ranges."""
    i = 0
    while i < len(lines):
        line = lines[i]
        col = 0
        while col < len(line):
            idx = line.find('`', col)
            if idx == -1:
                break
            # Check if escaped
            if idx > 0 and line[idx - 1] == '\\':
                n = 0
                p = idx - 1
                while p >= 0 and line[p] == '\\':
                    n += 1
                    p -= 1
                if n % 2 == 1:
                    col = idx + 1
                    continue

            rest = line[idx + 1:]
            close_pos = rest.find('`')
            if close_pos != -1:
                col = idx + 1 + close_pos + 1
                continue  # same-line close

            inside_ranges.add(i)
            j = i + 1
            while j < len(lines):
                inside_ranges.add(j)
                if '`' in lines[j]:
                    break
                j += 1
            i = j
            break
        else:
            i += 1
            continue
        i += 1


def find_multiline_string_ranges(lines: list[str], lang: str) -> set[int]:
    """
    Return set of line indices (0-based) that are inside multi-line strings.
    Supports: Python triple-quotes, Rust raw strings, JS/TS template literals.
    """
    inside_ranges: set[int] = set()

    if lang == "python":
        _find_python_multiline(lines, inside_ranges)
    elif lang == "rust":
        _find_rust_multiline(lines, inside_ranges)
    elif lang in ("typescript", "javascript"):
        _find_template_literals(lines, inside_ranges)
    elif lang == "ruby":
        # Ruby has heredocs and multi-line strings — simplified detection
        _find_template_literals(lines, inside_ranges)

    return inside_ranges


# ── Project config detection ────────────────────────────────────────

def detect_indent_from_file(filepath: str) -> tuple[int, bool]:
    """
    Heuristically detect indentation from file content.
    Returns (indent_size, uses_tabs).
    """
    try:
        with open(filepath, "r", encoding="utf-8", errors="replace") as f:
            content = f.read()
    except Exception:
        return (0, False)

    # Normalize line endings for detection
    content = content.replace("\r\n", "\n").replace("\r", "\n")
    lines = content.split("\n")

    tab_lines = 0
    space_lines = 0
    space_indents: list[int] = []

    for line in lines[:500]:  # sample first 500 lines
        if not line.strip():
            continue
        leading = line[:len(line) - len(line.lstrip())]
        if "\t" in leading:
            tab_lines += 1
        elif leading and leading[0] == " ":
            space_lines += 1
            indent_len = len(leading)
            if indent_len > 0:
                space_indents.append(indent_len)

    # Determine tabs vs spaces
    uses_tabs = tab_lines > space_lines

    if uses_tabs:
        return (0, True)

    # Guess indent size from most common GCD of space indents
    if not space_indents:
        return (0, False)

    from collections import Counter
    sizes = [s for s in space_indents if s <= 8]
    if not sizes:
        return (0, False)

    # Try common sizes: 2, 4, 8
    size_counts = Counter()
    for s in sizes:
        for candidate in (2, 4, 8):
            if s % candidate == 0:
                size_counts[candidate] += 1

    if size_counts:
        best = size_counts.most_common(1)[0][0]
        return (best, False)

    return (0, False)


def detect_editorconfig(filepath: str) -> Optional[dict]:
    """Parse nearest .editorconfig for the given file path."""
    path = Path(filepath).resolve()
    for parent in path.parents:
        ec_path = parent / ".editorconfig"
        if ec_path.is_file():
            try:
                return parse_editorconfig(ec_path, path.name)
            except Exception:
                continue
    return None


def parse_editorconfig(ec_path: Path, filename: str) -> dict:
    """Minimal .editorconfig parser (handles [*] and simple globs)."""
    import fnmatch
    config: dict = {}
    in_section = False

    with open(ec_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or line.startswith(";"):
                continue
            if line.startswith("["):
                pattern = line.strip("[]").strip()
                if pattern == "*":
                    in_section = True
                else:
                    in_section = fnmatch.fnmatch(filename, pattern)
                continue
            if in_section and "=" in line:
                key, _, val = line.partition("=")
                config[key.strip().lower()] = val.strip().lower()

    return config


# ── Issue detection and fixing ──────────────────────────────────────

@dataclass
class Issue:
    line: int
    col: int
    severity: str      # "error" | "warning"
    category: str      # tabs, trailing, mixed-indent, crlf, final-newline, blank-lines
    message: str
    original: str = ""
    fixed: str = ""


@dataclass
class FixResult:
    filepath: str
    language: str
    issues: list[Issue] = field(default_factory=list)
    original_content: str = ""
    fixed_content: str = ""
    changed: bool = False

    @property
    def issue_count(self) -> int:
        return len(self.issues)

    @property
    def error_count(self) -> int:
        return sum(1 for i in self.issues if i.severity == "error")

    @property
    def warning_count(self) -> int:
        return sum(1 for i in self.issues if i.severity == "warning")


def expand_tabs_in_line(line: str, tab_size: int) -> str:
    """Expand tabs to spaces, preserving alignment for non-leading tabs."""
    stripped = line.lstrip(" \t")
    leading_len = len(line) - len(stripped)
    leading = line[:leading_len]

    # Expand leading tabs: each tab → next multiple of tab_size
    new_leading = []
    col = 0
    for ch in leading:
        if ch == "\t":
            spaces = tab_size - (col % tab_size)
            new_leading.append(" " * spaces)
            col += spaces
        else:
            new_leading.append(ch)
            col += 1

    # Expand non-leading tabs literally (tab_size spaces each)
    rest = stripped.expandtabs(tab_size)

    return "".join(new_leading) + rest


def spaces_to_tabs_in_line(line: str, tab_size: int) -> str:
    """Convert leading spaces to tabs."""
    stripped = line.lstrip(" ")
    leading_len = len(line) - len(stripped)

    n_tabs = leading_len // tab_size
    remainder = leading_len % tab_size

    return "\t" * n_tabs + " " * remainder + stripped


def analyze_file(
    filepath: str,
    indent_size: Optional[int] = None,
    use_tabs: Optional[bool] = None,
    filter_issues: Optional[list[str]] = None,
) -> FixResult:
    """
    Analyze a file for whitespace issues.
    Returns FixResult with detected issues and the fixed content.
    """
    lang = detect_language(filepath)
    lang_cfg = LANG_CONFIGS.get(lang, LangConfig())

    # Detect from file heuristics
    detected_size, detected_tabs = detect_indent_from_file(filepath)

    # Detect from .editorconfig
    ec_config = detect_editorconfig(filepath)

    # Priority: CLI args > .editorconfig > heuristics > language default
    if indent_size is not None:
        final_indent = indent_size
    elif ec_config and "indent_size" in ec_config:
        try:
            final_indent = int(ec_config["indent_size"])
        except ValueError:
            final_indent = detected_size or lang_cfg.effective_indent
    else:
        final_indent = detected_size or lang_cfg.effective_indent

    if use_tabs is not None:
        final_use_tabs = use_tabs
    elif ec_config and "indent_style" in ec_config:
        final_use_tabs = ec_config["indent_style"] == "tab"
    elif detected_tabs:
        final_use_tabs = True
    else:
        final_use_tabs = lang_cfg.use_tabs

    # Go always uses tabs
    if lang == "go":
        final_use_tabs = True

    # When heuristics detected tabs and no other config overrides,
    # respect the file's existing style (important for Java files that use tabs)
    if use_tabs is None and (not ec_config or "indent_style" not in ec_config):
        if detected_tabs:
            final_use_tabs = True
            if final_indent == 0:
                final_indent = lang_cfg.effective_indent

    try:
        with open(filepath, "rb") as f:
            raw_content = f.read()
    except FileNotFoundError:
        print(f"Error: file not found: {filepath}", file=sys.stderr)
        sys.exit(2)
    except Exception as e:
        print(f"Error reading {filepath}: {e}", file=sys.stderr)
        sys.exit(2)

    # Decode content
    content = raw_content.decode("utf-8", errors="replace")

    result = FixResult(
        filepath=filepath,
        language=lang,
        original_content=content,
    )

    # ── Step 1: Fix CRLF → LF ───────────────────────────────────────
    has_crlf = "\r\n" in content
    if has_crlf:
        if not filter_issues or "crlf" in filter_issues:
            # Count CRLF lines
            crlf_lines = content.count("\r\n")
            result.issues.append(Issue(
                line=1, col=1,
                severity="error", category="crlf",
                message=f"CRLF line endings detected ({crlf_lines} lines)",
            ))
            content = content.replace("\r\n", "\n")

    # Also handle bare CR (old Mac style)
    if "\r" in content and "\r\n" not in content:
        if not filter_issues or "crlf" in filter_issues:
            content = content.replace("\r", "\n")

    # ── Step 2: Split into lines ────────────────────────────────────
    lines = content.split("\n")

    # Handle trailing newline: split on "\n" produces an extra empty string
    # if content ends with "\n". Remove it for processing, add back later.
    had_trailing_newline = content.endswith("\n") if content else False
    if had_trailing_newline and lines and lines[-1] == "":
        lines = lines[:-1]

    # ── Step 3: Find multi-line string ranges to skip ───────────────
    skip_lines = find_multiline_string_ranges(lines, lang)

    # ── Step 4: Fix tabs / mixed-indent ─────────────────────────────
    fixed_lines = list(lines)

    for i, line in enumerate(lines):
        if i in skip_lines:
            continue  # don't touch lines inside multi-line strings

        line_num = i + 1
        stripped = line.lstrip(" \t")
        leading_len = len(line) - len(stripped)
        leading = line[:leading_len]

        # Mixed indent (tabs + spaces in leading whitespace)
        if "\t" in leading and " " in leading and not final_use_tabs:
            if not filter_issues or "mixed-indent" in filter_issues:
                fixed_line = expand_tabs_in_line(line, final_indent or 4)
                result.issues.append(Issue(
                    line=line_num, col=1,
                    severity="error", category="mixed-indent",
                    message="Mixed tabs and spaces in leading whitespace",
                    original=line, fixed=fixed_line,
                ))
                fixed_lines[i] = fixed_line

        # Hard tabs (when should use spaces)
        elif "\t" in leading and not final_use_tabs:
            if not filter_issues or "tabs" in filter_issues:
                fixed_line = expand_tabs_in_line(line, final_indent or 4)
                result.issues.append(Issue(
                    line=line_num, col=1,
                    severity="error", category="tabs",
                    message=f"Hard tab found (expected {final_indent} spaces)",
                    original=line, fixed=fixed_line,
                ))
                fixed_lines[i] = fixed_line

        # Spaces where tabs expected
        elif " " in leading and final_use_tabs and leading_len > 0:
            if not filter_issues or "tabs" in filter_issues:
                fixed_line = spaces_to_tabs_in_line(line, final_indent or 4)
                result.issues.append(Issue(
                    line=line_num, col=1,
                    severity="error", category="tabs",
                    message="Spaces found (expected tabs)",
                    original=line, fixed=fixed_line,
                ))
                fixed_lines[i] = fixed_line

    # ── Step 5: Fix trailing whitespace ─────────────────────────────
    for i, line in enumerate(fixed_lines):
        if i in skip_lines:
            continue
        line_num = i + 1

        # Trailing whitespace (on non-blank lines only)
        if line != line.rstrip(" \t") and line.strip():
            if not filter_issues or "trailing" in filter_issues:
                fixed_line = line.rstrip(" \t")
                result.issues.append(Issue(
                    line=line_num, col=len(fixed_line) + 1,
                    severity="warning", category="trailing",
                    message="Trailing whitespace",
                    original=line, fixed=fixed_line,
                ))
                fixed_lines[i] = fixed_line

    # ── Step 6: Collapse blank lines ────────────────────────────────
    if not filter_issues or "blank-lines" in filter_issues:
        new_lines = []
        blank_run = 0
        for i, line in enumerate(fixed_lines):
            if line.strip() == "":
                blank_run += 1
                if blank_run <= 2:
                    new_lines.append(line)
                # else: skip (collapse)
            else:
                if blank_run > 2:
                    result.issues.append(Issue(
                        line=i - blank_run + 1, col=1,
                        severity="warning", category="blank-lines",
                        message=f"Collapsed {blank_run} consecutive blank lines to 2",
                    ))
                blank_run = 0
                new_lines.append(line)
        # Handle trailing blank lines
        if blank_run > 2:
            result.issues.append(Issue(
                line=len(fixed_lines) - blank_run + 1, col=1,
                severity="warning", category="blank-lines",
                message=f"Collapsed {blank_run} trailing blank lines to 1",
            ))
            new_lines.append("")  # keep one trailing blank
        fixed_lines = new_lines

    # ── Step 7: Ensure final newline ─────────────────────────────────
    if not filter_issues or "final-newline" in filter_issues:
        if not had_trailing_newline and content:
            result.issues.append(Issue(
                line=len(fixed_lines) + 1, col=1,
                severity="warning", category="final-newline",
                message="File does not end with a newline",
            ))

    # ── Reconstruct content ─────────────────────────────────────────
    fixed_content = "\n".join(fixed_lines)
    if fixed_content:  # always ensure trailing newline for non-empty files
        fixed_content += "\n"

    result.fixed_content = fixed_content
    result.changed = (result.original_content != fixed_content)

    return result


# ── Extract exact lines for edit tool ───────────────────────────────

def extract_lines(filepath: str, start_line: int, end_line: int) -> str:
    """
    Extract exact text from a file for use with the edit tool.
    Reads raw bytes to preserve exact whitespace.
    """
    try:
        with open(filepath, "r", encoding="utf-8", errors="replace") as f:
            lines = f.readlines()
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(2)

    # Convert to 0-indexed
    start = max(0, start_line - 1)
    end = min(len(lines), end_line)

    return "".join(lines[start:end])


def show_invisible(text: str) -> str:
    """Show invisible characters for debugging."""
    return text.replace("\t", "→").replace(" ", "·")


# ── Output formatters ───────────────────────────────────────────────

def format_diff(result: FixResult, show_invisibles: bool = False) -> str:
    """Show a unified-diff style output of changes."""
    if not result.changed:
        return f"✓ {result.filepath} — no issues found"

    orig_lines = result.original_content.splitlines(keepends=True)
    fixed_lines = result.fixed_content.splitlines(keepends=True)

    output = []
    output.append(f"{'─' * 60}")
    output.append(f"  {result.filepath} ({result.language})")
    output.append(f"  {result.issue_count} issue(s): {result.error_count} errors, {result.warning_count} warnings")
    output.append(f"{'─' * 60}")

    # Group issues by category
    from collections import defaultdict
    by_cat: dict[str, list[Issue]] = defaultdict(list)
    for issue in result.issues:
        by_cat[issue.category].append(issue)

    for cat, issues in by_cat.items():
        output.append(f"\n  [{cat}] ({len(issues)} issue(s))")
        for issue in issues[:10]:  # limit display
            output.append(f"    L{issue.line}: {issue.message}")
            if show_invisibles and issue.original:
                output.append(f"      was: {show_invisible(issue.original.rstrip())}")
            if show_invisibles and issue.fixed:
                output.append(f"      fix: {show_invisible(issue.fixed.rstrip())}")
        if len(issues) > 10:
            output.append(f"    ... and {len(issues) - 10} more")

    # Show diff
    output.append(f"\n  Diff:")
    output.append(f"  {'-' * 56}")

    import difflib
    diff = difflib.unified_diff(
        orig_lines, fixed_lines,
        fromfile=f"{result.filepath} (original)",
        tofile=f"{result.filepath} (fixed)",
        lineterm="",
    )
    diff_lines = list(diff)
    if diff_lines:
        for dl in diff_lines[:60]:  # limit output
            output.append(f"  {dl}")
        if len(diff_lines) > 60:
            output.append(f"  ... ({len(diff_lines) - 60} more diff lines)")
    else:
        output.append("  (no textual diff)")

    return "\n".join(output)


def format_json(result: FixResult) -> str:
    """Output results as JSON for programmatic use."""
    import json
    return json.dumps({
        "filepath": result.filepath,
        "language": result.language,
        "changed": result.changed,
        "issue_count": result.issue_count,
        "error_count": result.error_count,
        "warning_count": result.warning_count,
        "issues": [
            {
                "line": i.line,
                "col": i.col,
                "severity": i.severity,
                "category": i.category,
                "message": i.message,
            }
            for i in result.issues
        ],
    }, indent=2, ensure_ascii=False)


def format_summary(results: list[FixResult]) -> str:
    """Print a summary of all files processed."""
    total_issues = sum(r.issue_count for r in results)
    total_errors = sum(r.error_count for r in results)
    total_warnings = sum(r.warning_count for r in results)
    changed_files = sum(1 for r in results if r.changed)
    clean_files = sum(1 for r in results if not r.changed)

    lines = [
        "",
        "═" * 50,
        "  WHITESPACE FIXER — SUMMARY",
        "═" * 50,
        f"  Files scanned:  {len(results)}",
        f"  Clean files:    {clean_files}",
        f"  Changed files:  {changed_files}",
        f"  Total issues:   {total_issues} ({total_errors} errors, {total_warnings} warnings)",
        "═" * 50,
    ]

    if changed_files > 0:
        lines.append("  Files with issues:")
        for r in results:
            if r.changed:
                lines.append(f"    • {r.filepath} ({r.language}): {r.issue_count} issue(s)")
        lines.append("═" * 50)

    return "\n".join(lines)


# ── Main ─────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Whitespace Fixer — Normalize indentation and whitespace in source files",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "files", nargs="+",
        help="File(s) to check/fix",
    )
    parser.add_argument(
        "--fix", action="store_true",
        help="Apply fixes in-place (default: dry-run)",
    )
    parser.add_argument(
        "--check", action="store_true",
        help="Exit with code 1 if any issues found (for CI)",
    )
    parser.add_argument(
        "--json", action="store_true",
        help="Output results as JSON",
    )
    parser.add_argument(
        "--issues", type=str,
        help="Comma-separated list of issue categories to fix "
             "(tabs,trailing,mixed-indent,crlf,final-newline,blank-lines)",
    )
    parser.add_argument(
        "--indent-size", type=int,
        help="Override indent size (e.g. 2 or 4)",
    )
    parser.add_argument(
        "--use-tabs", action="store_true",
        help="Use tabs instead of spaces",
    )
    parser.add_argument(
        "--show-invisibles", action="store_true",
        help="Show tabs (→) and spaces (·) in output",
    )
    parser.add_argument(
        "--extract", type=str,
        help="Extract exact text for edit tool. Format: start:end (1-indexed, inclusive)",
    )

    args = parser.parse_args()

    # Handle extract mode
    if args.extract:
        for filepath in args.files:
            parts = args.extract.split(":")
            start, end = int(parts[0]), int(parts[1])
            text = extract_lines(filepath, start, end)
            sys.stdout.write(text)
        return

    # Parse issue filter
    filter_issues = None
    if args.issues:
        filter_issues = [i.strip() for i in args.issues.split(",")]

    results: list[FixResult] = []
    has_issues = False

    for filepath in args.files:
        if not os.path.isfile(filepath):
            print(f"Warning: skipping non-file: {filepath}", file=sys.stderr)
            continue

        result = analyze_file(
            filepath,
            indent_size=args.indent_size,
            use_tabs=args.use_tabs if args.use_tabs else None,
            filter_issues=filter_issues,
        )

        if args.json:
            print(format_json(result))
        else:
            print(format_diff(result, show_invisibles=args.show_invisibles))

        if result.changed:
            has_issues = True

            if args.fix:
                try:
                    with open(filepath, "w", encoding="utf-8") as f:
                        f.write(result.fixed_content)
                    print(f"\n  ✓ Fixed and saved: {filepath}")
                except Exception as e:
                    print(f"\n  ✗ Error saving {filepath}: {e}", file=sys.stderr)
                    sys.exit(2)

        results.append(result)

    # Summary for multiple files
    if len(results) > 1 and not args.json:
        print(format_summary(results))

    # Exit code for --check mode
    if args.check and has_issues:
        sys.exit(1)


if __name__ == "__main__":
    main()
