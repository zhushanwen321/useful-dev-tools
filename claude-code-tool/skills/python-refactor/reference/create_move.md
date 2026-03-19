# create_move API 文档

## 1. 基本信息

- **API 完整路径**: `rope.refactor.move.create_move`
- **模块**: `rope.refactor.move`
- **函数说明**: `create_move` 是一个工厂函数，用于自动识别并创建合适的移动重构对象。根据传入的 `resource` 和 `offset` 参数，它会自动判断要移动的元素类型，并返回对应的重构对象（`MoveModule`、`MoveMethod` 或 `MoveGlobal`）。

## 2. 函数签名

```python
def create_move(project, resource, offset=None):
```

## 3. 函数参数

| 参数名 | 类型 | 必填 | 说明 |
|--------|------|------|------|
| `project` | `Project` | 是 | rope 项目对象 |
| `resource` | `Resource` | 是 | 要移动的元素所在的文件资源对象 |
| `offset` | `int` | 否 | 元素在文件中的字符偏移量。如果为 `None`，则表示移动整个模块 |

## 4. 返回值

`create_move` 函数返回一个移动重构对象，根据被移动元素的类型不同，返回不同的类：

| 元素类型 | 返回类型 | 说明 |
|----------|----------|------|
| 模块/包 | `MoveModule` | 移动整个模块文件到另一个包 |
| 类的方法 | `MoveMethod` | 将方法移动到另一个类 |
| 全局函数/类/变量 | `MoveGlobal` | 将全局元素移动到另一个模块 |

**自动识别逻辑**:
1. 如果 `offset` 为 `None`，返回 `MoveModule`
2. 如果元素是类的方法（父对象是 `PyClass`），返回 `MoveMethod`
3. 如果元素是全局函数/类/变量（父对象是 `PyModule` 或 `AssignedName`），返回 `MoveGlobal`
4. 如果元素是模块或包，返回 `MoveModule`

## 5. 使用场景

### 5.1 移动方法到另一个类

将一个类的方法移动到另一个类中。原位置的方法会被替换为对新方法的调用。

```python
from rope.base.project import Project
from rope.refactor import move

# 创建项目
project = Project("/path/to/project")

# 获取包含方法的文件
resource = project.get_resource("module.py")

# 方法在文件中的偏移量（指向方法名）
offset = resource.read().index("method_name")

# 创建移动重构对象
mover = move.create_move(project, resource, offset)

# 获取重构变更
# dest_attr: 目标类中用于访问的属性名
changes = mover.get_changes(dest_attr="target_instance")

# 执行重构
project.do(changes)
project.close()
```

### 5.2 移动全局函数到另一个模块

将模块级别的函数、类或变量移动到另一个模块。会自动处理所有引用该元素的代码，更新导入语句。

```python
from rope.base.project import Project
from rope.refactor import move

project = Project("/path/to/project")

# 获取源文件
resource = project.get_resource("source_module.py")

# 全局函数在文件中的偏移量
offset = resource.read().index("my_function")

# 创建移动重构对象
mover = move.create_move(project, resource, offset)

# 获取重构变更，dest 可以是模块名或 Resource 对象
changes = mover.get_changes(dest="destination_module")

# 执行重构
project.do(changes)
project.close()
```

### 5.3 移动整个模块

将整个模块文件移动到另一个包中。

```python
from rope.base.project import Project
from rope.refactor import move

project = Project("/path/to/project")

# 获取模块资源，offset 为 None 表示移动整个模块
resource = project.get_resource("my_module.py")

# 创建移动重构对象
mover = move.create_move(project, resource, offset=None)

# 获取重构变更，dest 必须是包（文件夹）
changes = mover.get_changes(dest=project.get_resource("new_package"))

# 执行重构
project.do(changes)
project.close()
```

## 6. MoveMethod 类的详细用法

`MoveMethod` 用于将类的方法移动到另一个类。

### 6.1 get_changes 方法

```python
def get_changes(
    self,
    dest_attr: str,
    new_name: Optional[str] = None,
    resources: Optional[List[resources.File]] = None,
):
```

**参数说明**:

| 参数名 | 类型 | 说明 |
|--------|------|------|
| `dest_attr` | `str` | 目标类中用于访问实例的属性名。例如，如果目标类有一个 `self.logger` 属性，则 `dest_attr` 应为 `"logger"` |
| `new_name` | `str` | 可选，新方法名。如果为 `None`，则使用原方法名 |
| `resources` | `List[File]` | 可选，要应用重构的文件列表。默认为项目所有 Python 文件 |

### 6.2 示例：移动方法

```python
from rope.base.project import Project
from rope.refactor import move

project = Project("/path/to/project")

# 源文件包含:
# class Foo:
#     def method_to_move(self, x):
#         return x * 2
#
# class Bar:
#     pass

resource = project.get_resource("module.py")
offset = resource.read().index("method_to_move")

mover = move.create_move(project, resource, offset)

# 将方法移动到 Bar 类，通过 self.bar 访问
changes = mover.get_changes(dest_attr="bar")

project.do(changes)
project.close()

# 重构后:
# class Foo:
#     def method_to_move(self, x):
#         return self.bar.method_to_move(x)
#
# class Bar:
#     def method_to_move(self, x):
#         return x * 2
```

## 7. MoveGlobal 类的详细用法

`MoveGlobal` 用于移动模块级别的函数、类或变量。

### 7.1 get_changes 方法

```python
def get_changes(
    self,
    dest: Optional[Union[str, resources.Resource]],
    resources: Optional[List[resources.File]] = None,
):
```

**参数说明**:

| 参数名 | 类型 | 说明 |
|--------|------|------|
| `dest` | `str` 或 `Resource` | 目标模块，可以是模块名（字符串）或 Resource 对象 |
| `resources` | `List[File]` | 可选，要应用重构的文件列表。默认为项目所有 Python 文件 |

### 7.2 示例：移动全局函数

```python
from rope.base.project import Project
from rope.refactor import move

project = Project("/path/to/project")

# source_module.py
# def helper():
#     return "hello"

resource = project.get_resource("source_module.py")
offset = resource.read().index("helper")

mover = move.create_move(project, resource, offset)

# 移动到 target_module
changes = mover.get_changes(dest="target_module")

project.do(changes)
project.close()

# 重构后:
# source_module.py: helper 被移除
# target_module.py: 新增 helper 函数
# 其他引用 source_module.helper 的文件会自动更新导入
```

### 7.3 示例：移动全局变量

```python
from rope.base.project import Project
from rope.refactor import move

project = Project("/path/to/project")

# config.py
# MAX_SIZE = 100

resource = project.get_resource("config.py")
offset = resource.read().index("MAX_SIZE")

mover = move.create_move(project, resource, offset)

# 移动到 constants 模块
changes = mover.get_changes(dest="constants")

project.do(changes)
project.close()
```

## 8. MoveModule 类的详细用法

`MoveModule` 用于移动整个模块文件到另一个包。

### 8.1 get_changes 方法

```python
def get_changes(
    self,
    dest: resources.Resource,
    resources: Optional[List[resources.File]] = None,
):
```

**参数说明**:

| 参数名 | 类型 | 说明 |
|--------|------|------|
| `dest` | `Resource` | 目标包，必须是一个包（包含 `__init__.py` 的文件夹） |
| `resources` | `List[File]` | 可选，要应用重构的文件列表。默认为项目所有 Python 文件 |

### 8.2 示例：移动模块

```python
from rope.base.project import Project
from rope.refactor import move

project = Project("/path/to/project")

# 移动 utils.py 到 packages/utils/ 包
resource = project.get_resource("utils.py")
mover = move.create_move(project, resource, offset=None)  # offset=None 表示整个模块

dest_package = project.get_resource("packages/utils")
changes = mover.get_changes(dest=dest_package)

project.do(changes)
project.close()

# 重构后:
# packages/utils/__init__.py  (原 utils.py 的内容)
# 原位置的 utils.py 被移除
# 所有导入 utils 的代码会自动更新
```

## 9. 与 MoveModule 的区别

| 特性 | `create_move` | `MoveModule` |
|------|---------------|--------------|
| **用途** | 移动方法、全局函数/类/变量、或整个模块 | 仅用于移动整个模块文件 |
| **返回类型** | 自动识别返回 `MoveMethod`/`MoveGlobal`/`MoveModule` | 直接返回 `MoveModule` |
| **参数** | 需要 `offset` 参数来指定具体元素 | 不需要 `offset` |
| **适用场景** | 移动代码元素 | 移动文件 |

**选择建议**:
- 如果要移动方法、函数、类或变量，使用 `create_move`
- 如果要移动整个模块文件，可以直接使用 `MoveModule` 或调用 `create_move` 并传入 `offset=None`

## 10. 常见问题

### 10.1 如何获取元素的偏移量？

可以使用字符串的 `index()` 方法获取字符偏移量：

```python
source = resource.read()
offset = source.index("function_name")  # 返回第一个字符的位置
# 或者更精确地指向函数名
offset = source.index("def function_name") + 4  # 偏移到函数名开始
```

### 10.2 移动方法时 dest_attr 是什么？

`dest_attr` 是目标类中用于访问实例的属性名。例如：

```python
class TargetClass:
    def __init__(self):
        self.helper = Helper()

# 移动方法时，dest_attr="helper"
# 原方法会变成: return self.helper.new_method(...)
```

### 10.3 如何只对特定文件应用重构？

可以通过 `resources` 参数指定要处理的文件列表：

```python
# 只对指定文件应用重构
changes = mover.get_changes(
    dest="target_module",
    resources=[project.get_resource("file1.py"), project.get_resource("file2.py")]
)
```

### 10.4 如何处理移动目标不存在的情况？

如果目标模块不存在，会抛出 `RefactoringError`：

```python
try:
    changes = mover.get_changes(dest="non_existent_module")
except exceptions.RefactoringError as e:
    print(f"错误: {e}")
```

### 10.5 如何重命名被移动的元素？

对于 `MoveMethod`，可以使用 `new_name` 参数：

```python
changes = mover.get_changes(dest_attr="target", new_name="new_method_name")
```

对于 `MoveGlobal`，目标名称保持不变。

### 10.6 如何查看重构的变更而不立即执行？

可以使用 `get_changes()` 方法获取变更，然后查看或者选择性地应用：

```python
mover = move.create_move(project, resource, offset)
changes = mover.get_changes(dest="target_module")

# 查看变更内容
print(changes.get_description())

# 如果满意再执行
project.do(changes)
```

## 11. 完整示例

### 示例：完整的移动方法流程

```python
from rope.base.project import Project
from rope.refactor import move

# 1. 创建项目
project = Project("/path/to/your/project")

# 2. 获取源文件
source_file = project.get_resource("source.py")

# 3. 定义要移动的方法（在文件中的偏移量）
source_code = source_file.read()
method_name = "calculate_total"
offset = source_code.index(method_name)

# 4. 创建移动重构对象
mover = move.create_move(project, source_file, offset)

# 5. 获取变更
# 假设目标类有一个 self.calculator 属性
changes = mover.get_changes(dest_attr="calculator")

# 6. 查看变更
print("变更描述:", changes.get_description())

# 7. 执行变更
project.do(changes)

# 8. 关闭项目
project.close()
```

### 示例：完整的移动全局函数流程

```python
from rope.base.project import Project
from rope.refactor import move

project = Project("/path/to/project")

# 移动全局函数
source = project.get_resource("utils.py")
offset = source.read().index("format_date")

mover = move.create_move(project, source, offset)

# dest 可以是字符串（模块名）或 Resource 对象
changes = mover.get_changes(dest="formatters")

project.do(changes)
project.close()
```

## 12. 参考资源

- **源码位置**: `/Users/zhushanwen/GitApp/rope/rope/refactor/move.py`
- **测试用例**: `ropetest/refactor/movetest.py`
- **相关 API**:
  - `rope.refactor.move.MoveMethod`
  - `rope.refactor.move.MoveGlobal`
  - `rope.refactor.move.MoveModule`
