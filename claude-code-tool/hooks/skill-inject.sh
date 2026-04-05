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

if 'writing-plans' in skill:
    additional = (
        '【Skill 注入规则 - 计划文档拆分】\n'
        '如果 plan 较大（涉及 3 个以上模块），请按以下流程：\n'
        '1. 先划分模块，每个模块对应独立详细设计文档（放在 plans/ 目录下）\n'
        '2. 使用 agent 并行（并发度<=2）编写各模块文档\n'
        '3. 最后用一个 agent 合成精简主文档，链接到其他模块文档\n'
        '主文档聚焦：目标、架构概览、模块索引、关键决策。\n'
        '各模块文档包含：详细设计、接口定义、实现步骤。'
    )
elif 'subagent-driven-development' in skill:
    additional = (
        '【Skill 注入规则 - Subagent 并发控制】\n'
        'subagent 的并发度不要超过 2。\n'
        '分批启动 agent，等待前一批完成后再启动下一批。'
    )

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
