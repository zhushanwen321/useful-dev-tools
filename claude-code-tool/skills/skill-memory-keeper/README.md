# Skill Memory Keeper - 技能记忆管家

一个用于记录和管理所有 Claude Code skills 使用经验的元skill，支持双维度存储和渐进式总结。

## 核心特性

### 1. 双维度存储

**User维度（默认）**：
- 跨项目共享的通用经验
- skill本身的问题（不依赖特定项目）
- 存储路径：`memory/user/`

**Project维度**：
- 项目特定的使用问题
- 与项目代码结构相关的痛点
- 存储路径：`memory/project/`

### 2. 渐进式总结

**快速总结（Quick Summary）**：
- 仅总结未总结过的记录（`summarized: false`）
- 生成增量笔记
- 添加SKILL.md链接，不修改内容
- **不删除原始记录**

**完整总结（Full Summary）**：
- 总结所有记录
- 生成归档文档
- **更新SKILL.md内容**（关键改进点）
- **删除原始记录**（已归档）

### 3. 状态追踪

每条记录包含：
- `summarized`: 是否已总结
- `summary_ref`: 总结文档引用

支持增量处理，避免重复总结。

## 目录结构

```
skill-memory-keeper/
├── SKILL.md              # skill定义和执行流程
├── README.md             # 本文件
├── memory/               # 存储所有记录和总结
│   ├── user/             # 用户维度（跨项目）
│   │   ├── records/      # 原始记录
│   │   │   └── {skill-name}/
│   │   │       ├── raw-{timestamp}.json
│   │   │       └── issues.json
│   │   ├── quick-notes/  # 快速总结的增量笔记
│   │   │   └── {skill-name}/
│   │   │       └── note-{date}.md
│   │   └── archive/      # 完整总结后的归档
│   │       └── {skill-name}/
│   │           └── summary-{date}.md
│   └── project/          # 项目维度（项目特定）
│       └── (同上结构)
├── templates/            # 记录和总结模板
└── scripts/              # Python脚本
    ├── record.py         # 记录脚本
    ├── summarize_quick.py # 快速总结脚本
    └── summarize_full.py  # 完整总结脚本
```

## 使用方法

### 通过Claude Code使用

**记录问题**：
- "记录这个skill问题"
- "记录到user维度" / "记录到project维度"

**快速总结**：
- "快速总结{skill-name}"
- "总结新经验"

**完整总结**：
- "完整总结{skill-name}"
- "归档总结"

**查看状态**：
- "查看skill记忆"
- "列出未总结记录"

### 直接使用脚本

```bash
# 记录问题
python3 scripts/record.py \
  --skill skill-name \
  --dimension user \
  --type 体验 \
  --severity minor \
  --description "输出过多"

# 快速总结
python3 scripts/summarize_quick.py --skill skill-name --dimension user

# 完整总结
python3 scripts/summarize_full.py --skill skill-name --dimension user

# 列出所有skills
python3 scripts/summarize_quick.py --list --dimension user
```

## 记录格式

### 原始记录 (raw-{timestamp}.json)

```json
{
  "timestamp": "2026-03-19T10:30:00Z",
  "skill_name": "skill-name",
  "dimension": "user|project",
  "summarized": false,
  "summary_ref": null,
  "issue_type": "错误|性能|体验|功能|其他",
  "severity": "critical|major|minor",
  "description": "问题描述",
  "user_feedback": "用户原话",
  "context": {...},
  "environment": {...},
  "tags": []
}
```

## SKILL.md 链接格式

在目标skill的SKILL.md末尾添加：

```markdown
---

## 经验总结

### 最新笔记
- [2026-03-19 快速笔记](../skill-memory-keeper/memory/user/quick-notes/{skill-name}/note-2026-03-19.md)

### 历史归档
- [2026-03 完整总结](../skill-memory-keeper/memory/user/archive/{skill-name}/summary-2026-03-19.md)

### 问题统计
- 当前跟踪问题: X 个
- 已解决问题: Y 个
```

## 工作流程

### 快速总结流程（增量）

```
记录 → 未总结 → 快速总结 → 标记summarized=true → 添加SKILL.md链接
                    ↓
              生成note-{date}.md
              (原始记录保留)
```

### 完整总结流程（归档）

```
所有记录 → 完整总结 → 生成summary-{date}.md → 更新SKILL.md → 删除原始记录
                                   ↓
                            添加关键改进点
```

## 与其他skills的配合

| Skill | 记录内容 | 存储方式 | 配合方式 |
|-------|----------|----------|----------|
| bug-fix-recorder | 代码bug | JSON | 互补：不同层面的问题 |
| python-refactor-optimize | rope重构坑 | Markdown | 可互相引用 |
| skill-creator | 测试结果 | evals.json | skill-creator做大改，skill-memory-keeper做小改 |

## 设计原则

1. **不干扰主流程** - 记录在后台进行
2. **保持SKILL.md精简** - 详细内容链接到外部文档
3. **用户控制** - 所有更新需要确认
4. **渐进式改进** - 快速总结频繁，完整总结定期
5. **维度分离** - user/project独立管理

## 示例

### 示例 1: 记录问题（选择维度）

**用户**: "这个review-tracer每次都输出太多内容"

**你**:
> 请选择记录维度：
> - **user维度（推荐）**：这是review-tracer本身的问题
> - **project维度**：这是本项目特定的使用情况
>
> [默认user维度]
>
> 已记录到: memory/user/records/review-tracer/raw-20260319_103000.json

### 示例 2: 快速总结

**用户**: "快速总结review-tracer"

**你**:
> 找到 5 条未总结记录
>
> 新增问题：
> 1. 输出过多 - 3次
> 2. 格式不统一 - 2次
>
> 笔记保存: memory/user/quick-notes/review-tracer/note-2026-03-19.md
> SKILL.md已更新: 添加了最新笔记链接
>
> 下次完整总结时会清理这些记录

### 示例 3: 完整总结

**用户**: "完整总结review-tracer"

**你**:
> 总记录数: 23 条
>
> 核心改进（将应用到SKILL.md）：
> 1. 添加detail_level配置
> 2. 优化默认输出格式
>
> 是否更新SKILL.md？
> - [是，应用改进]
> - [否，仅归档]
>
> 归档保存: memory/user/archive/review-tracer/summary-2026-03-19.md
> 原始记录已清理: 23条已删除
