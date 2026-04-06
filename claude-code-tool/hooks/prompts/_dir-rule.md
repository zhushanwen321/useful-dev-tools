【Skill 注入规则 - Superpowers 目录规范】
所有 superpowers 生成的文件必须存放在统一的目录结构下：
- 主目录：{project_root}/.claude/.superpowers/
- 子目录按主题划分，命名格式：${yyyy-MM-dd}-${主题简短标题}
  例如：2026-04-06-knowledge-engine
- 主题目录下存放该主题的所有文档（spec、plan、notes 等）
  例如：
  {project_root}/.claude/.superpowers/2026-04-06-knowledge-engine/spec.md
  {project_root}/.claude/.superpowers/2026-04-06-knowledge-engine/plan.md
  {project_root}/.claude/.superpowers/2026-04-06-knowledge-engine/notes.md
- 不同主题使用不同的子目录，禁止混放
- 如果同一主题有多版本 spec/plan，用 v2、v3 等后缀区分
此规则优先于 skill 自带的目录默认值（如 docs/superpowers/specs/ 等）。