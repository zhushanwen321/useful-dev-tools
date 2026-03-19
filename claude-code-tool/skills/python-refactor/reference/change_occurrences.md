# ChangeOccurrences API 文档

## 基本信息

**API 完整路径**: `rope.refactor.rename.ChangeOccurrences`

**类说明**: `ChangeOccurrences` 是 rope 库中的一个类，用于执行选择性的重命名操作。与 `Rename` 类不同，它只改变指定作用域（scope）内的引用，而不影响其他位置的同名引用。

这个类的设计目标是提供更灵活的重命名能力：
- 它只修改包含给定偏移量所在的作用域内的引用
- 不会产生副作用，例如重命名模块时不会实际重命名模块文件
- 非常适合执行各种自定义的重构操作

## 构造函数

```python
ChangeOccurrences(project, resource, offset)
```

### 参数说明

| 参数名 | 类型 | 说明 |
|--------|------|------|
| `project` | `Project` | rope 项目对象 |
| `resource` | `Resource` | 要执行重命名的文件资源对象 |
| `offset` | `int` | 目标名称在文件中的字符偏移量 |

### 参数详解

- **project**: 通过 `rope.base.project.Project` 创建的项目实例，用于访问项目的配置和 Python 解析能力。

- **resource**: 要操作的文件资源，可以通过 `project.get_resource()` 或 `project.get_file()` 获取。

- **offset**: 指向目标名称任意一次出现的字符偏移量。`ChangeOccurrences` 会找到该偏移量所在的作用域，并只在该作用域内进行替换。

## 常用方法

### get_old_name()

获取重命名之前的原始名称。

```python
def get_old_name(self):
    word_finder = worder.Worder(self.resource.read())
    return word_finder.get_primary_at(self.offset)
```

**返回值**: `str` - 原始名称

### get_changes(new_name, only_calls=False, reads=True, writes=True)

生成重命名操作的变更集合。

```python
def get_changes(self, new_name, only_calls=False, reads=True, writes=True):
    # 方法实现
```

**参数说明**:

| 参数名 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `new_name` | `str` | 必填 | 重命名后的新名称 |
| `only_calls` | `bool` | `False` | 是否只替换函数/方法调用 |
| `reads` | `bool` | `True` | 是否替换读取引用（右侧使用） |
| `writes` | `bool` | `True` | 是否替换写入引用（左侧赋值） |

**返回值**: `ChangeSet` - 包含所有变更的集合

**参数详解**:

- **new_name**: 要替换成的新名称。

- **only_calls**: 当设置为 `True` 时，只替换函数/方法的调用形式，不替换作为变量引用或赋值的形式。例如在 `g = f1` 中不会被替换，但在 `a = f1()` 中会被替换。

- **reads**: 控制是否替换"读取"引用（即作为表达式右侧使用的情况）。设为 `False` 可以只保留写入引用。

- **writes**: 控制是否替换"写入"引用（即赋值操作左侧的情况）。设为 `False` 可以只保留读取引用。

### 关于 add_occurrence 方法

**注意**: `ChangeOccurrences` 类中并**不存在** `add_occurrence(line, column)` 方法。该方法是用户对 API 的误解。

如果你需要更精细地控制要替换的引用位置，可以考虑以下方案：
1. 使用 `Rename` 类的 `resources` 参数限制文件范围
2. 编写自定义的 occurance 过滤逻辑

## 使用场景

### 场景一：只重命名局部作用域内的引用

当你只想重命名某个函数或类内部的引用，而不影响全局或外部作用域的同名变量时，`ChangeOccurrences` 非常有用。

```python
# 原始代码
a_var = 1
new_var = 2

def f():
    print(a_var)
```

使用 `ChangeOccurrences` 在 `a_var` 的某个位置创建实例：

```python
from rope.refactor.rename import ChangeOccurrences

# 只替换函数 f() 内部的 a_var，不影响全局的 a_var
changer = ChangeOccurrences(project, mod, mod.read().rindex("a_var"))
changes = changer.get_changes("new_var")
changes.do()
```

结果：

```python
a_var = 1
new_var = 2

def f():
    print(new_var)
```

### 场景二：只替换函数调用

当你想要将一个函数引用替换为另一个函数，但只想替换实际调用而非赋值时：

```python
# 原始代码
def f1():
    pass

def f2():
    pass

g = f1       # 保持不变
a = f1()     # 被替换为 f2()
```

```python
changer = ChangeOccurrences(project, mod, mod.read().rindex("f1"))
changes = changer.get_changes("f2", only_calls=True)
changes.do()
```

### 场景三：只替换读取或写入引用

只替换变量的读取（使用）而不替换赋值：

```python
# 原始代码
a = 1
b = 2
print(a)  # 只替换这一行
```

```python
changer = ChangeOccurrences(project, mod, mod.read().rindex("a"))
changes = changer.get_changes("b", writes=False)
changes.do()
```

结果：

```python
a = 1
b = 2
print(b)
```

## 与 Rename 的区别

| 特性 | Rename | ChangeOccurrences |
|------|--------|-------------------|
| 作用范围 | 全项目/指定文件 | 仅限特定作用域 |
| 模块重命名 | 会实际重命名文件 | 只会替换引用 |
| 批量替换 | 支持（通过 resources 参数） | 仅限单个文件 |
| 调用过滤 | 不支持 | 支持（only_calls 参数） |
| 读写过滤 | 不支持 | 支持（reads/writes 参数） |

### 核心区别说明

1. **作用域限制**: `Rename` 会在所有指定的文件中进行全量替换，而 `ChangeOccurrences` 只会影响包含指定偏移量所在的作用域（如函数体、类体等）。

2. **副作用**: `Rename` 在重命名模块时会实际移动/重命名文件，而 `ChangeOccurrences` 不会有任何副作用，只是文本替换。

3. **灵活性**: `ChangeOccurrences` 提供了 `only_calls`、`reads`、`writes` 等参数，可以更精细地控制替换行为。

## 代码示例

### 示例一：基础用法

```python
from rope.base.project import Project
from rope.refactor.rename import ChangeOccurrences

# 创建项目
project = Project("/path/to/your/project")

# 获取文件资源
mod = project.get_resource("module.py")

# 创建 ChangeOccurrences 实例
# 假设 module.py 内容为: a_var = 1; print(a_var)
# offset 指向任意一个 "a_var" 的位置
offset = mod.read().index("a_var")
changer = ChangeOccurrences(project, mod, offset)

# 获取变更并执行
changes = changer.get_changes("new_var")
changes.do()

# 关闭项目
project.close()
```

### 示例二：精细控制替换行为

```python
from rope.refactor.rename import ChangeOccurrences

# 假设文件内容为:
# def old_func():
#     pass
#
# def new_func():
#     pass
#
# result = old_func()  # 调用
# func_ref = old_func  # 引用

mod = project.get_resource("example.py")
offset = mod.read().index("old_func")

changer = ChangeOccurrences(project, mod, offset)

# 只替换函数调用，不替换赋值引用
changes = changer.get_changes("new_func", only_calls=True)
changes.do()
```

### 示例三：在局部作用域中使用

```python
# 文件内容
code = """
counter = 0

def increment():
    counter = counter + 1
    return counter

def decrement():
    counter = counter - 1
    return counter
"""

# 只重命名 increment 函数内部的 counter
mod.write(code)
offset = mod.read().index("counter")  # 第一个 counter 的位置

# 由于 offset 在文件开头，会匹配到全局的 counter
# 如果想在 increment 函数内部操作，需要使用函数内部的 offset
# 例如第二个 "counter" 的位置

# 查找 increment 函数内第一个 counter 的位置
content = mod.read()
increment_start = content.index("def increment")
counter_in_increment = content.index("counter", increment_start)

changer = ChangeOccurrences(project, mod, counter_in_increment)
changes = changer.get_changes("local_counter")
changes.do()
```

## 注意事项

1. **作用域限制**: `ChangeOccurrences` 只会替换指定偏移量所在作用域内的引用。如果偏移量在全局作用域，则只影响全局作用域本身，不会穿透到局部作用域。

2. **不解析导入**: 与 `Rename` 不同，`ChangeOccurrences` 默认不解析导入语句中的引用。

3. **单文件限制**: 目前的实现只支持单个文件内的替换，不支持跨文件操作。

4. **偏移量计算**: 偏移量是基于文件内容的字符偏移，需要准确计算。可以使用 `str.index()` 或 `str.find()` 方法获取。

## 完整示例

```python
from rope.base.project import Project
from rope.refactor.rename import ChangeOccurrences

# 创建项目
project = Project("my_project")

# 创建测试文件
mod = project.root.create_file("test.py")
mod.write("""
def process_data(data):
    result = transform(data)
    return result

def transform(item):
    return item.upper()

output = process_data("hello")
""")

# 将 transform 函数调用替换为其他函数
# 只替换 process_data 函数内部的调用
offset = mod.read().index("transform")
changer = ChangeOccurrences(project, mod, offset)

# 只替换函数调用
changes = changer.get_changes("convert", only_calls=True)
changes.do()

print(mod.read())
# 输出:
# def process_data(data):
#     result = convert(data)
#     return result
#
# def transform(item):
#     return item.upper()
#
# output = process_data("hello")

project.close()
```

## 参考资源

- 源码位置: `/Users/zhushanwen/GitApp/rope/rope/refactor/rename.py`
- 相关类: `rope.refactor.rename.Rename`
- 相关模块: `rope.refactor.occurrences`
