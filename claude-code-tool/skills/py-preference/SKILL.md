---
name: py-preference
description: Python 开发偏好指南。当进行 Python 开发、代码重构、问题修复、类型标注、错误处理等任务时使用此 skill。AI 会根据用户的历史偏好记录，自动采用用户偏好的方案和风格。触发词：Python开发、写Python代码、Python重构、Python问题修复、mypy修复。
---

# Python 开发偏好指南

基于用户历史偏好记录，指导 AI 进行 Python 开发。

```
Python 开发
写 Python 代码
Python 重构
Python 问题修复
mypy 修复
类型标注
```

## 核心原则

**AI 必须先阅读偏好记录，再进行开发决策**。

## 深层偏好原则

> 以下是从具体案例中提炼出的通用偏好原则，适用于各类开发决策。

### 代码清晰性

| 原则 | 说明 | 案例 |
|------|------|------|
| **语义优先** | 优先选择"让代码意图更清晰"的方案，而非"依赖工具行为"的方案 | for 循环使用不同变量名而非类型注解 |
| **显式优于隐式** | 变量名、类型、逻辑应自解释，不依赖上下文推断 | 通过变量名表达意图，而非依赖类型推断 |
| **最小改动原则** | 优先选择改动范围小、影响边界清晰的方案 | - |
| **正面修复优于忽略** | 优先选择解决类型系统限制的方案，而非使用 `type: ignore` 绕过检查 | 创建 `_extract_rowcount` 方法而非忽略 mypy 错误 |
| **集中管理重复逻辑** | 将重复的类型转换或错误处理逻辑封装为辅助方法 | `_extract_rowcount` 统一处理 rowcount 提取 |

### 决策风格

| 原则 | 说明 |
|------|------|
| **实用主义** | 不追求"完美"方案，选择"够用且简单"的方案 |
| **避免过度工程** | 不为假设的未来需求做过度设计 |
| **工具服务于人** | 工具（mypy、ruff 等）是辅助，不应主导决策，但也不应简单忽略其警告 |

### 类型标注

| 原则 | 说明 | 案例 |
|------|------|------|
| **语义化命名** | 通过变量名或方法名表达意图，而非依赖类型注解 | `_extract_rowcount` 而非 `_cast_rowcount_to_int` |
| **接受工具限制** | 工具的误报可以接受，不必追求 100% 通过，但优先选择正面修复 | 使用 `cast` 明确类型而非 `type: ignore` |

---

## 加载偏好记录

在执行任何 Python 开发任务前，必须先读取偏好记录：

```bash
# 列出所有偏好记录
ls .claude/skills/py-preference/references/

# 读取特定类别的偏好
cat .claude/skills/py-preference/references/<category>/<file>.md
```

## 偏好类别

| 类别 | 说明 | 文件位置 |
|------|------|----------|
| `type-hint` | 类型标注偏好 | `references/type-hint/` |
| `error-handling` | 错误处理偏好 | `references/error-handling/` |
| `code-style` | 代码风格偏好 | `references/code-style/` |
| `refactoring` | 重构策略偏好 | `references/refactoring/` |
| `tool-config` | 工具配置偏好 | `references/tool-config/` |

## 执行流程

### 1. 识别任务类型

根据用户请求，判断涉及的偏好类别：

| 用户请求 | 相关类别 |
|----------|----------|
| mypy 类型错误 | `type-hint`, `tool-config` |
| 代码风格问题 | `code-style` |
| 重构决策 | `refactoring` |
| 异常处理 | `error-handling` |

### 2. 读取相关偏好

```bash
# 示例：读取类型标注相关偏好
cat .claude/skills/py-preference/references/type-hint/*.md
```

### 3. 应用偏好决策

**优先级**：
1. **深层偏好原则**（本文件的"深层偏好原则"章节）
2. **具体案例记录**（references/ 目录下的记录）
3. **项目规范**（CLAUDE.md）

根据偏好记录中的选择，采用用户偏好的方案。

**如果偏好记录中没有相关内容**：
1. 先查看"深层偏好原则"是否有相关指导
2. 向用户展示多个可选方案
3. 说明各方案的优缺点
4. 让用户选择
5. 建议用户调用 `py-preference-optimize` 记录此偏好

## 偏好记录格式

每条偏好记录遵循以下结构：

```markdown
---
category: <类别>
created: <日期>
tags: [<标签1>, <标签2>]
---

# <偏好标题>

## 场景
（描述什么情况下需要做这个决策）

## 选项
（列出可能的方案）

## 选择
（用户选择的方案）

## 理由
（为什么选择这个方案）
```

## 示例：应用偏好

**场景**：遇到 mypy 变量类型不兼容错误

**应用深层原则**：
- "语义优先" → 使用不同变量名，让每个变量意图清晰
- "显式优于隐式" → 不依赖 mypy 的类型推断行为

**结果**：AI 直接采用"不同变量名"方案，不再询问用户。

## 边界限制

- 本 skill 只负责**读取和应用**偏好
- **记录新偏好**需调用 `py-preference-optimize` skill
- **提炼深层原则**也需调用 `py-preference-optimize` skill
- 如果偏好记录与项目规范（CLAUDE.md）冲突，以项目规范为准

---

## 经验总结

### 最新笔记
- [2026-03-20 快速笔记](../skill-memory-keeper/memory/user/quick-notes/py-preference/note-2026-03-20.md)
- [2026-03-19 快速笔记](../skill-memory-keeper/memory/user/quick-notes/py-preference/note-2026-03-19.md)

### 问题统计
- 当前跟踪偏好记录: 6 个
