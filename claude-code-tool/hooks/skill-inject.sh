#!/bin/bash
# 在特定 superpowers 技能被调用时，注入额外的提示词
# 通过 PreToolUse hook 拦截 Skill 工具调用

python3 -c "
import json, sys

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

skill = ''
tool_input = data.get('tool_input')
if isinstance(tool_input, dict):
    skill = str(tool_input.get('skill', ''))

additional = None

# ---- 所有 superpowers skill 通用的目录规范 ----
is_superpowers = 'superpowers' in skill

if is_superpowers:
    # 获取当前项目根目录（从 cwd 向上查找含 .git 的目录）
    import subprocess, os
    try:
        project_root = subprocess.check_output(
            ['git', 'rev-parse', '--show-toplevel'],
            stderr=subprocess.DEVNULL
        ).decode().strip()
    except Exception:
        project_root = os.getcwd()

    dir_rule = (
        '【Skill 注入规则 - Superpowers 目录规范】\n'
        '所有 superpowers 生成的文件必须存放在统一的目录结构下：\n'
        f'- 主目录：{project_root}/.claude/.superpowers/\n'
        '- 子目录按主题划分，命名格式：\${yyyy-MM-dd}-\${主题简短标题}\n'
        '  例如：2026-04-06-knowledge-engine\n'
        '- 主题目录下存放该主题的所有文档（spec、plan、notes 等）\n'
        '  例如：\n'
        f'  {project_root}/.claude/.superpowers/2026-04-06-knowledge-engine/spec.md\n'
        f'  {project_root}/.claude/.superpowers/2026-04-06-knowledge-engine/plan.md\n'
        f'  {project_root}/.claude/.superpowers/2026-04-06-knowledge-engine/notes.md\n'
        '- 不同主题使用不同的子目录，禁止混放\n'
        '- 如果同一主题有多版本 spec/plan，用 v2、v3 等后缀区分\n'
        '此规则优先于 skill 自带的目录默认值（如 docs/superpowers/specs/ 等）。'
    )

    # 所有 superpowers skill 通用的文件写入字数控制
    write_rule = (
        '\n\n【Skill 注入规则 - 单文件写入字数控制】\n'
        '评估对单个文件的写入量。如果预计内容可能超过 1000 字（尤其是 plan、spec 等文档），必须拆分写入：\n'
        '- 单次写入目标为 500 字左右，绝对不要超过 1000 字\n'
        '- 超过时按模块/章节拆分为独立文件，通过文件间链接（相对路径）互相引用\n'
        '- 主文档只保留概述和索引，详细内容下沉到子文件\n'
        '例如：plan.md 只含目标、模块索引、关键决策；各模块详细设计放在 plan-<module>.md 中。'
    )

# ---- 特定 skill 的额外注入规则 ----
skill_specific = ''

if 'writing-plans' in skill:
    skill_specific = (
        '\n\n【Skill 注入规则 - 计划文档拆分流程】\n'
        '对于涉及多模块的 plan，按以下流程操作：\n'
        '1. 先划分模块，每个模块对应独立详细设计文档（放在对应主题目录下）\n'
        '2. 使用 agent 并行（并发度<=2）编写各模块文档\n'
        '3. 最后用一个 agent 合成精简主文档，链接到其他模块文档\n'
        '主文档聚焦：目标、架构概览、模块索引、关键决策。'
    )
elif 'subagent-driven-development' in skill:
    skill_specific = (
        '\n\n【Skill 注入规则 - Subagent 并发控制】\n'
        'subagent 的并发度不要超过 2。\n'
        '分批启动 agent，等待前一批完成后再启动下一批。'
    )

# ---- 组合输出 ----
if is_superpowers:
    additional = dir_rule + write_rule + skill_specific

if additional:
    print(json.dumps({
        'hookSpecificOutput': {
            'hookEventName': 'PreToolUse',
            'additionalContext': additional
        }
    }))

sys.exit(0)
"

exit 0
