# MoveModule 不更新不匹配的导入路径

## 问题概述

使用 `rope.refactor.move.MoveModule` 移动 Python 模块时，如果某些代码文件中的导入语句指向的路径与实际模块位置不匹配（"幽灵导入"），Rope 不会更新这些导入语句，导致代码在移动后出现导入错误。

## 错误现象

### 重构前的文件结构
```
calculation/
├── atr.py              # 实际文件在这里
├── bollinger.py
├── macd.py
├── service/
│   └── technical_service.py
└── indicator/
    └── technical/
        └── __init__.py  # 空的，没有实际的 .py 文件
```

### 重构前的导入语句（technical_service.py）
```python
from app.domain.supporting.calculation.indicator.technical.atr import calculate_atr
from app.domain.supporting.calculation.indicator.technical.bollinger import calculate_bollinger
# ... 等等
```

**关键点**：导入语句指向 `indicator.technical.*`，但实际文件在 `calculation/*`。这些导入在重构前就是错误的（可能是重构遗留问题）。

### 执行的重构操作
```python
mover = MoveModule(project, resource)
changeset = mover.get_changes(destination_folder)
project.do(changeset)
```

将 `calculation/atr.py` 移动到 `calculation/util/atr.py`。

### 重构后的结果
- ✅ 正确导入的代码被更新（如 `from calculation.atr` → `from calculation.util.atr`）
- ❌ `technical_service.py` 中的导入**没有被更新**，仍然指向 `indicator.technical.atr`（不存在的路径）

## 根本原因

### Rope 的工作机制
`MoveModule` 的更新逻辑是：
1. 识别被移动的模块：`calculation.atr`
2. 搜索项目中所有**直接导入** `calculation.atr` 的代码
3. 更新这些导入语句为新的路径

### 问题所在
当原导入语句与实际模块位置不匹配时：
- Rope 被告知移动 `calculation.atr`
- Rope 只搜索 `from calculation.atr import ...` 或 `import calculation.atr`
- `technical_service.py` 中写的是 `from indicator.technical.atr import ...`
- Rope **无法识别**这是对被移动模块的引用
- 结果：导入语句不会被更新

### 为什么会出现这种不匹配？
这是之前重构遗留的问题：
- 可能之前有人手动移动了文件，但没有更新所有导入
- 可能使用了不支持自动更新导入的工具移动文件
- 可能是从其他项目复制代码时没有调整路径

## 解决方案

### 方案 1：修复导入语句后再移动（推荐）
在执行 `MoveModule` 之前，先确保所有导入语句正确：

```python
# 方式 A：使用 rope 的 Rename 来修复错误的导入
# 但这需要知道所有错误导入的位置

# 方式 B：手动修复导入语句
# 将 indicator.technical.* 改为 calculation.*
# 然后再执行 MoveModule
```

### 方案 2：使用 ChangeOccurrences 更新特定导入
```python
from rope.refactor.rename import ChangeOccurrences

# 对于每个错误的导入路径
resource = project.get_resource("path/to/technical_service.py")
changer = ChangeOccurrences(project, resource, offset_of_import_statement)
changeset = changer.get_changes("calculation.atr")
project.do(changeset)
```

### 方案 3：移动后手动修复（不推荐）
移动完成后，手动搜索并修复所有未更新的导入：

```python
# 使用 Grep 找出所有错误的导入
# 然后逐个修复
```

### 方案 4：使用 rope 的 importutils（实验性）
```python
from rope.refactor.importutils import ImportOrganizer

organizer = ImportOrganizer(project)
changeset = organizer.organize_imports(resource)
# 这可能会重新组织导入，但不一定能修复路径
```

## 经验总结

### 预防措施
1. **重构前审查导入**：执行模块移动前，先用 `grep` 或 IDE 的查找引用功能，确认所有导入语句的路径是否正确
2. **保持导入一致性**：确保导入语句始终与实际文件结构匹配
3. **使用 rope 重构**：避免使用不支持自动更新的工具（如 `shutil.move`、`mv` 命令）移动 Python 文件

### 检测方法
移动模块后，运行以下命令检测问题：

```bash
# 查找所有 Python 导入
grep -r "from.*import" backend/

# 运行测试发现导入错误
pytest tests/ --tb=short

# 使用 Python 编译检查
python -m py_compile backend/app/domain/supporting/calculation/service/*.py
```

### Rope 的限制
1. **静态分析限制**：Rope 依赖静态分析，无法处理运行时动态导入
2. **路径匹配要求**：导入路径必须与模块的实际位置精确匹配
3. **无法猜测意图**：如果导入路径和模块位置不匹配，Rope 无法猜测开发者的意图

## 相关问题类型

- 类似问题可能出现在 `Rename` 操作中
- `move.create_move`（方法/函数移动）有相同限制
- 任何依赖导入路径分析的重构操作都可能受影响

## 后续建议

1. **建立代码审查流程**：在重构 PR 中检查导入语句
2. **添加 pre-commit hook**：使用 `rope` 或 `autoflake` 检查未使用的导入
3. **文档化项目结构**：维护清晰的目录结构文档，减少人为错误
4. **使用 IDE 重构功能**：现代 IDE（如 PyCharm、VS Code with Pylance）的重构功能通常更智能

## 测试用例

```python
# 最小复现示例
# 文件结构：
# calc/
#   ├── __init__.py
#   ├── foo.py  (def foo(): pass)
#   └── bar.py
#
# bar.py 内容：
#   from wrong.path.foo import foo  # 错误的导入路径
#
# 执行：MoveModule(project, foo_resource, calc/sub/)
# 预期：bar.py 的导入不会被更新
# 实际：bar.py 的导入确实不会被更新
```

## 结论

Rope 的 `MoveModule` 是一个强大的重构工具，但它假设代码库的导入语句是正确和一致的。当存在"幽灵导入"（导入路径与实际模块位置不匹配）时，Rope 无法自动修复这些错误。**维护一致的导入结构是使用 Rope 重构的前提条件。**
