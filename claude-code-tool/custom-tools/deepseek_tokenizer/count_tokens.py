#!/usr/bin/env python3
"""Token 计数工具 — 基于 DeepSeek V3 BPE tokenizer，附带 Claude Code 粗略估算对比。

Claude Code 源码中的 token 估算策略（roughTokenCountEstimation）：
  - 普通文件：chars / 4
  - JSON 文件：chars / 2
本工具使用 BPE tokenizer 做更精确的本地计数，同时输出 Claude Code 风格的粗略估算供对比。

用法:
  python3 count_tokens.py --file <path>        统计单个文件
  python3 count_tokens.py --text "some text"   统计文本字符串
  echo "text" | python3 count_tokens.py --stdin  从管道读取
  python3 count_tokens.py --dir <path>         统计目录下所有文本文件
  python3 count_tokens.py --files a.md b.md    统计多个文件（汇总）
"""
import argparse
import os
import sys

TOKENIZER_DIR = os.path.dirname(os.path.abspath(__file__))
_tokenizer = None

CHARS_PER_TOKEN_DEFAULT = 4
CHARS_PER_TOKEN_JSON = 2


def get_tokenizer():
    global _tokenizer
    if _tokenizer is None:
        try:
            from transformers import AutoTokenizer
        except ImportError:
            print("错误: 缺少 transformers 库，请运行: pip3 install transformers", file=sys.stderr)
            sys.exit(1)
        _tokenizer = AutoTokenizer.from_pretrained(
            TOKENIZER_DIR, trust_remote_code=True
        )
    return _tokenizer


def count_tokens(text):
    """返回文本的 BPE token 数量。"""
    tokenizer = get_tokenizer()
    return len(tokenizer.encode(text))


def rough_estimate(chars, ext=""):
    """Claude Code 源码 roughTokenCountEstimation: chars/N。"""
    if ext in (".json", ".jsonl", ".jsonc"):
        return chars // CHARS_PER_TOKEN_JSON
    return chars // CHARS_PER_TOKEN_DEFAULT


def count_file(filepath):
    """读取文件并返回 (bpe_tokens, chars, rough_tokens)。"""
    with open(filepath, "r", encoding="utf-8", errors="replace") as f:
        content = f.read()
    ext = os.path.splitext(filepath)[1].lower()
    return count_tokens(content), len(content), rough_estimate(len(content), ext)


TEXT_EXTENSIONS = {
    ".md", ".txt", ".py", ".js", ".ts", ".tsx", ".jsx", ".vue",
    ".json", ".jsonl", ".jsonc", ".yaml", ".yml", ".toml",
    ".sh", ".bash", ".zsh", ".html", ".css", ".scss",
    ".rs", ".go", ".java", ".c", ".cpp", ".h", ".hpp",
    ".rb", ".php", ".sql", ".xml", ".svg",
}


def should_count(filepath):
    return os.path.splitext(filepath)[1].lower() in TEXT_EXTENSIONS


def count_directory(dirpath):
    """统计目录下所有文本文件的 token 数，返回 [(relpath, bpe_tokens, chars, rough)]。"""
    results = []
    for root, dirs, files in os.walk(dirpath):
        parts = root.split(os.sep)
        if any(p.startswith(".") for p in parts) or "node_modules" in parts:
            continue
        for fname in sorted(files):
            fpath = os.path.join(root, fname)
            if not should_count(fpath):
                continue
            try:
                bpe, chars, rough = count_file(fpath)
                rel = os.path.relpath(fpath, dirpath)
                results.append((rel, bpe, chars, rough))
            except Exception:
                continue
    return results


def fmt(n):
    return f"{n:,}"


def print_row(label, bpe, chars, rough=None):
    diff = ""
    if rough is not None and rough > 0:
        pct = (bpe - rough) / rough * 100
        sign = "+" if pct >= 0 else ""
        diff = f"  rough={fmt(rough)} ({sign}{pct:.0f}%)"
    print(f"  {label}: bpe={fmt(bpe)}  chars={fmt(chars)}{diff}")


def main():
    parser = argparse.ArgumentParser(description="Token 计数工具")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--file", help="统计单个文件")
    group.add_argument("--text", help="统计文本字符串")
    group.add_argument("--stdin", action="store_true", help="从 stdin 读取")
    group.add_argument("--dir", help="统计目录下所有文本文件")
    group.add_argument("--files", nargs="+", help="统计多个文件（汇总）")

    args = parser.parse_args()

    if args.text is not None:
        bpe = count_tokens(args.text)
        chars = len(args.text)
        rough = rough_estimate(chars)
        print(f"bpe={fmt(bpe)}  chars={fmt(chars)}  rough={fmt(rough)}  ratio={bpe/max(chars,1):.2f}")

    elif args.file:
        bpe, chars, rough = count_file(args.file)
        print_row(args.file, bpe, chars, rough)

    elif args.stdin:
        text = sys.stdin.read()
        bpe = count_tokens(text)
        chars = len(text)
        rough = rough_estimate(chars)
        print(f"bpe={fmt(bpe)}  chars={fmt(chars)}  rough={fmt(rough)}  ratio={bpe/max(chars,1):.2f}")

    elif args.files:
        total_bpe, total_chars, total_rough = 0, 0, 0
        for fp in args.files:
            if os.path.isfile(fp):
                bpe, chars, rough = count_file(fp)
                total_bpe += bpe
                total_chars += chars
                total_rough += rough
                print_row(fp, bpe, chars, rough)
        print(f"---")
        print_row("total", total_bpe, total_chars, total_rough)

    elif args.dir:
        results = count_directory(args.dir)
        if not results:
            print("未找到可统计的文本文件")
            return
        total_bpe, total_chars, total_rough = 0, 0, 0
        for rel, bpe, chars, rough in sorted(results, key=lambda x: -x[1]):
            total_bpe += bpe
            total_chars += chars
            total_rough += rough
            print_row(rel, bpe, chars, rough)
        print(f"---")
        print_row("total", total_bpe, total_chars, total_rough)


if __name__ == "__main__":
    main()
