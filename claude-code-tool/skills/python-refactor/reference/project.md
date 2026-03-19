# rope.base.project.Project API 文档

## 1. 基本信息

### API 完整路径
`rope.base.project.Project`

### 类说明
`Project` 是 rope 的核心类，作为项目管理器，负责加载和分析 Python 代码。它是进行代码重构、智能提示和分析的前提条件。

Project 本质上是一个文件夹，包含需要分析或重构的 Python 代码。Rope 会递归扫描项目中的 Python 文件和包，建立代码的抽象语法树（AST）以支持各种重构操作。

### 相关类
- `_Project`: Project 的基类，提供核心功能
- `NoProject`: 无项目模式，用于处理项目外的模块
- `get_no_project()`: 获取全局 NoProject 实例的函数

---

## 2. 构造函数参数

```python
class Project(_Project):
    def __init__(
        self,
        projectroot,           # 项目根目录路径
        fscommands=None,       # 文件系统操作实现
        ropefolder=".ropeproject",  # Rope 配置文件夹名称
        **prefs               # 项目偏好设置
    ):
```

### 参数详细说明

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `projectroot` | `str` | 必填 | 项目根目录的绝对或相对路径。如果目录不存在，rope 会自动创建该目录 |
| `fscommands` | `FileSystemCommands` | `None` | 实现文件系统操作的类，用于支持版本控制系统。默认为 `rope.base.fscommands.create_fscommands()` |
| `ropefolder` | `str` | `".ropeproject"` | Rope 存储项目配置和数据的文件夹名称。设为 `None` 则不创建此类文件夹 |
| `**prefs` | `dict` | `{}` | 项目偏好设置，会覆盖配置文件中的设置。常用选项包括 `ignored_resources`、`source_folders` 等 |

### 路径说明
- `projectroot` 可以是相对路径或绝对路径
- 建议使用绝对路径以避免歧义
- Rope 会自动将路径转换为绝对路径（使用 `os.path.realpath`）

---

## 3. 常用属性

### address
项目根目录的绝对路径字符串。

```python
project = Project("/path/to/project")
print(project.address)  # '/path/to/project'
```

### root
项目根目录对应的 `Folder` 对象。

```python
root_folder = project.root
print(root_folder.path)  # '' (空字符串，表示项目根)
```

### history
项目的历史记录管理器，是一个 `History` 对象。用于撤销/重做操作。

### pycore
项目的 Python 核心模块管理器，提供 Python 相关的分析功能。

### ropefolder
返回 `.ropeproject` 文件夹的 `Folder` 对象，如果 `ropefolder` 参数设为 `None`，则返回 `None`。

---

## 4. 常用方法

### get_resource(resource_name)

获取项目中指定路径的资源。

**参数：**
- `resource_name` (`str`): 资源路径，相对于项目根目录。使用正斜杠 `/` 分隔。

**返回：**
- `File` 或 `Folder` 对象

**异常：**
- `ResourceNotFoundError`: 资源不存在时抛出

**示例：**
```python
# 获取项目根目录下的 src/main.py
resource = project.get_resource("src/main.py")

# 获取项目根目录本身
root = project.get_resource("")
```

### get_file(path)

获取指定路径的文件资源（文件可以不存在）。

**参数：**
- `path` (`str`): 文件路径，相对于项目根目录

**返回：**
- `File` 对象

**示例：**
```python
# 获取可能不存在的文件
new_file = project.get_file("src/new_module.py")
```

### get_folder(path)

获取指定路径的文件夹资源（文件夹可以不存在）。

**参数：**
- `path` (`str`): 文件夹路径，相对于项目根目录

**返回：**
- `Folder` 对象

### get_files()

返回项目中所有非忽略的文件资源集合。

**返回：**
- `set[File]`: 包含所有文件的集合

**示例：**
```python
all_files = project.get_files()
for file in all_files:
    print(file.path)
```

### get_python_files()

返回项目中所有 Python 文件。

**返回：**
- `list[File]`: Python 文件列表

### get_pymodule(resource, force_errors=False)

获取资源的 Python 模块对象。

**参数：**
- `resource` (`Resource`): 文件资源
- `force_errors` (`bool`): 是否在有语法错误时抛出异常，默认 `False`

**返回：**
- `PyModule` 对象

**示例：**
```python
resource = project.get_resource("src/main.py")
pymodule = project.get_pymodule(resource)
```

### get_module(name, folder=None)

获取指定名称的 Python 模块。

**参数：**
- `name` (`str`): 模块名（可以是点分隔的包路径）
- `folder` (`Folder`): 可选的搜索起始文件夹

**返回：**
- `PyObject` 对象

**异常：**
- `ModuleNotFoundError`: 模块未找到

### validate(folder=None)

验证文件和文件夹的缓存信息。当外部程序修改了项目文件时，需要调用此方法使 rope 重新加载。

**参数：**
- `folder` (`Folder`): 要验证的文件夹，默认为项目根目录

**示例：**
```python
# 验证整个项目
project.validate()

# 验证特定文件夹
folder = project.get_resource("src")
project.validate(folder)
```

### close()

关闭项目，保存数据文件。**务必在完成项目操作后调用此方法**，否则可能导致数据丢失或不一致状态。

**示例：**
```python
project.close()
```

### do(changes, task_handle=DEFAULT_TASK_HANDLE)

执行重构操作产生的变更。

**参数：**
- `changes` (`Change` 或 `ChangeSet`): 重构操作返回的变更对象
- `task_handle` (`TaskHandle`): 可选的任务处理器，用于监控进度或中断操作

**示例：**
```python
from rope.refactor.rename import Rename

renamer = Rename(project, resource, offset)
changes = renamer.get_changes('new_name')
project.do(changes)
```

### set(key, value)

设置项目偏好选项。

**参数：**
- `key` (`str`): 偏好设置名称
- `value`: 偏好设置值

**示例：**
```python
project.set('ignored_resources', ['*.pyc', '__pycache__'])
```

### get_source_folders()

返回项目的源代码文件夹列表。

**返回：**
- `list[Folder]`: 源代码文件夹列表

### get_python_path_folders()

返回项目的 Python path 文件夹列表。

**返回：**
- `list[Folder]`: Python path 文件夹列表

---

## 5. 历史记录操作 (History)

通过 `project.history` 属性访问，用于撤销和重做重构操作。

### history.undo(change=None, drop=False, task_handle=DEFAULT_TASK_HANDLE)

撤销上一次或指定的变更。

**参数：**
- `change` (`Change`): 可选，指定要撤销的变更（默认为上一个）
- `drop` (`bool`): 是否丢弃该变更（不加入重做列表）
- `task_handle` (`TaskHandle`): 可选的任务处理器

**返回：**
- `list[Change]`: 已撤销的变更列表

**异常：**
- `HistoryError`: 撤销列表为空时抛出

### history.redo(change=None, task_handle=DEFAULT_TASK_HANDLE)

重做上一次或指定的已撤销变更。

**参数：**
- `change` (`Change`): 可选，指定要重做的变更
- `task_handle` (`TaskHandle`): 可选的任务处理器

**返回：**
- `list[Change]`: 已重做的变更列表

**异常：**
- `HistoryError`: 重做列表为空时抛出

### history.undo_list

当前可撤销的变更列表。

### history.redo_list

当前可重做的变更列表。

### history.tobe_undone

下一个将被撤销的变更（如果存在）。

### history.tobe_redone

下一个将被重做的变更（如果存在）。

---

## 6. 使用场景

### 6.1 什么时候使用 Project

- 进行代码重构（重命名、移动、提取变量/函数等）
- 获取代码补全建议
- 查找符号的定义和引用
- 代码静态分析
- 代码结构理解

### 6.2 如何初始化项目

```python
from rope.base.project import Project

# 基本初始化
project = Project("/path/to/your/project")

# 使用相对路径（会转换为绝对路径）
project = Project("./myproject")

# 禁用 .ropeproject 文件夹
project = Project("/path/to/project", ropefolder=None)

# 自定义配置
project = Project(
    "/path/to/project",
    ignored_resources=["*.pyc", "build/", "dist/"],
    source_folders=["src"]
)
```

### 6.3 路径是相对还是绝对

- Rope 内部使用相对路径（相对于项目根目录）进行资源定位
- 构造函数接受的路径可以是相对的或绝对的，Rope 会自动转换为绝对路径
- `Resource.path` 属性返回相对路径
- `Resource.real_path` 属性返回文件系统上的绝对路径

```python
project = Project("/path/to/project")
resource = project.get_resource("src/main.py")

print(resource.path)      # 'src/main.py' (相对路径)
print(resource.real_path)  # '/path/to/project/src/main.py' (绝对路径)
```

---

## 7. 代码示例

### 7.1 基本项目操作

```python
from rope.base.project import Project
from rope.refactor.rename import Rename
import rope.base.libutils as libutils

# 创建项目
project = Project("/path/to/myproject")

try:
    # 获取文件资源
    resource = libutils.path_to_resource(project, "src/main.py")

    # 执行重命名重构
    renamer = Rename(project, resource, offset=100)  # offset 为光标位置
    changes = renamer.get_changes('new_function_name')

    # 预览变更
    print(changes.get_description())

    # 执行变更
    project.do(changes)

    # 撤销操作
    project.history.undo()

    # 重做操作
    project.history.redo()

finally:
    # 确保关闭项目
    project.close()
```

### 7.2 使用 with 语句（推荐）

```python
from rope.base.project import Project
from rope.refactor.extract import ExtractVariable

with Project("/path/to/project") as project:
    resource = project.get_resource("src/main.py")
    pymodule = project.get_pymodule(resource)

    # 执行提取变量重构
    extractor = ExtractVariable(project, resource, start, end)
    changes = extractor.get_changes('new_variable')

    project.do(changes)

# 项目自动关闭
```

注意：Project 类没有实现 `__enter__` 和 `__exit__`，上面的写法需要自行处理。更推荐使用 try/finally：

```python
from rope.base.project import Project

project = Project("/path/to/project")
try:
    # 项目操作
    pass
finally:
    project.close()
```

### 7.3 完整的重构示例

```python
from rope.base.project import Project
from rope.base import libutils
from rope.refactor.rename import Rename
from rope.refactor.move import create_move

# 初始化项目
project = Project(
    "/path/to/project",
    ignored_resources=["*.pyc", ".git/", "venv/"]
)

try:
    # 验证项目缓存
    project.validate()

    # 获取要重构的文件
    resource = libutils.path_to_resource(project, "src/module.py")

    # 示例1: 重命名
    renamer = Rename(project, resource, offset=50)
    changes = renamer.get_changes("new_name")
    project.do(changes)

    # 示例2: 移动模块
    dest_folder = project.get_resource("src/new_package")
    mover = create_move(project, resource, offset=0)
    changes = mover.get_changes(dest_folder)
    project.do(changes)

    # 查看历史
    print(f"可撤销操作数: {len(project.history.undo_list)}")
    print(f"可重做操作数: {len(project.history.redo_list)}")

finally:
    project.close()
```

### 7.4 代码分析示例

```python
from rope.base.project import Project
from rope.contrib import codeassist

project = Project("/path/to/project")

try:
    resource = project.get_resource("src/main.py")
    source = resource.read()

    # 获取代码补全建议
    offset = 100  # 光标位置
    proposals = codeassist.code_assist(project, source, offset)
    proposals = codeassist.sorted_proposals(proposals)

    for proposal in proposals:
        print(proposal.name, proposal.kind)

finally:
    project.close()
```

---

## 8. 常见错误

### 8.1 ResourceNotFoundError

资源未找到错误。

**原因：**
- 指定的资源路径不存在
- 路径拼写错误
- 路径分隔符使用错误（应使用 `/`）

**解决方案：**
```python
from rope.base.exceptions import ResourceNotFoundError

try:
    resource = project.get_resource("src/main.py")
except ResourceNotFoundError:
    # 检查路径是否正确
    print("资源不存在，请检查路径")
```

### 8.2 ModuleNotFoundError

模块未找到错误。

**原因：**
- 指定的模块不存在
- 模块不在项目的源代码文件夹中

**解决方案：**
```python
from rope.base.exceptions import ModuleNotFoundError

try:
    pymodule = project.get_module("nonexistent_module")
except ModuleNotFoundError as e:
    print(f"模块未找到: {e}")
```

### 8.3 HistoryError

历史操作错误。

**原因：**
- 撤销/重做列表为空
- 试图撤销/重做不存在的操作

**解决方案：**
```python
from rope.base.exceptions import HistoryError

try:
    project.history.undo()
except HistoryError as e:
    print(f"历史操作错误: {e}")
```

### 8.4 RefactoringError

重构执行错误。

**原因：**
- 重构操作的前提条件不满足
- 代码结构不符合重构要求

**解决方案：**
```python
from rope.base.exceptions import RefactoringError

try:
    renamer = Rename(project, resource, offset)
    changes = renamer.get_changes("new_name")
except RefactoringError as e:
    print(f"重构错误: {e}")
```

### 8.5 路径错误

**常见问题：**
- 使用反斜杠 `\` 而非正斜杠 `/`
- 相对路径理解错误

**正确做法：**
```python
# 错误
resource = project.get_resource("src\\main.py")

# 正确
resource = project.get_resource("src/main.py")

# 使用绝对路径更可靠
resource = project.get_resource("/absolute/path/to/file.py")
```

---

## 9. 最佳实践

### 9.1 始终关闭项目

**重要：** 使用完项目后务必调用 `close()` 方法，以确保数据正确保存。

```python
# 不推荐
project = Project("/path/to/project")
# ... 操作 ...
# 可能忘记关闭

# 推荐
project = Project("/path/to/project")
try:
    # ... 操作 ...
finally:
    project.close()

# 或者
project = Project("/path/to/project")
# ... 操作 ...
project.close()  # 确保调用
```

### 9.2 定期验证项目

当项目文件被外部程序修改时，需要调用 `validate()` 方法：

```python
# 在每次执行重构前验证
project.validate()

# 或者只验证特定文件夹
project.validate(project.get_resource("src"))
```

### 9.3 合理设置忽略模式

对于不需要 rope 分析的文件和文件夹，设置忽略模式可以提高性能：

```python
project = Project(
    "/path/to/project",
    ignored_resources=[
        "*.pyc",           # 编译的 Python 文件
        "__pycache__/",    # Python 缓存目录
        ".git/",           # Git 目录
        "venv/",           # 虚拟环境
        "build/",          # 构建目录
        "dist/",           # 发行目录
    ]
)
```

### 9.4 使用 libutils.path_to_resource

推荐使用 `rope.base.libutils.path_to_resource()` 而不是直接使用 `project.get_resource()`，因为它更加灵活：

```python
from rope.base import libutils

# 获取已存在的资源
resource = libutils.path_to_resource(project, "src/main.py")

# 创建不存在的文件
new_file = libutils.path_to_resource(project, "src/new_module.py", type="file")

# 创建不存在的文件夹
new_folder = libutils.path_to_resource(project, "src/new_pkg", type="folder")
```

### 9.5 使用任务处理器监控长时间操作

对于大型项目的重构，可以使用任务处理器：

```python
from rope.base import taskhandle

handle = taskhandle.TaskHandle("My Refactoring")

def progressObserver():
    jobset = handle.current_jobsets()
    if jobset:
        print(f"{jobset.get_name()}: {jobset.get_percent_done()}%")

handle.add_observer(progressObserver)

# 执行重构
project.do(changes, task_handle=handle)

# 或者中断任务
handle.stop()
```

---

## 10. 相关模块和类

| 模块/类 | 说明 |
|---------|------|
| `rope.base.project.Project` | 主项目类 |
| `rope.base.project._Project` | 项目基类 |
| `rope.base.project.NoProject` | 无项目模式 |
| `rope.base.history.History` | 历史记录管理 |
| `rope.base.resources.Resource` | 资源基类 |
| `rope.base.resources.File` | 文件资源 |
| `rope.base.resources.Folder` | 文件夹资源 |
| `rope.base.libutils` | 工具函数模块 |
| `rope.base.pycore.PyCore` | Python 核心模块 |
| `rope.base.fscommands` | 文件系统命令（支持 VCS） |
| `rope.refactor` | 重构模块 |
| `rope.contrib.codeassist` | 代码补全 |
| `rope.contrib.findit` | 查找引用 |

---

## 参考资料

- [Rope 官方文档](https://rope.readthedocs.io/)
- [Rope GitHub 仓库](https://github.com/python-rope/rope)
- 源码位置: `/Users/zhushanwen/GitApp/rope/rope/base/project.py`
