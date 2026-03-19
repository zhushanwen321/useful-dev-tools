# LocalToField API 文档

## 基本信息

- **完整路径**: `rope.refactor.localtofield.LocalToField`
- **类说明**: 将方法内的局部变量转换为类字段（Instance Attribute）

`LocalToField` 是一个重构工具，用于将类的方法中定义的局部变量转换为类的实例字段（即添加 `self.` 前缀的属性）。

## 构造函数

### 参数说明

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `project` | `Project` | 是 | rope 项目对象 |
| `resource` | `Resource` | 是 | 包含待转换变量的 Python 文件资源 |
| `offset` | `int` | 是 | 目标局部变量名的字符偏移量（offset） |

### 示例

```python
from rope.base.project import Project
from rope.refactor.localtofield import LocalToField

# 创建项目
project = Project('/path/to/project')

# 获取资源
resource = project.get_resource('module.py')

# 指定要转换的变量位置（变量名的 offset）
offset = resource.read().index('var') + 1  # +1 是因为 offset 基于 1

# 创建 LocalToField 重构对象
local_to_field = LocalToField(project, resource, offset)
```

## 常用方法

### get_changes()

执行重构转换并返回变更对象。

**返回值**: `Changes` - 包含所有文件变更的重构变更对象

**抛出异常**:
- `RefactoringError`: 当转换不适用于当前选中的变量时抛出，包括：
  - 选中的是全局变量（非方法内的局部变量）
  - 选中的是类字段（已带有 `self.` 前缀）
  - 选中的是函数参数

**使用方式**:

```python
# 获取变更
changes = local_to_field.get_changes()

# 应用变更
project.do(changes)
```

## 使用场景

### 适用场景

1. **方法内局部变量需要提升为实例属性**: 当某个局部变量在方法中被多次使用，且需要在该类的其他方法中访问时
2. **方法局部变量需要在对象生命周期内持久化**: 当变量值需要在多次方法调用之间保持时
3. **代码重构**: 将方法内的临时变量重构为更合适的实例字段

### 不适用场景

1. **全局变量**: 不能将模块级全局变量转换为字段
2. **类字段**: 不能将已经是 `self.xxx` 形式的变量再次转换
3. **函数参数**: 不能将方法参数转换为字段
4. **静态方法中的变量**: 仅适用于实例方法

## 代码示例

### 基本示例

转换方法内的局部变量为类字段：

```python
from rope.base.project import Project
from rope.refactor.localtofield import LocalToField

# 初始代码
# class A:
#     def a_func(self):
#         var = 10

project = Project('/path/to/project')
resource = project.get_resource('module.py')

# 定位到 var 变量
code = resource.read()
offset = code.index('var') + 1

# 执行转换
local_to_field = LocalToField(project, resource, offset)
changes = local_to_field.get_changes()
project.do(changes)

# 转换后的代码
# class A:
#     def a_func(self):
#         self.var = 10
```

### 自定义 self 参数名

如果方法使用非标准的 self 参数名（如 `myself`），重构会自动适配：

```python
# 初始代码
# class A:
#     def a_func(myself):
#         var = 10

# 重构后
# class A:
#     def a_func(myself):
#         myself.var = 10
```

### 完整示例

```python
import os
import shutil
from rope.base.project import Project
from rope.refactor.localtofield import LocalToField

# 创建临时项目目录
project_path = '/tmp/rope_demo'
if os.path.exists(project_path):
    shutil.rmtree(project_path)
os.makedirs(project_path)

# 创建测试文件
test_file = os.path.join(project_path, 'example.py')
with open(test_file, 'w') as f:
    f.write('''class Calculator:
    def __init__(self):
        pass

    def add(self, a, b):
        result = a + b
        return result

    def multiply(self, a, b):
        result = a * b
        return result
''')

# 创建 rope 项目
project = Project(project_path)

# 将 add 方法中的 result 转换为字段
resource = project.get_resource('example.py')
code = resource.read()

# 找到第一个 result 的位置（add 方法中的）
offset = code.index('result') + 1

try:
    # 执行重构
    local_to_field = LocalToField(project, resource, offset)
    changes = local_to_field.get_changes()
    project.do(changes)

    # 查看结果
    with open(test_file) as f:
        print(f.read())
except Exception as e:
    print(f"重构失败: {e}")

# 清理项目
project.close()
shutil.rmtree(project_path)
```

## 注意事项

1. **偏移量计算**: `offset` 应该是变量名的起始位置，通常使用 `str.index() + 1` 获得
2. **重复变量名**: 如果类中已存在同名字段，重构仍会执行（可能产生命名冲突）
3. **内部实现**: 该重构实际上使用了 `Rename` 重构，将变量名从 `var` 重命名为 `self.var`
4. **只作用于当前文件**: 重构默认只影响当前资源文件中的变量引用

## 异常处理

```python
from rope.base.exceptions import RefactoringError

try:
    changes = local_to_field.get_changes()
    project.do(changes)
except RefactoringError as e:
    print(f"重构错误: {e}")
    # 处理以下情况：
    # - "Convert local variable to field should be performed on a local variable of a method."
    # - "The field xxx already exists"
```

## 源码位置

- 主文件: `/Users/zhushanwen/GitApp/rope/rope/refactor/localtofield.py`
- 测试文件: `/Users/zhushanwen/GitApp/rope/ropetest/refactor/__init__.py` (LocalToFieldTest 类)
