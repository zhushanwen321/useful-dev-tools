# get_source_folders 性能问题

## 问题概述

`MoveModule.get_changes()` 在 606 个文件的项目中执行需要 53 秒，性能极差。

## 错误现象

```
单个模块 get_changes 耗时: 53.054s
12 个模块预计总耗时: ~360s (6分钟)

cProfile 分析结果：
- _find_source_folders 被调用 66,744 次
- get_children 被调用 200,216 次
- get_child 被调用 3,550,212 次
- get_resource 被调用 3,550,242 次
```

## 根本原因

`rope/base/project.py` 第 84 行 `get_source_folders()` 方法**缺少缓存装饰器**：

```python
# 原代码（有问题）
def get_source_folders(self):
    """Returns project source folders"""
    if self.root is None:
        return []
    result = list(self._custom_source_folders)
    result.extend(self.pycore._find_source_folders(self.root))  # 每次都遍历整个目录树！
    return result
```

问题链路：
1. `MoveModule.get_changes()` 调用 `find_module()`
2. `find_module()` 调用 `get_source_folders()`
3. `get_source_folders()` 调用 `_find_source_folders(root)` 递归遍历整个项目目录树
4. 每个文件分析时都会调用，606 个文件 × 多次调用 = 66,744 次目录遍历

## 解决方案

添加 `@utils.saveit` 缓存装饰器：

```python
# 修复后的代码
@utils.saveit
def get_source_folders(self):
    """Returns project source folders"""
    if self.root is None:
        return []
    result = list(self._custom_source_folders)
    result.extend(self.pycore._find_source_folders(self.root))
    return result
```

## 性能对比

| 指标 | 修复前 | 修复后 | 提升 |
|------|--------|--------|------|
| 单个模块 get_changes | 53s | 0.024s | **2200x** |
| 12 个模块总耗时 | ~360s | 4.15s | **86x** |
| occurs_in_module | 11.25s | 0.005s | 2250x |

## 经验总结

- **缓存缺失**：rope 的 `@utils.saveit` 装饰器用于缓存方法结果，但 `get_source_folders` 漏掉了
- **性能分析优先**：遇到性能问题时，先用 cProfile 找热点，不要盲目猜测
- **调用次数异常**：当看到函数调用次数远超文件数量时（66,744 vs 606），说明存在重复计算
- **目录遍历昂贵**：递归遍历目录树是昂贵操作，必须缓存结果

## 相关文件

- `case_script.py` - 性能分析脚本
- `case_output.txt` - 完整的 cProfile 输出

## 修复位置

- 文件：`rope/base/project.py`
- 行号：84
- 修复：添加 `@utils.saveit` 装饰器
