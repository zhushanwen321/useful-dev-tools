# Python Refactor Skill 文档规范

## SKILL.md 编写规则

### 行数限制

- **目标**：保持在 **200 行**左右
- **最大**：不超过 **300 行**
- **原则**：只记录最核心的问题，其他问题链接到其他文档

### 内容组织

```
SKILL.md 内容结构：
├── 核心规则（最高优先级）
├── 触发条件
├── 工作流程
├── API 速查表（核心 API）
├── 关键限制（最常见的限制）
├── 参考文档链接
└── 常见问题（最常见的 3-5 个）
```

### 文档分层策略

| 内容 | 位置 | 说明 |
|------|------|------|
| 核心规则和限制 | SKILL.md | 必须记住的 |
| 详细 API 用法 | references/high-usage-functions.md | 高频函数详解 |
| 负向用例 | negative-case/raw-case/ | 具体问题和解决方案 |
| 框架特定问题 | references/fastapi-support.md | FastAPI 等特定框架 |

---

## Negative Case 总结

### 频繁出现的问题（高发）

#### 1. MoveModule 不更新导入

| 问题类型 | 描述 | 解决方案 |
|---------|------|---------|
| 不匹配导入 | 导入路径与实际位置不匹配时不会更新 | 先修复导入再移动 |
| 相对导入 | `from base_providers import` 类型不会被更新 | 改用绝对导入 |
| 嵌套目录 | 移动 `__init__.py` 会导致嵌套目录 | 只移动单个文件 |

#### 2. MoveModule 不能同时改名

- **限制**：`MoveModule` 只能移动位置，不能改变文件名
- **解决方案**：先用 `Rename(offset=None)` 重命名，再用 `MoveModule` 移动

#### 3. 性能问题

- **问题**：`get_changes()` 在大项目中很慢
- **原因**：`get_source_folders()` 缺少缓存，重复遍历目录
- **解决方案**：使用 `resources` 参数限制扫描范围

---

### 容易出错的问题（易错）

#### 1. 版本控制要求

| 操作 | 需要 VCS | 不需要 VCS |
|------|---------|-----------|
| 重命名模块文件 | ✅ | |
| 撤销/重做 | ✅ | |
| 提取/内联/改变签名 | | ✅ |

**错误**：`"not under version control"`
**解决**：确保项目在 git/hg 下

#### 2. 路径格式错误

| 错误用法 | 正确用法 |
|---------|---------|
| `path_to_resource(project, '/abs/path')` | `path_to_resource(project, 'relative/path')` |
| `project.get_resource('/abs/path')` | `project.get_resource('relative/path')` |
| `mover.get_changes()` | `mover.get_changes(destination)` |

#### 3. 执行后忘记关闭项目

```python
# 错误
project = Project('/path')
# ... 使用 ...

# 正确
project = Project('/path')
try:
    # ... 使用 ...
finally:
    project.close()
```

#### 4. get_changes 后忘记执行

```python
# 错误
change = mover.get_changes(dst)
# 忘记执行！

# 正确
change = mover.get_changes(dst)
project.do(change)  # 必须执行
```

---

### 特殊问题（特定场景）

#### 1. 类型注解导致 AST 位置不同步

- **现象**：`MismatchedTokenError`
- **原因**：Python 3.6+ 的 `ast.arg` 包含 `annotation` 属性，rope 未处理
- **涉及语法**：`list[str]`、`dict[str, str] | None`、`X | Y`

#### 2. FastAPI 依赖注入

- **现象**：重构后依赖注入失效
- **原因**：`Annotated` 依赖注入模式的特殊处理

---

### 问题分类速查表

```
按操作类型：
├── 重命名模块
│   └── 需要 VCS
│   └── 不能同时移动
├── 移动模块
│   ├── 不更新不匹配导入
│   ├── 不更新相对导入
│   ├── __init__.py 嵌套问题
│   └── resources 参数优化
├── 提取/内联
│   └── Python 3.10+ 语法兼容
└── 改变签名
    └── 复杂参数处理

按错误类型：
├── NotUnderVersionControl
├── MismatchedTokenError
├── ModuleNotFoundError
└── ValueError (path mount)
```

---

### 记录新问题的模板

当遇到新问题时，按以下结构记录：

```markdown
# {问题摘要}

## 问题概述
（一句话描述）

## 错误现象
```
错误信息
```

## 根本原因
（分析为什么出错）

## 解决方案
（如何解决）

## 经验总结
- 关键词1：总结1
- 关键词2：总结2
```

目录位置：
```
negative-case/raw-case/{问题摘要}/
├── analysis.md          # 必须
├── case_script.py      # 可选
├── case_output.txt     # 可选
└── case_src/          # 可选
```

---

## 相关文档索引

| 文档 | 路径 | 用途 |
|------|------|------|
| SKILL.md | 当前目录 | 主文档，核心规则 |
| high-usage-functions.md | references/ | 高频函数详解 |
| fastapi-support.md | references/ | FastAPI 特殊处理 |
| overview.rst | references/rope-docs/ | rope 用户指南 |
| library.rst | references/rope-docs/ | rope API 参考 |
| negative-case/ | ../../ | 负向用例库 |
