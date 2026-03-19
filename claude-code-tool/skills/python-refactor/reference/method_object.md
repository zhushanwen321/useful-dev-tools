# MethodObject

## 基本信息

- **API 完整路径**: `rope.refactor.method_object.MethodObject`
- **模块**: `rope.refactor.method_object`
- **类说明**: 将方法转换为方法对象（命令模式）。该重构功能将一个函数或方法提取为一个独立的类，原函数的位置会被替换为该类的实例化调用。这是一种实现命令模式的重构技术，适用于将复杂方法封装为可复用的对象。

## 继承关系

```
MethodObject
```

`MethodObject` 是独立的重构类，不继承其他基类。

## 构造函数

```python
MethodObject(project, resource, offset)
```

### 参数说明

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `project` | `Project` | 是 | rope 项目对象，用于访问项目资源和代码分析功能 |
| `resource` | `Resource` | 是 | 要进行重构的文件资源对象（如 `File` 对象） |
| `offset` | `int` | 是 | 函数/方法在文件中的偏移量（字符索引，从 0 开始） |

### 偏移量说明

- `offset` 应指向函数定义的开始位置（即 `def` 关键字的位置）
- 可以使用 `source.index("function_name")` 或 `codeanalyze.SourceLinesAdapter` 来获取偏移量

### 异常处理

如果在指定偏移位置不是函数定义，将抛出 `rope.base.exceptions.RefactoringError` 异常，错误消息为：
> "Replace method with method object refactoring should be performed on a function."

## 常用方法

### get_changes()

```python
get_changes(classname=None, new_class_name=None)
```

执行方法对象重构并返回变更集合。

#### 参数说明

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `classname` | `str` | `None` | 新生成类的名称 |
| `new_class_name` | `str` | `None` | **已废弃**，请使用 `classname` 参数 |

#### 返回值

返回 `ChangeSet` 对象，包含文件内容的变更：
1. 原函数位置被替换为新类的实例化调用（`return ClassName(args)()`）
2. 新类被插入到模块的适当位置

#### 废弃警告

`new_class_name` 参数已废弃，请使用 `classname` 参数。

---

### get_new_class()

```python
get_new_class(name)
```

生成新类的代码字符串（不执行重构）。

#### 参数说明

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `name` | `str` | 是 | 新类的名称 |

#### 返回值

返回新类的代码字符串，格式如下：

```python
class {name}(object):

    def __init__(self, arg1, arg2, ...):
        self.arg1 = arg1
        self.arg2 = arg2
        ...

    def __call__(self):
        # 原函数体
        ...
```

#### 示例

```python
# 假设原函数为：
def add(a, b):
    return a + b

# get_new_class("Adder") 返回：
class Adder(object):

    def __init__(self, a, b):
        self.a = a
        self.b = b

    def __call__(self):
        return self.a + self.b
```

## 使用场景

### 1. 将复杂方法提取为独立类

当一个方法包含大量局部变量和复杂逻辑时，将其转换为方法对象可以：
- 将所有局部变量转换为类的实例变量
- 使方法体变得更容易理解和测试
- 为方法添加更多状态管理能力

### 2. 命令模式重构

方法对象是实现命令模式的基础：
- 将操作封装为对象
- 支持操作的延迟执行
- 便于实现撤销/重做功能

### 3. 分离关注点

当一个方法处理多种职责时，可以将其提取为独立类，以便：
- 独立测试各个部分
- 更容易修改其中一部分而不影响其他部分

## 代码示例

### 基础用法

```python
from rope.base.project import Project
from rope.refactor.method_object import MethodObject

# 创建项目
project = Project('/path/to/project')

# 获取要重构的文件
mod = project.get_resource('module.py')

# 获取代码
source = mod.read()

# 创建 MethodObject 实例
# offset 指向函数名的起始位置
offset = source.index('calculate')
replacer = MethodObject(project, mod, offset)

# 执行重构
changes = replacer.get_changes('Calculator')
project.do(changes)

# 关闭项目
project.close()
```

### 重构前后的代码变化

**重构前：**

```python
def calculate(a, b, c):
    result = a * b + c
    intermediate = result * 2
    return intermediate + 10
```

**重构后：**

```python
def calculate(a, b, c):
    return Calculate(a, b, c)()


class Calculate(object):

    def __init__(self, a, b, c):
        self.a = a
        self.b = b
        self.c = c

    def __call__(self):
        result = self.a * self.b + self.c
        intermediate = result * 2
        return intermediate + 10
```

### 处理 self 参数

当方法包含 `self` 参数时，会被重命名为 `host`：

**重构前：**

```python
class MyClass:
    def process(self, data):
        return self.transform(data)

    def transform(self, x):
        return x * 2
```

**重构后：**

```python
class MyClass:
    def process(self, data):
        return Process(self, data)()

    def transform(self, x):
        return x * 2


class Process(object):

    def __init__(self, host, data):
        self.host = host
        self.data = data

    def __call__(self):
        return self.host.transform(self.data)
```

### 获取新类代码预览

在执行重构前，可以先预览新类的代码：

```python
from rope.base.project import Project
from rope.refactor.method_object import MethodObject

project = Project('/path/to/project')
mod = project.get_resource('module.py')
source = mod.read()

offset = source.index('my_function')
replacer = MethodObject(project, mod, offset)

# 预览新类代码（不执行重构）
new_class_code = replacer.get_new_class('MyFunction')
print(new_class_code)
```

## 注意事项

1. **函数位置**: 构造函数中的 `offset` 必须指向函数定义的开始位置，而不是函数体内的任意位置
2. **类方法**: 支持对类中的方法进行重构，但不会保留原类的上下文（self 会被作为参数传递）
3. **返回值处理**: 原函数位置会被替换为 `return ClassName(args)()`，这要求原函数有返回值或可以添加 return 语句
4. **参数处理**: 所有参数（包括 `*args` 和 `**kwargs`）都会被正确处理并传递到新类的 `__init__` 方法中

## 相关文档

- [ExtractMethod](./extract_method.md) - 将代码片段提取为方法
- [IntroduceFactory](./introduce_factory.md) - 引入工厂方法
- [Rename](./rename.md) - 重命名重构
