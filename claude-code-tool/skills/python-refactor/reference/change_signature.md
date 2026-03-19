# ChangeSignature API 使用文档

## 1. 基本信息

### API 完整路径

```
rope.refactor.change_signature.ChangeSignature
```

### 类说明

`ChangeSignature` 是 rope 库中用于修改函数签名的重构工具类。它可以：

- 添加新参数
- 删除现有参数
- 重命名参数
- 重排参数顺序
- 规范化参数调用方式

该重构会自动更新函数定义以及项目中所有调用该函数的地方。

---

## 2. 构造函数参数

```python
ChangeSignature(project, resource, offset)
```

| 参数 | 类型 | 说明 |
|------|------|------|
| `project` | `Project` | rope 项目对象 |
| `resource` | `Resource` | 函数所在的资源文件对象 |
| `offset` | `int` | 函数名在文件中的字符偏移量 |

### 注意事项

- `offset` 需要指向函数名，而非函数调用的位置
- 如果在类的方法上调用，会自动处理 `__init__` 方法
- 如果 offset 指向的不是函数，会抛出 `RefactoringError` 异常

---

## 3. 常用方法

### get_changes()

获取重构产生的所有变更。

```python
get_changes(
    changers,                    # List[_ArgumentChanger] - 参数修改器列表
    in_hierarchy=False,          # bool - 是否在类层次结构中应用
    resources=None,              # List[File] - 要搜索的文件范围
    task_handle=DEFAULT_TASK_HANDLE  # TaskHandle - 任务处理器
) -> ChangeSet
```

这是执行重构的主要方法，`changers` 是参数修改器的列表，可以同时应用多个修改。

### get_args()

获取函数当前的所有参数。

```python
get_args() -> List[Tuple[str, Any]]
```

返回格式为 `(name, default)` 的元组列表。如果没有默认值，则 default 为 `None`。

### is_method()

判断当前修改的是否为类方法。

```python
is_method() -> bool
```

---

## 4. 参数修改器类

### ArgumentAdder - 添加参数

```python
ArgumentAdder(index, name, default=None, value=None)
```

| 参数 | 类型 | 说明 |
|------|------|------|
| `index` | `int` | 插入位置的索引 |
| `name` | `str` | 新参数名称 |
| `default` | `str` | 默认值（作为字符串） |
| `value` | `str` | 调用时使用的默认值 |

### ArgumentRemover - 删除参数

```python
ArgumentRemover(index)
```

| 参数 | 类型 | 说明 |
|------|------|------|
| `index` | `int` | 要删除参数的索引（从 0 开始） |

### ArgumentReorderer - 重排参数

```python
ArgumentReorderer(new_order, autodef=None)
```

| 参数 | 类型 | 说明 |
|------|------|------|
| `new_order` | `List[int]` | 新顺序列表，表示每个参数的新位置 |
| `autodef` | `str` | 当重排导致需要默认值时使用的自动默认值 |

**注意**：`new_order` 是参数新位置的列表，而不是参数要移动到的位置列表。

例如：将 `f(a, b, c)` 变为 `f(c, a, b)` 需要传入 `[2, 0, 1]`。

### ArgumentNormalizer - 规范化参数

```python
ArgumentNormalizer()
```

将关键字参数调用转换为位置参数调用，使函数调用更加规范。

### ArgumentDefaultInliner - 内联默认参数

```python
ArgumentDefaultInliner(index)
```

将具有默认值的参数在调用处内联其默认值。

---

## 5. 使用场景

### 场景一：添加新参数

```python
from rope.base.project import Project
from rope.refactor.change_signature import ChangeSignature, ArgumentAdder

# 创建项目
project = Project('.')

# 获取要修改的文件
resource = project.get_resource('example.py')

# 定位到函数名位置（需要找到函数名在文件中的偏移量）
code = resource.read()
func_offset = code.index('my_function')  # 或者使用其他方式定位

# 创建 ChangeSignature 对象
signature = ChangeSignature(project, resource, func_offset)

# 添加新参数（在索引 0 位置添加参数 'new_param'，默认值为 None）
changes = signature.get_changes([
    ArgumentAdder(0, 'new_param', default='None')
])

# 执行变更
project.do(changes)
project.close()
```

### 场景二：删除参数

```python
from rope.base.project import Project
from rope.refactor.change_signature import ChangeSignature, ArgumentRemover

project = Project('.')
resource = project.get_resource('example.py')

code = resource.read()
func_offset = code.index('my_function')

signature = ChangeSignature(project, resource, func_offset)

# 删除索引为 0 的参数
changes = signature.get_changes([
    ArgumentRemover(0)
])

project.do(changes)
project.close()
```

### 场景三：重命名参数

重命名参数需要结合删除和添加操作，或者直接使用 rope 的 Rename 重构。

```python
# 使用 rope 的 Rename 功能重命名参数
from rope.refactor.rename import Rename

project = Project('.')
resource = project.get_resource('example.py')

code = resource.read()
# 定位到参数名位置（不是函数名）
param_offset = code.index('old_param_name')

renamer = Rename(project, resource, param_offset)
changes = renamer.get_changes('new_param_name')

project.do(changes)
project.close()
```

### 场景四：重排参数顺序

```python
from rope.base.project import Project
from rope.refactor.change_signature import ChangeSignature, ArgumentReorderer

project = Project('.')
resource = project.get_resource('example.py')

code = resource.read()
func_offset = code.index('my_function')

signature = ChangeSignature(project, resource, func_offset)

# 假设原函数为 f(a, b, c)，现在需要变为 f(c, a, b)
# new_order = [2, 0, 1] 表示：
#   - 原索引 0 的参数 (a) 移动到新索引 1
#   - 原索引 1 的参数 (b) 移动到新索引 2
#   - 原索引 2 的参数 (c) 移动到新索引 0
changes = signature.get_changes([
    ArgumentReorderer([2, 0, 1])
])

project.do(changes)
project.close()
```

### 场景五：规范化参数调用

```python
from rope.base.project import Project
from rope.refactor.change_signature import ChangeSignature, ArgumentNormalizer

project = Project('.')
resource = project.get_resource('example.py')

code = resource.read()
func_offset = code.index('my_function')

signature = ChangeSignature(project, resource, func_offset)

# 将关键字参数调用转换为位置参数
changes = signature.get_changes([
    ArgumentNormalizer()
])

project.do(changes)
project.close()
```

---

## 6. 完整代码示例

### 示例：完整的重构脚本

```python
#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
ChangeSignature API 使用示例
演示如何修改函数的参数
"""

from rope.base.project import Project
from rope.refactor.change_signature import (
    ChangeSignature,
    ArgumentAdder,
    ArgumentRemover,
    ArgumentReorderer,
    ArgumentNormalizer,
)


def add_parameter_example():
    """示例：添加新参数到函数"""
    # 创建项目
    project = Project('/path/to/project')

    # 获取文件
    resource = project.get_resource('my_module.py')

    # 读取文件内容找到函数位置
    content = resource.read()
    offset = content.index('def greet')  # 假设函数名为 greet

    # 创建 ChangeSignature 对象
    changer = ChangeSignature(project, resource, offset)

    # 添加新参数：在位置 1 添加 'greeting' 参数，默认值为 'Hello'
    changes = changer.get_changes([
        ArgumentAdder(1, 'greeting', default="'Hello'")
    ])

    # 执行变更
    project.do(changes)

    print("参数添加完成！")
    project.close()


def remove_parameter_example():
    """示例：删除函数参数"""
    project = Project('/path/to/project')
    resource = project.get_resource('my_module.py')

    content = resource.read()
    offset = content.index('def calculate')

    changer = ChangeSignature(project, resource, offset)

    # 删除索引为 0 的参数
    changes = changer.get_changes([
        ArgumentRemover(0)
    ])

    project.do(changes)
    project.close()
    print("参数删除完成！")


def reorder_parameters_example():
    """示例：重排函数参数顺序"""
    # 假设有以下函数：
    # def process(name, age, city):
    #     pass
    #
    # 调用为：
    # process("Alice", 30, "Beijing")
    #
    # 我们希望变为：
    # def process(city, name, age):
    #     pass
    #
    # 调用自动变为：
    # process("Beijing", "Alice", 30)

    project = Project('/path/to/project')
    resource = project.get_resource('my_module.py')

    content = resource.read()
    offset = content.index('def process')

    changer = ChangeSignature(project, resource, offset)

    # 参数顺序从 [name, age, city] 变为 [city, name, age]
    # 即原索引 0 -> 新索引 1
    #      原索引 1 -> 新索引 2
    #      原索引 2 -> 新索引 0
    # 所以 new_order = [2, 0, 1]
    changes = changer.get_changes([
        ArgumentReorderer([2, 0, 1])
    ])

    project.do(changes)
    project.close()
    print("参数重排完成！")


def multiple_changes_example():
    """示例：同时执行多个修改"""
    project = Project('/path/to/project')
    resource = project.get_resource('my_module.py')

    content = resource.read()
    offset = content.index('def my_func')

    changer = ChangeSignature(project, resource, offset)

    # 同时删除索引 0 的参数，并在索引 1 添加新参数
    changes = changer.get_changes([
        ArgumentRemover(0),
        ArgumentAdder(1, 'new_param', default='None')
    ])

    project.do(changes)
    project.close()
    print("多重修改完成！")


if __name__ == '__main__':
    # 选择要执行的示例
    # add_parameter_example()
    # remove_parameter_example()
    # reorder_parameters_example()
    # multiple_changes_example()
    pass
```

---

## 7. 常见问题

### Q1: 如何获取函数名的偏移量？

可以使用以下方法：

```python
# 方法1：直接查找
code = resource.read()
offset = code.index('function_name')

# 方法2：使用 rope 的工具定位
from rope.base import worder
offset = worder.get_name_start(resource, 'function_name')
```

### Q2: 如何只修改特定文件中的调用？

```python
# 使用 resources 参数限制搜索范围
specific_resource = project.get_resource('specific_file.py')
changes = signature.get_changes(
    [ArgumentAdder(0, 'new_param', default='None')],
    resources=[specific_resource]
)
```

### Q3: 如何处理类方法？

`ChangeSignature` 会自动检测类方法。当在类的 `__init__` 方法上调用时，它会自动处理类的构造函数。

```python
# 对于类方法，不需要特殊处理
# rope 会自动识别 self 参数
signature = ChangeSignature(project, resource, offset)
# 这会自动跳过 self 参数
```

### Q4: 如何在类层次结构中应用更改？

```python
# 使用 in_hierarchy 参数
changes = signature.get_changes(
    [ArgumentAdder(0, 'new_param', default='None')],
    in_hierarchy=True  # 会在所有子类的方法中应用更改
)
```

### Q5: 为什么重排序参数后出现默认值错误？

当将没有默认值的参数移动到有默认值参数的后面时，Python 会报错。可以使用 `autodef` 参数：

```python
# 如果重排导致需要默认值，使用 autodef 自动添加
changes = signature.get_changes([
    ArgumentReorderer([2, 0, 1], autodef='None')
])
```

### Q6: 如何查看函数当前有哪些参数？

```python
signature = ChangeSignature(project, resource, offset)
args = signature.get_args()
# 返回格式: [('param1', None), ('param2', 'default_value'), ...]
for name, default in args:
    print(f"参数: {name}, 默认值: {default}")
```

### Q7: 为什么会抛出 "Change method signature should be performed on functions" 错误？

这表示你选择的偏移量没有指向一个函数。请确保：

1. 偏移量指向函数名，而不是函数调用
2. 目标是函数定义，不是类定义或变量

---

## 8. 参考资源

- **源码位置**: `/Users/zhushanwen/GitApp/rope/rope/refactor/change_signature.py`
- **测试用例**: `/Users/zhushanwen/GitApp/rope/ropetest/refactor/change_signature_test.py`
- **Rope 官方文档**: https://github.com/python-rope/rope
