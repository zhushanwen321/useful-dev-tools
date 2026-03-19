# Arg 类型注解导致 AST 位置不同步

## 问题概述

rope 在处理包含类型注解的函数参数时，`patchedast.py` 中的 `_arg` 方法没有正确处理 `annotation` 属性，导致 AST 节点的位置跟踪失去同步，最终引发 `MismatchedTokenError`。

## 错误现象

```
MismatchedTokenError: Pattern <Keyword: 'def', Name: 'process_data'> at (2, 4) cannot be matched
```

当尝试对包含类似以下代码的文件执行重构操作时触发：

```python
def process_data(
    items: list[str],
    config: dict[str, str] | None = None,
) -> str:
    ...
```

## 根本原因

### Python AST 中 `arg` 节点的结构

在 Python 3.6+ 中，函数参数使用 `ast.arg` 节点表示，其结构为：

```python
arg = arg(arg='参数名', annotation=<类型注解>)
```

当有类型注解时，源代码实际上包含：
1. 参数名（如 `items`）
2. 冒号 `:`
3. 类型注解（如 `list[str]`）

### rope 的 `_arg` 方法问题

**原始代码**（`rope/refactor/patchedast.py`）：

```python
def _arg(self, node):
    self._handle(node, [node.arg])
```

这个实现**只处理了参数名**，完全忽略了 `annotation` 属性。

### 位置跟踪失去同步

rope 的 `patchedast` 通过遍历 AST 节点并跟踪源代码位置来工作。当 `_arg` 只声明了 `node.arg` 而不包含类型注解时：

1. rope 认为这个参数只有 1 个 token（参数名）
2. 但源代码实际有 3 个 token：`items` + `:` + `list[str]`
3. 导致位置计数器落后于实际位置
4. 累积误差最终导致 `MismatchedTokenError`

## 解决方案

修改 `rope/refactor/patchedast.py` 中的 `_arg` 方法：

```python
def _arg(self, node):
    children = [node.arg]
    if node.annotation is not None:
        children.extend([":", node.annotation])
    self._handle(node, children)
```

### 修改说明

1. 检查 `node.annotation` 是否存在
2. 如果有类型注解，添加冒号和注解到 children 列表
3. 这样 rope 就能正确跟踪包含类型注解的参数位置

## 经验总结

### 调试技巧

1. **二分定位**：通过注释掉部分代码，二分查找问题行
2. **AST 分析**：使用 `ast.dump()` 查看节点结构
3. **对比分析**：对比 rope 实现与 Python 官方 AST 文档

### rope 调试要点

1. `patchedast.py` 负责将 AST 节点与源代码位置关联
2. 每个 AST 节点类型都有对应的处理方法（如 `_arg`, `_FunctionDef`）
3. `_handle` 方法的第二个参数必须包含该节点的所有子元素
4. 缺少任何子元素都会导致位置跟踪失去同步

### Python 版本兼容性

- `ast.arg` 的 `annotation` 属性从 Python 3.6 开始支持
- PEP 484 类型注解、PEP 585 通用类型、PEP 604 联合类型语法
- rope 需要跟随 Python 版本更新 AST 处理逻辑

## 相关文件

- 修复位置：`/Users/zhushanwen/GitApp/rope/rope/refactor/patchedast.py`
- 修复方法：`_arg`（约第 260 行）

## 参考

- Python AST 文档：https://docs.python.org/3/library/ast.html
- PEP 484：Type Hints
- PEP 585：Type Hinting Generics In Standard Collections
- PEP 604：Allow Writing Union Types as X | Y
