# rope EncapsulateField API 详细使用文档

## 1. 基本信息

- **API 完整路径**: `rope.refactor.encapsulate_field.EncapsulateField`
- **类说明**: 将类的公开字段封装为私有属性，并自动生成 getter 和 setter 方法。这是面向对象编程中常用的设计模式，用于实现数据封装和信息隐藏。
- **源码位置**: `/Users/zhushanwen/GitApp/rope/rope/refactor/encapsulate_field.py`

```python
from rope.refactor.encapsulate_field import EncapsulateField
```

## 2. 构造函数参数

```python
EncapsulateField(project, resource, offset)
```

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `project` | `Project` | 是 | rope 项目对象 |
| `resource` | `Resource` | 是 | 包含要封装字段的 Python 文件资源对象 |
| `offset` | `int` | 是 | 指向要封装字段名称的字符偏移量 |

### 参数说明

- **project**: 通过 `rope.base.project.Project` 创建的项目实例
- **resource**: 通过 `project.get_resource()` 或类似方法获取的文件资源
- **offset**: 字段名在文件中的起始位置（从 0 开始）。需要指向字段名的第一个字符，而不是类名或其他位置

### 构造函数的内部逻辑

1. 调用 `worder.get_name_at()` 获取 offset 位置处的字段名
2. 调用 `evaluate.eval_location()` 获取该字段对应的 pyname 对象
3. 验证该 pyname 是否为类的属性（通过 `_is_an_attribute()` 方法）
4. 如果不是类属性，抛出 `RefactoringError` 异常

## 3. 常用方法

### get_changes(getter=None, setter=None, resources=None, task_handle=taskhandle.DEFAULT_TASK_HANDLE)

获取重构所产生的代码变更。

#### 参数

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `getter` | `str` | `None` | 自定义 getter 方法名。如果为 `None`，默认使用 `get_${字段名}` |
| `setter` | `str` | `None` | 自定义 setter 方法名。如果为 `None`，默认使用 `set_${字段名}` |
| `resources` | `list[Resource]` | `None` | 要应用重构的文件列表。如果为 `None`，搜索项目中的所有 Python 文件 |
| `task_handle` | `TaskHandle` | `DEFAULT_TASK_HANDLE` | 任务句柄，用于显示进度 |

#### 返回值

返回 `ChangeSet` 对象，包含所有需要修改的文件和内容。

#### 方法内部逻辑

1. 如果未指定 getter/setter，使用默认命名规则
2. 创建 `GetterSetterRenameInModule` 对象来处理模块中的引用替换
3. 遍历所有指定的资源文件：
   - 对于定义字段的模块：在类中添加 getter 和 setter 方法，并替换类内部对字段的直接引用
   - 对于其他模块：仅替换对字段的引用为 getter/setter 调用
4. 返回包含所有变更的 `ChangeSet`

### get_field_name()

获取要封装的字段名称。

#### 返回值

返回字段名字符串。

## 4. 使用场景

### 场景一：将公开字段转为私有属性

将类中直接暴露的字段改为私有，并通过 getter/setter 访问：

```python
# 重构前
class User:
    def __init__(self):
        self.name = "Alice"
        self.age = 30

# 重构后
class User:
    def __init__(self):
        self.name = "Alice"
        self.age = 30

    def get_name(self):
        return self.name

    def set_name(self, value):
        self.name = value

    def get_age(self):
        return self.age

    def set_age(self, value):
        self.age = value
```

### 场景二：自动更新所有引用

当其他模块使用了该类的字段时，EncapsulateField 会自动将所有引用更新为 getter/setter 调用：

```python
# 其他文件中的代码
import mod
user = mod.User()
print(user.name)      # 变为 user.get_name()
user.age = 25        # 变为 user.set_age(25)
user.age += 1        # 变为 user.set_age(user.get_age() + 1)
```

### 场景三：自定义方法名

可以指定自定义的 getter 和 setter 方法名：

```python
changes = EncapsulateField(project, resource, offset).get_changes(
    getter="get_username",
    setter="set_username"
)
```

这将生成 `get_username()` 和 `set_username()` 方法，而不是默认的 `get_name()` 和 `set_name()`。

## 5. 代码示例

### 完整示例

```python
from rope.base.project import Project
from rope.refactor.encapsulate_field import EncapsulateField

# 创建项目
project = Project('/path/to/your/project')

# 获取要修改的文件
resource = project.get_resource('module.py')

# 要封装的字段在文件中的位置
# 假设 module.py 内容为:
# class MyClass:
#     def __init__(self):
#         self.my_field = 100
code = resource.read()
offset = code.index('my_field')  # 获取字段名的起始位置

# 创建 EncapsulateField 对象
encapsulator = EncapsulateField(project, resource, offset)

# 获取变更（使用自定义方法名）
changes = encapsulator.get_changes(
    getter='get_my_field',
    setter='set_my_field'
)

# 应用变更
project.do(changes)

# 关闭项目
project.close()
```

### 只在指定文件中应用重构

```python
# 只在特定文件中应用重构，而不是整个项目
mod1 = project.get_resource('mod1.py')
mod2 = project.get_resource('mod2.py')

changes = EncapsulateField(project, resource, offset).get_changes(
    resources=[mod1, mod2]
)
```

### 处理错误

```python
from rope.base import exceptions

try:
    encapsulator = EncapsulateField(project, resource, offset)
    changes = encapsulator.get_changes()
except exceptions.RefactoringError as e:
    print(f"重构错误: {e}")
```

可能抛出的异常：
- `RefactoringError`: 当选择的不是类属性时抛出，例如选择了函数参数、模块级变量等

## 6. 注意事项

1. **字段必须是类属性**: EncapsulateField 只能用于类中定义的实例属性或类属性，不能用于局部变量或函数参数

2. **元组赋值限制**: 不支持在元组赋值中使用字段，例如 `a, b = self.attr` 会抛出异常

3. **命名冲突**: 自定义 getter/setter 名称时，需要确保不会与类中现有方法冲突

4. **性能考虑**: 当不指定 `resources` 参数时，会搜索整个项目所有 Python 文件，对于大型项目可能会比较慢，建议明确指定资源列表

5. **增量重构**: 多次调用 `get_changes()` 会基于当前代码状态生成变更，如果已经执行过一次封装，再次执行会添加新的 getter/setter（可能产生重复方法）
