"""skill-inject.py - 根据 skill 名称组合注入提示词

使用方式：从 stdin 读取 hook JSON，输出 additionalContext JSON
提示词文件放在同目录的 prompts/ 下，下划线前缀的为通用规则。
"""

import json
import os
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROMPTS_DIR = os.path.join(SCRIPT_DIR, "prompts")


def get_project_root():
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"],
            stderr=subprocess.DEVNULL,
        ).decode().strip()
    except Exception:
        return os.getcwd()


def load_prompt(filename):
    path = os.path.join(PROMPTS_DIR, filename)
    if not os.path.isfile(path):
        return ""
    with open(path) as f:
        return f.read().strip()


def find_skill_prompt(skill_name):
    """根据 skill 名匹配 prompts/ 下的文件（不含下划线前缀的通用文件）"""
    for filename in os.listdir(PROMPTS_DIR):
        if filename.startswith("_"):
            continue
        name, _ = os.path.splitext(filename)
        if name in skill_name:
            return load_prompt(filename)
    return ""


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        sys.exit(0)

    tool_input = data.get("tool_input")
    if not isinstance(tool_input, dict):
        sys.exit(0)

    skill = str(tool_input.get("skill", ""))
    if "superpowers" not in skill:
        sys.exit(0)

    project_root = get_project_root()

    # 通用目录规范（{project_root} 占位符替换）
    dir_rule = load_prompt("_dir-rule.md").replace("{project_root}", project_root)

    # 特定 skill 规则
    skill_rule = find_skill_prompt(skill)

    parts = [dir_rule]
    if skill_rule:
        parts.append(skill_rule)

    additional = "\n\n".join(parts)

    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "additionalContext": additional,
        }
    }))


if __name__ == "__main__":
    main()
