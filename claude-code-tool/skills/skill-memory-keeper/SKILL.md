---
name: skill-memory-keeper
description: |
  技能记忆管家 - 记录和管理所有skills的使用经验、问题痛点和改进建议。
  当用户说"记录这个skill问题"、"总结skill经验"、"skill使用记录"、"更新skill"、"快速总结"、"完整总结"时触发。
  支持user维度（跨项目）和project维度（项目特定）两种存储模式。
user-invocable: true
---

# Skill Memory Keeper - 技能记忆管家

## 功能概述

为所有skills提供统一的记忆和改进机制：

1. **实时记录**：捕获skill使用过程中的问题、痛点和用户偏好
2. **双维度存储**：user维度（跨项目共享）和project维度（项目特定）
3. **渐进式总结**：快速总结（增量）和完整总结（归档）
4. **智能更新**：将改进建议应用到对应的skill，保持SKILL.md精简

## 执行前准备（重要）

**在任何操作前，必须先了解目标skill的背景**：

1. **读取skill定义**
   - 目标skill的 `SKILL.md` - 了解功能、使用场景、规范
   - 目标skill的 `README.md`（如果存在）- 获取更多上下文

2. **读取历史经验**
   - `memory/{dimension}/quick-notes/{skill-name}/` - 快速笔记（增量经验）
   - `memory/{dimension}/archive/{skill-name}/` - 完整归档（历史总结）

**这样做的好处**：
- 避免重复记录已知问题
- 准确理解skill的定位和边界
- 识别问题模式（新问题 vs 反复出现的问题）
- 生成更准确的改进建议

## 存储结构

```
# 本项目 skill-memory-keeper 的存储
claude-code-tool/skills/skill-memory-keeper/
├── memory/
│   ├── user/                 # 用户维度（跨项目共享）
│   │   ├── records/          # 按skill分类的原始记录
│   │   │   └── {skill-name}/
│   │   │       ├── raw-{timestamp}.json
│   │   │       └── issues.json
│   │   ├── quick-notes/      # 快速总结的增量笔记
│   │   │   └── {skill-name}/
│   │   │       └── note-{date}.md
│   │   └── archive/          # 完整总结后的归档
│   │       └── {skill-name}/
│   │           └── summary-{date}.md
│   └── project/              # 项目维度（当前项目特定）
│       ├── records/
│       │   └── {skill-name}/
│       ├── quick-notes/
│       │   └── {skill-name}/
│       └── archive/
│           └── {skill-name}/
├── templates/
│   ├── record_template.json
│   └── summary_template.md
└── scripts/
    ├── record.py
    ├── summarize_quick.py     # 快速总结
    └── summarize_full.py      # 完整总结

# 被记录的 skill 的 SKILL.md 中添加链接
{skill-name}/SKILL.md:
## 经验总结

- [最新快速总结](../../skill-memory-keeper/memory/user/quick-notes/{skill-name}/note-{date}.md)
- [历史归档](../../skill-memory-keeper/memory/user/archive/{skill-name}/)
```

## 触发场景

### 主动触发
用户说以下内容时触发：
- "记录这个skill问题" / "记录到user" / "记录到project"
- "快速总结{skill-name}" / "总结新经验"
- "完整总结{skill-name}" / "归档总结"
- "skill使用记录" / "查看skill记忆"

### 维度选择

**User维度（默认）**：
- 跨项目共享的经验
- skill本身的问题（不依赖特定项目）
- 通用改进建议

**Project维度**：
- 项目特定的使用问题
- 与项目代码结构相关的痛点
- 项目内自定义配置相关

## 记录格式

### 原始记录 (raw-{timestamp}.json)

```json
{
  "timestamp": "2026-03-19T10:30:00Z",
  "skill_name": "skill-name",
  "dimension": "user|project",
  "summarized": false,
  "summary_ref": null,
  "trigger_context": "用户说xxx",
  "issue_type": "错误|性能|体验|功能|其他",
  "severity": "critical|major|minor",
  "description": "问题描述",
  "user_feedback": "用户原话",
  "context": {
    "command": "执行的命令",
    "input": "输入内容",
    "output": "输出摘要"
  },
  "environment": {
    "model": "模型版本",
    "platform": "平台信息"
  },
  "tags": ["标签1", "标签2"]
}
```

### 问题索引 (issues.json)

```json
{
  "skill_name": "skill-name",
  "dimension": "user|project",
  "last_updated": "2026-03-19T10:30:00Z",
  "issues": [
    {
      "id": "issue-001",
      "type": "错误",
      "count": 3,
      "first_seen": "2026-03-15",
      "last_seen": "2026-03-19",
      "severity": "major",
      "summary": "简短描述",
      "status": "pending|investigating|resolved"
    }
  ]
}
```

## 执行流程

### 流程 1: 实时记录

当检测到需要记录时：

1. **了解skill背景**（重要）
   - 读取目标skill的 `SKILL.md`，了解其功能和使用场景
   - 如果存在，读取 `README.md` 获取更多信息
   - 读取 `memory/{dimension}/quick-notes/{skill-name}/` 下最新的笔记（如果有）
   - 读取 `memory/{dimension}/archive/{skill-name}/` 下最近的归档（如果有）

2. **确定维度**
   - 基于对skill的理解，询问用户：这是skill本身的问题还是项目特定问题？
   - 默认为user维度
   - 使用AskUserQuestion让用户选择

3. **收集上下文**
   - 当前使用的skill名称
   - 用户输入和反馈
   - 执行结果
   - 环境信息

4. **检查是否重复**
   - 查阅 `issues.json`，检查是否有类似问题
   - 如果发现重复，更新计数而非创建新记录
   - 向用户说明该问题已记录X次

5. **创建记录**
   - 使用模板创建JSON记录
   - 保存到 `memory/{dimension}/records/{skill-name}/raw-{timestamp}.json`
   - 初始化 `summarized: false`
   - 更新问题索引

6. **确认记录**
   - 向用户展示记录内容
   - 显示维度信息
   - 如果是重复问题，显示累计次数

### 流程 2: 快速总结（Quick Summary）

**目标**：总结未总结过的记录，生成增量笔记

1. **了解skill背景**（重要）
   - 读取目标skill的 `SKILL.md`，了解其功能和使用场景
   - 如果存在，读取 `README.md` 获取更多信息
   - 读取 `memory/{dimension}/quick-notes/{skill-name}/` 下所有历史笔记（如果有）
   - 读取 `memory/{dimension}/archive/{skill-name}/` 下最近的归档（如果有）

2. **筛选未总结记录**
   - 读取 `memory/{dimension}/records/{skill-name}/` 下所有 `raw-*.json`
   - 筛选 `summarized: false` 的记录

3. **分析新增记录**
   - 按问题类型分组
   - 统计频率和严重程度
   - 识别新模式
   - 与历史经验对比，识别新出现或反复出现的问题

4. **生成快速笔记**
   - 保存到 `memory/{dimension}/quick-notes/{skill-name}/note-{date}.md`
   - 格式简洁，聚焦新增问题
   - 包含：新增问题概览、与历史对比、改进建议

5. **更新记录状态**
   - 将参与总结的记录标记为 `summarized: true`
   - 设置 `summary_ref` 指向笔记文件

6. **更新SKILL.md链接**
   - 检查目标skill的SKILL.md
   - 在末尾添加或更新"经验总结"章节
   - 添加指向最新快速笔记的链接

**快速笔记模板**：
```markdown
# {skill-name} 快速笔记

**日期**: {date}
**维度**: {user|project}
**本次总结记录数**: {count}

## 新增问题

| 类型 | 问题描述 | 次数 | 严重程度 |
|------|----------|------|----------|
| 体验 | xxx | 3 | minor |
| 错误 | xxx | 1 | major |

## 改进建议

1. **建议内容** - 关联问题: xxx
2. **建议内容** - 关联问题: xxx

## 相关记录

- raw-20260319_103000.json
- raw-20260319_140000.json
```

### 流程 3: 完整总结（Full Summary）

**目标**：总结所有记录，归档并清理memory

1. **了解skill背景**（重要）
   - 读取目标skill的 `SKILL.md`，了解其功能和使用场景
   - 如果存在，读取 `README.md` 获取更多信息
   - 读取 `memory/{dimension}/quick-notes/{skill-name}/` 下所有历史笔记
   - 读取 `memory/{dimension}/archive/{skill-name}/` 下所有历史归档
   - 分析历史经验，识别改进趋势和效果

2. **读取所有记录**
   - 包括已总结和未总结的记录
   - 生成完整的统计报告

3. **生成完整报告**
   - 保存到 `memory/{dimension}/archive/{skill-name}/summary-{date}.md`
   - 包含：历史趋势、所有问题汇总、改进效果评估
   - 与历史归档对比，展示问题变化趋势

4. **更新SKILL.md**
   - 将关键改进点写入SKILL.md
   - 添加归档链接
   - 保持SKILL.md精简

5. **清理Memory**
   - 删除已总结的原始记录
   - 更新issues.json状态
   - 保留quick-notes作为历史参考

**完整总结模板**：
```markdown
# {skill-name} 完整总结报告

**归档日期**: {date}
**维度**: {user|project}
**统计周期**: {start_date} 至 {end_date}

## 核心改进

基于本次总结，SKILL.md已更新以下内容：

1. **改进点1** - 原因: xxx - 效果: xxx
2. **改进点2** - 原因: xxx - 效果: xxx

## 历史问题汇总

### 已解决
| 问题 | 解决日期 | 方案 |
|------|----------|------|
| xxx | 2026-03-15 | xxx |

### 持续观察
| 问题 | 首次发现 | 最近出现 | 状态 |
|------|----------|----------|------|
| xxx | 2026-03-10 | 2026-03-19 | 观察中 |

## 统计数据

- 总记录数: {total}
- 问题类型分布: ...
- 严重程度分布: ...
```

### 流程 4: 应用更新（谨慎执行）

**重要**：更新其他skill的SKILL.md需要用户明确确认。

1. **展示变更**
   - 显示当前SKILL.md
   - 显示建议的修改
   - 标注变更原因和来源

2. **用户确认**
   - 使用AskUserQuestion获取确认
   - 选项：
     - 全部应用到SKILL.md
     - 仅添加链接，不修改内容
     - 跳过

3. **执行更新**
   - 仅更新用户确认的部分
   - 在SKILL.md末尾添加"经验总结"章节
   - 记录更新历史

## SKILL.md 链接格式

在目标skill的SKILL.md末尾添加：

```markdown
---

## 经验总结

### 最新笔记
- [2026-03-19 快速笔记](../skill-memory-keeper/memory/user/quick-notes/{skill-name}/note-2026-03-19.md)

### 历史归档
- [2026-03 完整总结](../skill-memory-keeper/memory/user/archive/{skill-name}/summary-2026-03-19.md)
- [2026-02 完整总结](../skill-memory-keeper/memory/user/archive/{skill-name}/summary-2026-02-15.md)

### 问题统计
- 当前跟踪问题: X 个
- 已解决问题: Y 个
```

## 输出格式

### 记录时输出

```
## 已记录 Skill 问题

**Skill**: {skill-name}
**维度**: {user|project}
**问题类型**: {type}
**严重程度**: {severity}

**问题描述**:
{description}

**记录位置**: memory/{dimension}/records/{skill-name}/raw-{timestamp}.json

该skill类似问题已出现 {count} 次
```

### 快速总结时输出

```
## 快速总结 - {skill-name}

**维度**: {user|project}
**新增记录**: {count} 条

### 新增问题
1. {issue_1} - {count}次
2. {issue_2} - {count}次

### 改进建议
1. {recommendation_1}

**笔记保存**: memory/{dimension}/quick-notes/{skill-name}/note-{date}.md
**SKILL.md已更新**: 添加了最新笔记链接

下次完整总结时再清理这些记录
```

### 完整总结时输出

```
## 完整总结 - {skill-name}

**维度**: {user|project}
**总记录数**: {total} 条

### 历史趋势
- 本周期新增: {new} 个问题
- 已解决: {resolved} 个问题

### 核心改进
1. {improvement_1} - 已应用到SKILL.md
2. {improvement_2} - 已应用到SKILL.md

**归档保存**: memory/{dimension}/archive/{skill-name}/summary-{date}.md
**原始记录已清理**: {deleted_count} 条记录已删除
**SKILL.md已更新**: 添加了关键改进和归档链接
```

## 关键原则

1. **双维度分离**
   - user维度：通用经验，跨项目共享
   - project维度：项目特定，不影响其他项目

2. **渐进式总结**
   - 快速总结：频繁执行，增量更新，不删除原始记录
   - 完整总结：定期执行，归档清理，更新SKILL.md

3. **保持SKILL.md精简**
   - 关键改进写入SKILL.md
   - 详细内容链接到外部文档
   - 避免文件膨胀

4. **状态追踪**
   - 每条记录标记总结状态
   - 支持增量处理
   - 避免重复总结

## 使用示例

### 示例 1: 记录问题（选择维度）

**用户**: "这个review-tracer每次都输出太多内容"

**你**:
> 我来记录这个问题。
>
> 请选择记录维度：
> - **user维度（推荐）**：这是review-tracer本身的问题，其他项目也会遇到
> - **project维度**：这是本项目特定的使用情况
>
> [默认选择user维度]

**用户**: [选择user维度]

**你**:
> 已记录：
>
> **Skill**: review-tracer
> **维度**: user
> **问题类型**: 体验
> **严重程度**: minor
> **问题描述**: 输出内容过多，影响阅读体验
>
> **记录位置**: memory/user/records/review-tracer/raw-20260319_103000.json

### 示例 2: 快速总结

**用户**: "快速总结review-tracer"

**你**:
> 正在分析review-tracer的未总结记录...
>
> 找到 5 条新记录：
>
> 新增问题：
> 1. 输出内容过多 - 3次 (体验)
> 2. 格式不统一 - 2次 (体验)
>
> 改进建议：
> 1. 添加detail_level配置项
>
> **笔记保存**: memory/user/quick-notes/review-tracer/note-2026-03-19.md
> **SKILL.md已更新**: 添加了最新笔记链接
>
> 这5条记录已标记为已总结，下次完整总结时会清理

### 示例 3: 完整总结

**用户**: "完整总结review-tracer"

**你**:
> 正在生成review-tracer的完整总结...
>
> 统计周期: 2026-03-01 至 2026-03-19
> 总记录数: 23 条
>
> 历史趋势：
> - 本周期新增: 5 个问题
> - 已解决: 2 个问题
>
> 核心改进（将应用到SKILL.md）：
> 1. 添加output配置章节，支持detail_level参数
> 2. 优化默认输出格式
>
> 准备更新review-tracer的SKILL.md，是否继续？
> - [是，应用改进]
> - [否，仅生成归档]
>
> **你**: [选择"是，应用改进"]
>
> **你**:
> 已更新review-tracer/SKILL.md：
> - 添加了"输出配置"章节
> - 添加了"经验总结"章节和链接
>
> **归档保存**: memory/user/archive/review-tracer/summary-2026-03-19.md
> **原始记录已清理**: 23条记录已删除/归档
