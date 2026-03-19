# IntroduceFactory API 文档

## 基本信息

- **API 完整路径**：`rope.refactor.introduce_factory.IntroduceFactory`
- **类说明**：引入工厂方法（Factory Method）重构工具，用于将类的直接实例化替换为通过工厂方法进行创建。
- **别名**：`rope.refactor.introduce_factory.IntroduceFactoryRefactoring`

## 概述

`IntroduceFactory` 是一个代码重构工具，用于将类实例化的方式改为使用工厂方法。这是一种常用的设计模式，将对象的创建逻辑封装在独立的方法中，从而实现更灵活的对象创建和更好的代码解耦。

该重构支持两种模式：
1. **静态工厂方法**：在类内部添加一个 `@staticmethod` 装饰的静态方法
2. **全局工厂方法**：在模块级别添加一个独立的工厂函数

## 构造函数

```python
IntroduceFactory(project, resource, offset)
```

### 参数说明

| 参数 | 类型 | 说明 |
|------|------|------|
| `project` | `rope.base.project.Project` | rope 项目对象 |
| `resource` | `rope.base.resource.Resource` | 包含要重构的类的 Python 文件资源 |
| `offset` | `int` | 类名在文件中的字符偏移量（offset） |

### 异常

如果指定位置不是一个有效的类，将抛出 `rope.base.exceptions.RefactoringError` 异常，错误信息为 `"Introduce factory should be performed on a class."`。

## 常用方法

### get_changes()

```python
get_changes(factory_name, global_factory=False, resources=None, task_handle=taskhandle.DEFAULT_TASK_HANDLE)
```

获取重构所产生的代码变更。

#### 参数说明

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `factory_name` | `str` | 必填 | 工厂方法的名称 |
| `global_factory` | `bool` | `False` | 是否创建全局工厂方法。为 `True` 时在模块级别创建函数，为 `False` 时在类内部创建静态方法 |
| `resources` | `List[rope.base.resource.File]` | `None` | 要应用重构的文件列表。默认为 `None`，表示搜索项目中的所有 Python 文件 |
| `task_handle` | `rope.base.taskhandle.TaskHandle` | `DEFAULT_TASK_HANDLE` | 任务句柄，用于跟踪重构进度 |

#### 返回值

返回 `rope.base.change.ChangeSet` 对象，包含所有代码变更。可以通过 `project.do(changes)` 来应用这些变更。

#### 异常

- 当 `global_factory=True` 且类位于嵌套作用域（如内部类）时，抛出 `RefactoringError` 异常，错误信息为 `"Cannot make global factory method for nested classes."`

### get_name()

```python
get_name()
```

返回要重构的类的名称。

#### 返回值

返回类名字符串（`str`）。

## 使用场景

### 1. 统一对象创建入口

当需要统一管理类的实例化逻辑时，可以使用工厂方法。例如：

```python
# 之前
obj = MyClass(arg1, arg2)

# 之后
obj = MyClass.create(arg1, arg2)
```

### 2. 实现多态创建

工厂方法允许在子类中重写创建逻辑，实现多态的对象创建。

### 3. 隐藏具体实现

通过工厂方法可以隐藏类的具体实现细节，调用者只需要知道使用哪个工厂方法即可。

### 4. 延迟实例化

工厂方法可以实现延迟加载，只有在真正需要时才创建对象实例。

## 代码示例

### 示例 1：基本用法（静态工厂方法）

```python
from rope.base.project import Project
from rope.refactor.introduce_factory import IntroduceFactory

# 创建项目
project = Project('path/to/project')

# 获取要重构的文件和位置
mod = project.get_resource('module.py')

# 创建重构器，offset 指向类名的位置
factory = IntroduceFactory(project, mod, mod.read().index('MyClass') + 1)

# 获取变更
changes = factory.get_changes('create')

# 应用变更
project.do(changes)

# 关闭项目
project.close()
```

重构前的代码：
```python
class MyClass:
    def __init__(self, value):
        self.value = value
```

重构后的代码：
```python
class MyClass:
    def __init__(self, value):
        self.value = value

    @staticmethod
    def create(*args, **kwds):
        return MyClass(*args, **kwds)
```

### 示例 2：使用全局工厂方法

```python
# 创建重构器
factory = IntroduceFactory(project, mod, offset)

# 获取全局工厂方法变更
changes = factory.get_changes('create', global_factory=True)

# 应用变更
project.do(changes)
```

重构前的代码：
```python
class MyClass:
    an_attr = 10

obj = MyClass()
```

重构后的代码：
```python
class MyClass:
    an_attr = 10

def create(*args, **kwds):
    return MyClass(*args, **kwds)

obj = create()
```

### 示例 3：指定特定文件范围

```python
# 只在特定文件中应用重构
resources = [project.get_resource('main.py'), project.get_resource('utils.py')]
changes = factory.get_changes('create', resources=resources)
project.do(changes)
```

### 示例 4：获取类名

```python
factory = IntroduceFactory(project, mod, offset)
class_name = factory.get_name()  # 返回类名，如 'MyClass'
```

## 注意事项

1. **嵌套类限制**：全局工厂方法不能用于嵌套类（位于函数内部的类），这会抛出 `RefactoringError` 异常。

2. **构造函数参数**：工厂方法使用 `*args, **kwds` 传递参数，这样可以适配任何构造函数签名。

3. **自动更新引用**：重构会自动更新项目中所有对原类的直接调用，将其替换为工厂方法调用。

4. **导入处理**：对于跨模块的调用，全局工厂方法会自动处理导入语句。

5. **任务进度**：可以通过自定义 `task_handle` 来监听重构进度，这在处理大型项目时很有用。

## 错误处理

常见的异常情况：

- `RefactoringError`: 当指定位置不是类时，或尝试对嵌套类使用全局工厂方法时抛出
- 可能的文件系统相关错误：如资源不存在等

建议在使用时进行适当的异常捕获：

```python
from rope.base.exceptions import RefactoringError

try:
    factory = IntroduceFactory(project, resource, offset)
    changes = factory.get_changes('create')
    project.do(changes)
except RefactoringError as e:
    print(f"重构错误: {e}")
```
