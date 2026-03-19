# 高频使用函数详细指南

本文档详细说明 stock-data-crawler 项目重构脚本中高频使用的 rope 函数的使用方法、常见陷阱和最佳实践。

## 目录

1. [Project 基础设置](#1-project-基础设置)
2. [path_to_resource 路径转换](#2-path_to_resource-路径转换)
3. [MoveModule 移动模块](#3-movemodule-移动模块)
4. [Rename 重命名](#4-rename-重命名)
5. [get_changes 和 project.do](#5-get_changes-和-projectdo)
6. [project.get_resource 获取资源](#6-projectget_resource-获取资源)
7. [性能优化：resources 参数](#7-性能优化resources-参数)

---

## 1. Project 基础设置

### 基本用法

```python
import sys
from pathlib import Path

# 添加本地修复版 rope（修复了 get_source_folders 缓存问题）
ROPE_LOCAL = "/Users/zhushanwen/GitApp/rope"
sys.path.insert(0, ROPE_LOCAL)

from rope.base.project import Project

# 创建项目 - 传入项目根目录的绝对路径
project = Project('/path/to/project')

# ... 执行重构操作 ...

# 重要：操作完成后必须关闭项目
project.close()
```

### 关键点

- **路径必须是绝对路径**：不能使用相对路径
- **必须调用 `project.close()`**：否则可能丢失未保存的变更
- **项目目录需要有 `__init__.py`**：否则可能无法正确识别为 Python 包

### 常见错误

```
ValueError: path is on mount '/', start_on_mount is True
```
**原因**：传入的路径不正确，确保是绝对路径。

---

## 2. path_to_resource 路径转换

### 基本用法

```python
from rope.base.libutils import path_to_resource

# 方式 1：使用 path_to_resource（推荐）
resource = path_to_resource(project, 'path/to/file.py')

# 检查资源是否存在
if resource is None or not resource.exists:
    print("文件不存在")
```

### 路径格式

| 传入格式 | 说明 | 示例 |
|---------|------|------|
| 相对路径 | 相对于项目根目录 | `app/domain/user.py` |
| 不带前缀 | 不需要 `./` | `app/domain/user.py` |
| 带 `.py` 后缀 | 必须是完整文件名 | `app/domain/user.py` |

### 常见错误

```python
# 错误：使用了绝对路径
resource = path_to_resource(project, '/Users/xxx/project/app/domain/user.py')

# 错误：路径不存在
resource = path_to_resource(project, 'app/nonexistent/file.py')
# resource 为 None

# 错误：使用了相对路径
resource = path_to_resource(project, './app/domain/user.py')
```

### 最佳实践

```python
# 推荐：先检查再使用
resource = path_to_resource(project, 'app/domain/user.py')
if resource is None or not resource.exists:
    print(f"  [跳过] 源文件不存在: app/domain/user.py")
    return False
```

---

## 3. MoveModule 移动模块

### 基本用法

```python
from rope.refactor.move import MoveModule

# Step 1: 获取源资源
src_resource = path_to_resource(project, 'app/domain/old_module.py')

# Step 2: 获取目标文件夹资源
dst_folder = path_to_resource(project, 'app/application')

# Step 3: 创建移动器并获取变更
mover = MoveModule(project, src_resource)
change = mover.get_changes(dst_folder)

# Step 4: 执行变更
project.do(change)
```

### 关键限制

| 限制 | 说明 | 解决方案 |
|-----|------|---------|
| **不能改变文件名** | MoveModule 只能移动位置 | 先用 Rename 再用 MoveModule |
| **需要 VCS** | 重命名模块文件需要版本控制 | 确保项目在 git/hg 下 |
| **目标必须是文件夹** | 目标不能是文件路径 | 传入目标目录，不是文件 |

### 同时移动和重命名

如果需要同时改变文件名和位置，必须分两步：

```python
src = 'app/domain/old_name.py'
dst = 'app/application/new_name.py'

src_path = Path(src)
dst_path = Path(dst)

# Step 1: 重命名
if src_path.stem != dst_path.stem:
    renamer = Rename(project, src_resource, offset=None)
    change = renamer.get_changes(dst_path.stem)
    project.do(change)

    # 更新源路径为重命名后的路径
    src_resource = path_to_resource(project,
        str(src_path.parent / f"{dst_path.stem}.py"))

# Step 2: 移动
if src_path.parent != dst_path.parent:
    dst_folder = path_to_resource(project, str(dst_path.parent))
    mover = MoveModule(project, src_resource)
    change = mover.get_changes(dst_folder)
    project.do(change)
```

### 常见错误

```python
# 错误 1：目标传了文件路径而不是目录
change = mover.get_changes('app/application/module.py')  # 错！
change = mover.get_changes('app/application')  # 对！

# 错误 2：没有先检查文件是否存在
src_resource = path_to_resource(project, 'app/nonexistent.py')
mover = MoveModule(project, src_resource)  # 可能报错

# 正确：先检查
if src_resource is None or not src_resource.exists:
    print("文件不存在")
    return
```

---

## 4. Rename 重命名

### 重命名模块文件

```python
from rope.refactor.rename import Rename

# 获取资源
resource = path_to_resource(project, 'app/domain/old_name.py')

# offset=None 表示重命名模块文件
renamer = Rename(project, resource, offset=None)
change = renamer.get_changes('new_name')

# 执行
project.do(change)
```

### 重命名代码符号（类、函数、变量）

```python
# 需要知道符号在文件中的偏移量
# 可以使用 find_definition_offset 或手动定位

# 假设要重命名 MyClass
resource = path_to_resource(project, 'app/domain/module.py')

# 方法 1：使用 rope.base.libutils.get_doc
# 需要知道 offset（字符偏移量）

# 方法 2：使用 rope.pynames
from rope.base import libutils
pyname = project.get_pyname('app/domain/module.py', offset)
# 然后获取定义位置...

# 更实用的方法：使用工具函数
# 见下方 "工具函数" 章节
```

### 关键点

- **offset=None**：重命名模块文件
- **offset=数字**：重命名代码符号（类、函数等）
- **需要 VCS**：重命名模块文件必须在版本控制下

---

## 5. get_changes 和 project.do

### 基本模式

```python
# 获取变更对象（不执行）
change = renamer.get_changes('new_name')
# 或
change = mover.get_changes(destination)

# 执行变更
project.do(change)

# 注意：执行后 change 对象就失效了
# 如需再次执行，需要重新获取
```

### get_changes 的常见参数

| 参数 | 类型 | 说明 |
|-----|------|------|
| `destination` | Resource | 移动目标文件夹（MoveModule 必需） |
| `new_name` | str | 新名称（Rename 必需） |
| `resources` | list | 限制扫描的资源列表（可选，用于优化） |
| `similar` | bool | 是否替换相似代码（ExtractMethod 用） |

### 常见错误

```python
# 错误 1：get_changes 传错参数
mover = MoveModule(project, src_resource)
change = mover.get_changes()  # 错！必须传 destination

# 错误 2：忘记执行
change = mover.get_changes(dst_folder)
# 忘记 project.do(change) - 变更不会生效！

# 错误 3：执行后再次使用同一 change
project.do(change)
project.do(change)  # 错！change 已失效
```

---

## 6. project.get_resource 获取资源

### 基本用法

```python
# 获取文件资源
resource = project.get_resource('path/to/file.py')

# 获取文件夹资源
folder = project.get_resource('path/to/folder')

# 检查存在性
if resource is None:
    print("不存在")
```

### 与 path_to_resource 的区别

| 特性 | `project.get_resource()` | `path_to_resource()` |
|-----|------------------------|---------------------|
| 路径格式 | 相对于项目根 | 相对于项目根 |
| 返回类型 | Resource 或 None | Resource 或 None |
| 性能 | 稍慢 | 稍快 |
| 推荐 | 一般用途 | 推荐使用 |

### 常见用法对比

```python
# 两种方式都可以

# 方式 1：get_resource
resource = project.get_resource('app/domain/module.py')

# 方式 2：path_to_resource（推荐）
resource = path_to_resource(project, 'app/domain/module.py')

# 方式 3：绝对路径（不推荐）
resource = project.get_resource('/full/path/to/project/app/domain/module.py')
# 注意：这种方式可能不工作，取决于 rope 版本
```

---

## 7. 性能优化：resources 参数

### 问题背景

对于大型项目（几千个 Python 文件），`get_changes()` 可能非常慢，因为它会扫描整个项目来查找引用。

### 解决方案

使用 `resources` 参数限制扫描范围：

```python
# Step 1: 收集需要扫描的资源
def get_python_files_in_folder(folder_resource):
    """递归获取文件夹中的所有 Python 文件资源"""
    python_files = []

    def _collect(resource):
        if resource.is_folder():
            for child in resource.get_children():
                _collect(child)
        elif resource.name.endswith('.py'):
            python_files.append(resource)

    _collect(folder_resource)
    return python_files

# Step 2: 限制扫描范围
app_folder = project.get_resource("backend/app")
tests_folder = project.get_resource("backend/tests")
scoped_resources = get_python_files_in_folder(app_folder)
scoped_resources.extend(get_python_files_in_folder(tests_folder))

# Step 3: 传入 get_changes
mover = MoveModule(project, source)
change = mover.get_changes(target, resources=scoped_resources)
```

### 性能提升

| 项目规模 | 无 resources 参数 | 有 resources 参数 |
|---------|-----------------|------------------|
| 100 个文件 | ~1s | ~0.5s |
| 1000 个文件 | ~30s | ~2s |
| 5000 个文件 | ~10min | ~10s |

### 何时使用

- ✅ 移动的模块影响范围明确且有限
- ✅ 项目文件数量超过 1000
- ❌ 移动的模块是核心基础模块（影响大量其他模块）
- ❌ 不确定影响范围时

---

## 工具函数

这些函数来自 `scripts/helpers.py`：

### find_offset

```python
from rope.base.libutils import path_to_resource
from rope.refactor import usecode

def find_offset(resource, pattern):
    """
    在文件中查找模式字符串的偏移量

    Args:
        resource: 文件资源
        pattern: 要查找的字符串

    Returns:
        int: 模式的起始偏移量，未找到返回 -1
    """
    source = resource.content
    offset = source.find(pattern)
    return offset
```

### find_definition_offset

```python
def find_definition_offset(resource, name, type='class'):
    """
    查找类或函数定义的偏移量

    Args:
        resource: 文件资源
        name: 类名或函数名
        type: 'class' 或 'function'

    Returns:
        int: 定义的起始偏移量，未找到返回 -1
    """
    source = resource.content()
    # 查找 class Name 或 def Name
    if type == 'class':
        pattern = f'class {name}'
    else:
        pattern = f'def {name}'

    offset = source.find(pattern)
    return offset
```

### get_region_offsets

```python
def get_region_offsets(resource, start_line, end_line):
    """
    获取行范围的字符偏移量

    Args:
        resource: 文件资源
        start_line: 起始行号（1-based）
        end_line: 结束行号（1-based）

    Returns:
        tuple: (start_offset, end_offset)
    """
    source = resource.content()
    lines = source.split('\n')

    start_offset = sum(len(lines[i]) + 1 for i in range(start_line - 1))
    end_offset = sum(len(lines[i]) + 1 for i in range(end_line))

    return start_offset, end_offset
```

---

## 完整示例

### 移动并重命名模块的完整流程

```python
import sys
from pathlib import Path

ROPE_LOCAL = "/Users/zhushanwen/GitApp/rope"
sys.path.insert(0, ROPE_LOCAL)

from rope.base.project import Project
from rope.base.libutils import path_to_resource
from rope.refactor.move import MoveModule
from rope.refactor.rename import Rename


def move_and_rename_module(project, src, dst, dry_run=False):
    """
    移动并重命名模块的完整实现

    Args:
        project: rope Project 对象
        src: 源路径（如 'app/domain/old_name.py'）
        dst: 目标路径（如 'app/application/new_name.py'）
        dry_run: 是否预览模式
    """
    # Step 1: 获取源资源
    src_resource = path_to_resource(project, src)
    if src_resource is None or not src_resource.exists:
        print(f"  [错误] 源文件不存在: {src}")
        return False

    src_path = Path(src)
    dst_path = Path(dst)

    old_name = src_path.stem
    new_name = dst_path.stem

    current_src = src

    # Step 2: 重命名（如果需要）
    if old_name != new_name:
        print(f"  步骤 1: 重命名 {old_name}.py -> {new_name}.py")

        if not dry_run:
            renamer = Rename(project, src_resource, offset=None)
            change = renamer.get_changes(new_name)
            project.do(change)

            # 更新当前源文件路径
            current_src = str(src_path.parent / f"{new_name}.py")
            src_resource = path_to_resource(project, current_src)
        else:
            print(f"    [DRY-RUN] 将重命名为: {new_name}")

    # Step 3: 移动（如果目录不同）
    src_dir = src_path.parent
    dst_dir = dst_path.parent

    if str(src_dir) != str(dst_dir):
        print(f"  步骤 2: 移动到 {dst_dir}")

        if not dry_run:
            dst_folder = path_to_resource(project, str(dst_dir))
            mover = MoveModule(project, src_resource)
            change = mover.get_changes(dst_folder)
            project.do(change)
        else:
            print(f"    [DRY-RUN] 将移动到: {dst}")

    return True


# 使用示例
if __name__ == "__main__":
    project = Project("/path/to/project")

    success = move_and_rename_module(
        project,
        "app/domain/old_module.py",
        "app/application/new_module.py",
        dry_run=False
    )

    project.close()
```

---

## 常见问题汇总

| 问题 | 原因 | 解决方案 |
|-----|------|---------|
| "not under version control" | 重命名模块文件但项目不在 VCS 下 | 确保项目在 git/hg 下 |
| ValueError: path is on mount | 传入的路径不是项目内的相对路径 | 使用相对于项目的路径 |
| 移动后导入未更新 | MoveModule 执行失败但没报错 | 检查返回值和输出 |
| get_changes 很慢 | 项目太大，扫描整个项目 | 使用 resources 参数限制范围 |
| 移动后文件名不对 | MoveModule 不能同时改名 | 先 Rename 再 MoveModule |
