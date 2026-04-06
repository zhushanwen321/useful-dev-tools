【Skill 注入规则 - Subagent 并发控制】
subagent 的并发度不要超过 2。
分批启动 agent，等待前一批完成后再启动下一批。