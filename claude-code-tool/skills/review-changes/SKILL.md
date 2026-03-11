---
name: review-changes
description: |
  审查和提交指定目录下的代码变更。使用场景：(1) 用户想批量审查未提交的代码变更，(2) 用户说 "/review-changes" 或 "审查变更" 或 "review changes"，(3) 用户想对代码变更进行简化、审查和自动提交。
  接收一个目录参数，列出未提交的变更文件，智能分组后让用户选择要审查的分组，然后对选中的分组依次执行 pr-review-toolkit:code-reviewer（发现问题）和 pr-review-toolkit:code-simplifier（边修复边简化），每组完成后自动提交。
---

# Review Changes - 代码变更审查与提交流程

## 功能概述

对指定目录下的未提交代码变更进行分组审查和提交：
1. 列出变更文件
2. 智能分组
3. **用户选择要审查的分组**
4. 审查代码 → 带着问题修复+简化 → 提交

## 使用方式

```
/review-changes <directory>
```

示例：
- `/review-changes backend/`
- `/review-changes frontend/src/`
- `/review-changes .` (整个项目)

## 执行流程

### 步骤 1: 获取变更文件列表

运行以下命令获取指定目录下未提交的变更：

```bash
git status --porcelain -- <directory>
```

分析输出，提取：
- `M ` - 已修改的文件
- `A ` - 已添加的文件
- `MM` - 已修改且已暂存的文件
- `??` - 未跟踪的新文件（可选包含）

### 步骤 2: 智能分组

根据以下原则将文件分组：

1. **功能相关性**：同一功能/特性的文件放在一组
2. **目录结构**：同一模块/子目录的文件优先放在一起
3. **依赖关系**：有依赖关系的文件放在同一组
4. **文件数量**：每组控制在 3-7 个文件，避免过多

分组示例：
- 配置文件 + 数据库迁移 → 一组
- API 路由 + 服务层 + 测试 → 一组
- 前端组件 + 样式 + 类型定义 → 一组

### 步骤 3: 用户确认分组

**关键步骤**：分组后必须让用户确认要审查哪些组。

使用 AskUserQuestion 工具，multiSelect=true，让用户选择：

```
AskUserQuestion with:
  question: "已将变更文件分为以下 N 组，请选择要审查的分组："
  header: "选择分组"
  multiSelect: true
  options:
    - label: "分组 1: <分组名称> (N 个文件)"
      description: "包含: file1.py, file2.py, ..."
    - label: "分组 2: <分组名称> (N 个文件)"
      description: "包含: file3.py, file4.py, ..."
    - label: "[全选]"
      description: "审查所有分组"
    - label: "[跳过所有]"
      description: "不审查任何分组，直接退出"
```

根据用户选择，只对选中的分组执行后续步骤。

### 步骤 4: 处理每个分组

对每个分组依次执行：

#### 4a. 代码审查（先发现问题）

使用 Agent 工具调用 pr-review-toolkit:code-reviewer agent：

```
Agent tool with subagent_type="pr-review-toolkit:code-reviewer"
prompt: "请审查以下文件：<文件列表>"
```

记录审查发现的所有问题，包括：
- 代码质量问题
- 潜在 bug
- 性能问题
- 代码风格问题
- 项目规范符合性

#### 4b. 修复问题 + 代码简化（带着审查问题去处理）

使用 Task 工具调用 pr-review-toolkit:code-simplifier agent，**将审查发现的问题一起传入**：

```
Task tool with subagent_type="pr-review-toolkit:code-simplifier"
prompt: "请处理以下文件，同时解决这些审查问题：

文件列表：<文件列表>

审查发现的问题：
1. <问题 1>
2. <问题 2>
...

请在简化代码的同时修复这些问题。"
```

这样 pr-review-toolkit:code-simplifier 可以在简化代码的同时修复审查发现的问题。

#### 4c. 提交变更

使用 Skill 工具调用 commit skill：

```
Skill tool with skill="commit-commands:commit"
```

根据分组内容生成合适的提交信息。

### 步骤 5: 循环处理

重复步骤 4 直到所有用户选中的分组处理完成。

## 输出格式

```
## 变更审查报告

### 发现 X 个变更文件，已分为 N 组

#### 分组预览

| 分组 | 名称 | 文件数 | 文件列表 |
|------|------|--------|----------|
| 1 | 数据库配置 | 3 | migrations/..., config.py, ... |
| 2 | API 端点 | 4 | routes/..., services/..., ... |
| 3 | 前端组件 | 2 | components/..., styles/... |

#### 用户选择: 审查分组 1, 2（跳过分组 3）

#### 分组 1: <分组名称> (N 个文件)
- file1.py
- file2.py

**审查结果**: <发现的问题列表>
**修复+简化**: <已修复的问题和简化内容>
**提交**: <commit hash>

#### 分组 2: ...

### 总结
- 总文件数: X
- 用户选择审查: Y 个分组 (Z 个文件)
- 已跳过: W 个分组
- 所有选中分组已审查、修复并提交
```

## 注意事项

1. **审查优先**：先进行代码审查发现问题，再在简化时一并修复
2. **问题传递**：确保将审查发现的问题完整传递给 pr-review-toolkit:code-simplifier
3. **无问题时**：如果 pr-review-toolkit:code-reviewer 未发现问题，pr-review-toolkit:code-simplifier 仅做代码简化
4. **大文件处理**：对于特别大的文件，单独作为一组处理
5. **合并冲突**：如果存在冲突，先提示用户解决再继续
