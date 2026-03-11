---
name: bug-fix-recorder
description: 记录 bug 修复到知识库。触发词："记录这个 bug"、"保存修复"、"添加到 bug-fix 库"、"总结这个修复"。
user-invocable: true
---

# Bug Fix Recorder

将 bug 修复结构化记录到全局知识库，便于未来快速定位类似问题。

## 触发条件

用户说以下任一短语时触发：
- "记录这个 bug"
- "保存这个修复"
- "添加到 bug-fix 库"
- "总结这个修复"

## 执行步骤

### 步骤 1: 收集信息

从对话上下文中提取以下信息：

| 字段 | 必填 | 示例 |
|------|------|------|
| language | ✅ | Python, TypeScript |
| frameworks | ✅ | SQLAlchemy, Vue 3 |
| title | ✅ | 简洁的问题标题 |
| description | ✅ | 问题描述 |
| error_message | ✅ | 完整错误信息 |
| root_cause | ✅ | 根本原因分析 |
| fix_method | ✅ | 修复方法 |
| severity | 默认 major | critical/major/minor |
| tags | 推荐 | database, async |
| before_code | 可选 | 修复前代码 |
| after_code | 可选 | 修复后代码 |
| related_files | 可选 | 相关文件路径 |

### 步骤 2: 调用 Agent

使用 Task tool 调用 `bug-fixer` agent：

```
Task tool:
  subagent_type: bug-fixer
  prompt: [包含收集的所有信息]
```

### 步骤 3: 验证结果

Agent 返回后，执行验证：

```bash
# 验证记录可被检索
python3 ~/.claude/agents/bug-fixer/bug_fixer.py search --language <language> --keyword "<title关键词>"
```

### 步骤 4: 向用户报告

展示创建结果：
- 文件路径
- 问题 ID
- 是否检测到类似问题

## 常用命令参考

```bash
# 记录问题
python3 ~/.claude/agents/bug-fixer/bug_fixer.py record \
  --language "Python" \
  --frameworks "SQLAlchemy" \
  --title "问题标题" \
  --description "问题描述" \
  --error-message "错误信息" \
  --root-cause "根本原因" \
  --fix-method "修复方法" \
  --tags "tag1,tag2" \
  --severity major

# 搜索问题
python3 ~/.claude/agents/bug-fixer/bug_fixer.py search --language python --tags database

# 查看统计
python3 ~/.claude/agents/bug-fixer/bug_fixer.py stats
```

## 存储结构

```
~/.claude/bug-fix-library/
├── python/
│   ├── database/
│   │   ├── 001-xxx.md
│   │   └── index.json
│   └── global_index.json
├── typescript/
│   └── ...
└── stats.json
```

## 标签规范

推荐使用以下标准化标签：
- `database` - 数据库相关
- `async` - 异步/并发问题
- `type-hint` - 类型注解问题
- `dependency` - 依赖问题
- `api` - API 相关
- `frontend` - 前端问题
- `tooling` - 工具配置
