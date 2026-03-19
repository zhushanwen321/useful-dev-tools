# rope Rename API 详细使用文档

## 1. 基本信息

- **API 完整路径**: `rope.refactor.rename.Rename`
- **类说明**: 用于重命名函数、类、变量、模块、包的工具类
- **源码位置**: `/Users/zhushanwen/GitApp/rope/rope/refactor/rename.py`

```python
from rope.refactor.rename import Rename
```

## 2. 构造函数参数

```python
Rename(project, resource, offset=None)
```

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `project` | `Project` | 必填 | rope 项目对象 |
| `resource` | `Resource` | 必填 | 要重命名的文件/文件夹资源对象 |
| `offset` | `int` | `None` | 偏移量，指向要重命名的名称位置 |

### offset 参数的关键作用

**这是 Rename API 最重要的参数**，不同取值决定了完全不同的行为：

- **`offset=None`**: 重命名模块（整个文件或包）
- **`offset=具体数值`**: 重命名函数、类、变量等代码元素

当 `offset=None` 时，构造函数中的逻辑：

```python
# rename.py 第 41-50 行
else:
    if not resource.is_folder() and resource.name == "__init__.py":
        resource = resource.parent
    dummy_pymodule = libutils.get_string_module(self.project, "")
    self.old_instance = None
    self.old_pyname = pynames.ImportedModule(dummy_pymodule, resource=resource)
    if resource.is_folder():
        self.old_name = resource.name
    else:
        self.old_name = resource.name[:-3]  # 去掉 .py 后缀
```

## 3. 常用方法

### get_old_name()

返回要重命名的原始名称。

```python
def get_old_name(self):
    return self.old_name
```

### get_changes(new_name, **kwargs)

生成重命名的变更集合。

```python
def get_changes(
    self,
    new_name,           # 新的名称
    in_file=None,       # 已废弃，使用 resources 代替
    in_hierarchy=False, # 是否重命名层次结构中的所有方法
    unsure=None,        # 不确定匹配的处理函数
    docs=False,         # 是否重命名文档字符串和注释中的名称
    resources=None,     # 要处理的文件列表，None 表示所有 Python 文件
    task_handle=taskhandle.DEFAULT_TASK_HANDLE  # 任务处理器
):
```

## 4. 使用场景

### 场景一：重命名函数、类、变量

当需要重命名函数、类、方法、变量等代码元素时，需要：

1. 获取要重命名的资源（文件）
2. 计算名称在文件中的偏移量（offset）
3. 将 offset 传递给 Rename 构造函数

**关键点**: 必须传入具体的 `offset` 值，该值指向要重命名的名称位置。

```python
# 重命名函数 my_function -> new_function_name
offset = 100  # 假设 my_function 在文件中的偏移量是 100
renamer = Rename(project, resource, offset=offset)
changes = renamer.get_changes("new_function_name")
```

### 场景二：重命名模块文件

当需要重命名整个 Python 文件或包时，需要：

1. 获取模块资源
2. 设置 `offset=None`
3. 传入 `new_name`（不要包含 .py 后缀）

**关键点**: 必须设置 `offset=None`，这会告诉 rope 要重命名整个模块。

```python
# 重命名模块 old_module -> new_module
renamer = Rename(project, resource, offset=None)
changes = renamer.get_changes("new_module")  # 不要加 .py
```

### offset 参数总结

| offset 值 | 行为 | 适用场景 |
|-----------|------|----------|
| `None` | 重命名模块（文件或包） | 文件重命名、包重命名 |
| 具体整数 | 重命名代码元素 | 函数、类、变量、方法等 |

## 5. 代码示例

### 示例一：重命名函数

假设有以下文件 `example.py`：

```python
def greet(name):
    return f"Hello, {name}!"

if __name__ == "__main__":
    print(greet("World"))
```

使用 rope 重命名 `greet` 函数：

```python
from rope.base.project import Project
from rope.refactor.rename import Rename
from rope.base import libutils

# 创建项目
project = Project("/path/to/your/project")

# 获取文件资源
resource = project.get_resource("example.py")

# 获取文件内容，查找要重命名的位置
content = resource.read()
# 假设我们要重命名 "greet"，它在文件中偏移量是 0
# 实际使用时，需要通过 AST 分析或字符串查找来定位偏移量

# 方法一：使用 rope 的 worder 查找偏移量
from rope.base import worder
offset = worder.Worder(content).find_occurrences("greet")[0].start

# 方法二：手动指定偏移量（不推荐）
# offset = 0  # "def greet" 的起始位置

# 创建重命名对象
renamer = Rename(project, resource, offset=offset)

# 获取变更
changes = renamer.get_changes("say_hello")

# 执行变更
project.do(changes)

# 关闭项目
project.close()
```

### 示例二：重命名类

```python
from rope.base.project import Project
from rope.refactor.rename import Rename

project = Project("/path/to/project")
resource = project.get_resource("my_module.py")

# 假设 MyClass 在偏移量 100 处
offset = 100

renamer = Rename(project, resource, offset=offset)
changes = renamer.get_changes("NewClassName")

project.do(changes)
project.close()
```

### 示例三：重命名模块文件（需要 VCS）

重命名模块文件时，rope 会：
1. 修改所有引用该模块的文件中的 import 语句
2. 实际移动文件（通过 MoveResource）

```python
from rope.base.project import Project
from rope.refactor.rename import Rename

# 创建项目（项目必须在版本控制下）
project = Project("/path/to/project")

# 获取模块资源
resource = project.get_resource("old_module.py")

# 重命名模块：offset=None
renamer = Rename(project, resource, offset=None)

# 获取变更
changes = renamer.get_changes("new_module")

# 执行变更
project.do(changes)
project.close()
```

**重要**: 重命名模块需要项目处于版本控制之下（Git、Mercurial、SVN 等），因为：

1. rope 通过 `fscommands` 与版本控制系统交互
2. `MoveResource` 调用 `self._operations.move()` 来移动文件
3. 如果没有 VCS，rope 使用 `FileSystemCommands`，只是简单的文件移动，不会更新 VCS 的跟踪状态

rope 会自动检测项目中的版本控制系统：

```python
# rope/base/fscommands.py 中的检测逻辑
def create_fscommands(root):
    commands = {
        ".hg": MercurialCommands,
        ".svn": SubversionCommands,
        ".git": GITCommands,
        "_svn": SubversionCommands,
        "_darcs": DarcsCommands,
    }
    # 根据目录中的 VCS 标记文件自动选择
```

## 6. 常见错误

### 错误一：模块重命名未在版本控制下

```python
# 错误信息
# 实际上 rope 不会抛出特定异常，但 MoveResource.do() 会失败
# 或者 VCS 不会跟踪重命名后的文件
```

**解决方案**: 确保项目在 Git、Mercurial 或 SVN 版本控制下。

### 错误二：名称冲突

```python
# 如果新名称与现有名称冲突，会引发异常
from rope.base import exceptions

try:
    renamer = Rename(project, resource, offset=offset)
    changes = renamer.get_changes("conflicting_name")
except exceptions.RefactoringError as e:
    print(f"重命名失败: {e}")
```

### 错误三：引用未找到

```python
# 如果 offset 指向的位置无法解析为有效的 Python 标识符
# 会抛出 RefactoringError
from rope.base import exceptions

try:
    renamer = Rename(project, resource, offset=invalid_offset)
except exceptions.RefactoringError as e:
    print(f"无效的重命名位置: {e}")
```

### 错误四：使用了 Python 关键字

```python
# 新名称不能是 Python 关键字
renamer = Rename(project, resource, offset=offset)
try:
    changes = renamer.get_changes("class")  # 会失败
except exceptions.RefactoringError as e:
    print(f"无效名称: {e}")
```

## 7. 注意事项

### 7.1 版本控制要求

- **模块重命名强烈建议在版本控制下进行**
- rope 支持的 VCS：Git、Mercurial (Hg)、SVN、Darcs
- 如果没有 VCS，文件会被移动，但 VCS 不会记录这一变更

### 7.2 offset 参数的正确使用

- 使用 `worder.Worder` 或 AST 分析来获取准确的 offset
- 不要随意估计 offset 值，否则可能重命名错误的元素

### 7.3 局部变量重命名

如果重命名局部变量，rope 会自动限制只在该文件内进行搜索：

```python
# rename.py 第 105-106 行
if _is_local(self.old_pyname):
    resources = [self.resource]
```

### 7.4 方法层次结构重命名

当重命名类的方法时，可以使用 `in_hierarchy=True` 来重命名所有相关方法：

```python
changes = renamer.get_changes("new_method_name", in_hierarchy=True)
```

### 7.5 文档中的名称重命名

使用 `docs=True` 可以同时重命名文档字符串和注释中的名称：

```python
changes = renamer.get_changes("new_name", docs=True)
```

### 7.6 批量文件限制

可以使用 `resources` 参数限制要搜索的文件范围：

```python
# 只在特定文件中搜索
specific_files = [project.get_resource("file1.py"), project.get_resource("file2.py")]
changes = renamer.get_changes("new_name", resources=specific_files)
```

## 8. 相关类和方法

- `rope.refactor.rename.ChangeOccurrences`: 在指定作用域内替换名称 occurrences（不执行实际重命名）
- `rope.base.project.Project`: rope 项目主类
- `rope.base.resources.File` / `rope.base.resources.Folder`: 资源类
- `rope.base.fscommands`: 版本控制系统接口
