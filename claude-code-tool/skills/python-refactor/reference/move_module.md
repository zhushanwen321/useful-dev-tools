# MoveModule API 文档

## 基本信息

- **API 完整路径**: `rope.refactor.move.MoveModule`
- **类说明**: 用于将 Python 模块文件移动到新位置的重构工具类
- **源码位置**: `/Users/zhushanwen/GitApp/rope/rope/refactor/move.py`

## 构造函数

```python
MoveModule(project, resource)
```

### 参数说明

| 参数 | 类型 | 说明 |
|------|------|------|
| `project` | `Project` | rope 项目对象 |
| `resource` | `Resource` | 要移动的模块资源对象（可以是 `.py` 文件或包目录） |

### 构造函数的特殊处理

- 如果传入的是 `__init__.py` 文件，构造函数会自动将其父目录视为要移动的包
- 如果传入的是不含 `__init__.py` 的目录，会抛出 `RefactoringError`

## 常用方法

### get_changes()

```python
def get_changes(
    self,
    dest: resources.Resource,
    resources: Optional[List[resources.File]] = None,
    task_handle=taskhandle.DEFAULT_TASK_HANDLE,
) -> ChangeSet
```

生成移动模块所需的所有变更。

**参数说明**:

| 参数 | 类型 | 说明 |
|------|------|------|
| `dest` | `Resource` | 目标目录的资源对象（必须是包目录，即包含 `__init__.py`） |
| `resources` | `Optional[List[File]]` | 要检查和更新的文件列表。默认为项目所有 Python 文件 |
| `task_handle` | `TaskHandle` | 任务进度处理器 |

**返回**: `ChangeSet` 对象，包含所有需要执行的变更

**异常**:
- `RefactoringError`: 如果目标不是文件夹或不存在

### get_destination()

MoveModule 类本身没有此方法，但可以通过以下方式获取目标路径：

```python
# 手动计算目标模块名称
def get_destination_path(mover, dest_folder):
    source = mover.source
    if source.is_folder():
        old_name = source.name
    else:
        old_name = source.name[:-3]  # 移除 .py

    # 获取目标模块的完整路径
    dest_modname = dest_folder.path.lstrip('/')  # 移除前导斜杠
    return f"{dest_modname}/{old_name}"
```

### check_origin()

MoveModule 没有内置的 `check_origin()` 方法，但可以通过检查源模块是否存在来验证：

```python
def check_origin(mover):
    return mover.source.exists()
```

### validate_dest()

MoveModule 没有内置的 `validate_dest()` 方法，但 `get_changes()` 会自动验证目标：

```python
def validate_dest(project, dest_folder):
    """验证目标目录是否有效"""
    if dest_folder is None:
        return False, "目标目录不存在"
    if not dest_folder.is_folder():
        return False, "目标不是目录"
    # 检查是否是包（包含 __init__.py）
    if not dest_folder.has_child("__init__.py"):
        return False, "目标目录不是有效的 Python 包（缺少 __init__.py）"
    return True, "有效"
```

## 使用场景

### 适用场景

1. **移动模块文件到不同目录**: 将一个独立的 `.py` 文件移动到新的包目录下
2. **移动整个包**: 将一个完整的包（含 `__init__.py`）移动到新位置
3. **重构项目结构**: 调整代码的物理组织结构

### 路径说明

- **源路径**: 使用 rope 项目的相对路径（相对于项目根目录）
- **目标路径**: 传入 `Resource` 对象（通常通过 `project.get_folder()` 获取）

### 使用示例

```python
from rope.base.project import Project
from rope.refactor.move import MoveModule

# 创建项目
project = Project("path/to/your/project")

# 获取要移动的模块
source_module = project.get_resource("path/to/module.py")

# 创建 MoveModule 对象
mover = MoveModule(project, source_module)

# 获取目标目录
destination_folder = project.get_folder("path/to/destination")

# 生成变更
changes = mover.get_changes(destination_folder)

# 执行变更
project.do(changes)

# 关闭项目
project.close()
```

## 重要限制

### 1. 只能移动位置，不能改变文件名

`MoveModule` 只能将文件/包移动到新位置，**不能**同时重命名。

```python
# 只能这样
source = project.get_resource("old_name.py")
mover = MoveModule(project, source)
changes = mover.get_changes(destination_folder)
# 结果：old_name.py 被移动到 destination/old_name.py

# 不能这样（会报错或行为异常）
# MoveModule 不支持目标文件名的参数
```

### 2. 不更新不匹配的导入路径

如果某些文件中的导入语句指向的路径与实际模块位置不匹配（"幽灵导入"），MoveModule 不会更新这些导入。

**示例**:

```python
# 实际文件位置: calc/atr.py
# 但某文件写的是: from indicator.technical.atr import xxx  # 错误的路径

# 移动 calc/atr.py 到 calc/util/atr.py 后
# 上面的导入语句不会被更新，仍然指向不存在的路径
```

### 3. 不更新相对导入

MoveModule 主要更新绝对导入路径，但对相对导入的处理有限：

```python
# 移动前
# file.py
from base_providers import SomeClass  # 相对导入

# 移动后
# 新位置/file.py
from base_providers import SomeClass  # 不会自动更新！
# 运行时报错: ModuleNotFoundError: No module named 'base_providers'
```

### 4. 移动 __init__.py 可能导致嵌套目录问题

当移动 `__init__.py` 或包目录时，rope 会将整个包作为整体移动：

```
假设要移动: collection/__init__.py 到 supporting/collection/

预期结果:
supporting/collection/
  └── __init__.py

实际结果（如果 supporting/collection 已存在）:
supporting/collection/
  └── collection/          # 嵌套的包！
      └── __init__.py
```

### 5. 跨层级移动可能生成错误的导入路径

从父目录的子目录移动到兄弟目录的子目录时，rope 可能生成错误的导入：

```python
# 移动: api/constant/constants.py -> api/shared/constant/constants.py
# rope 可能生成错误的导入:
from constant.constants import APP_VERSION  # 错误！

# 正确的应该是:
from app.api.shared.constant.constants import APP_VERSION
```

## 代码示例

### 完整使用示例

```python
import os
from rope.base.project import Project
from rope.refactor.move import MoveModule

# 1. 创建 rope 项目
project = Project("/path/to/project")

# 2. 定义移动操作
def move_module(project, source_path, dest_folder_path):
    """移动模块到目标目录"""

    # 获取源模块
    source = project.get_resource(source_path)
    if source is None:
        raise ValueError(f"源模块不存在: {source_path}")

    # 获取目标目录
    dest_folder = project.get_folder(dest_folder_path)
    if dest_folder is None:
        raise ValueError(f"目标目录不存在: {dest_folder_path}")

    # 验证目标目录是有效的包
    if not dest_folder.has_child("__init__.py"):
        raise ValueError(f"目标目录不是有效的 Python 包: {dest_folder_path}")

    # 创建 MoveModule
    mover = MoveModule(project, source)

    # 生成变更
    changes = mover.get_changes(dest_folder)

    # 打印变更预览
    print("将要执行的变更:")
    for change in changes.changes:
        print(f"  {change.new_contents}")

    # 执行变更
    project.do(changes)

    return changes

# 3. 执行移动
try:
    changes = move_module(
        project,
        "app/module_a.py",        # 源模块（相对于项目根目录）
        "app/new_location"        # 目标目录
    )
    print("模块移动成功！")
finally:
    project.close()
```

### 使用 resources 参数优化性能

默认情况下，MoveModule 会检查项目中所有的 Python 文件。如果项目很大，这会很慢。可以使用 `resources` 参数限制检查范围：

```python
from rope.base.project import Project
from rope.refactor.move import MoveModule
import os

project = Project("/path/to/project")

source = project.get_resource("app/utils/helper.py")
destination = project.get_folder("app/core/helpers")

# 只检查可能受影响的文件
# 策略1: 只检查源模块的导入者
def get_importers(project, module_name):
    """获取导入特定模块的所有文件"""
    importers = []
    for resource in project.get_python_files():
        try:
            content = resource.read()
            if f"from {module_name}" in content or f"import {module_name}" in content:
                importers.append(resource)
        except:
            pass
    return importers

module_name = "app.utils.helper"
affected_files = get_importers(project, module_name)

# 执行移动，限制检查范围
mover = MoveModule(project, source)
changes = mover.get_changes(destination, resources=affected_files)

project.do(changes)
project.close()
```

### 预览变更而不执行

```python
project = Project("/path/to/project")

source = project.get_resource("module.py")
destination = project.get_folder("new_folder")

mover = MoveModule(project, source)
changes = mover.get_changes(destination)

# 打印所有变更
for change in changes.changes:
    resource = change.resource
    print(f"文件: {resource.path}")
    print(f"内容变更:")
    print(change.new_contents[:500])  # 打印前 500 字符
    print("-" * 40)

# 不执行，直接关闭项目
project.close()
```

## 常见错误

### 1. 目标目录不存在

```python
# 错误示例
source = project.get_resource("module.py")
destination = project.get_folder("non_existent_folder")  # None

mover = MoveModule(project, source)
changes = mover.get_changes(destination)  # 抛出 RefactoringError
```

**解决方案**: 确保目标目录存在

```python
destination = project.get_folder("path/to/dest")
if destination is None or not destination.exists():
    os.makedirs("path/to/dest", exist_ok=True)
    # 创建 __init__.py 使其成为包
    with open("path/to/dest/__init__.py", "w") as f:
        pass
    destination = project.get_folder("path/to/dest")
```

### 2. 目标不是包目录

```python
# 错误: 目标目录没有 __init__.py
changes = mover.get_changes(destination)
# RefactoringError: Move destination for modules should be packages.
```

**解决方案**: 确保目标目录包含 `__init__.py`

### 3. 导入未更新

移动后代码出现 `ModuleNotFoundError`，这是最常见的问题。

**原因**:
- 存在不匹配的导入路径
- 使用了相对导入
- 跨层级移动导致路径计算错误

**解决方案**:

```python
# 方案1: 移动前修复所有导入
# 使用 grep 找出所有错误的导入，手动修复后再移动

# 方案2: 移动后批量修复
import re

def fix_imports_in_file(file_path, fixes):
    """批量修复文件中的导入"""
    with open(file_path, 'r') as f:
        content = f.read()

    for pattern, replacement in fixes:
        content = re.sub(pattern, replacement, content)

    with open(file_path, 'w') as f:
        f.write(content)

# 使用示例
fixes = [
    (r'from old_path\.module import', 'from new_path.module import'),
    (r'from base_providers import', 'from full.path.base_providers import'),
]

for root, dirs, files in os.walk("path/to/project"):
    for file in files:
        if file.endswith(".py"):
            fix_imports_in_file(os.path.join(root, file), fixes)
```

### 4. 相对导入问题

```python
# 移动前: app/a/module.py 使用了相对导入
from .sibling import something

# 移动后: 相对导入失效
```

**解决方案**: 在移动前将相对导入改为绝对导入

```python
def convert_relative_to_absolute(project, resource):
    """将相对导入转换为绝对导入"""
    content = resource.read()

    # 简单的相对导入转换（可能需要更复杂的逻辑）
    # from . import xxx -> from package.xxx import xxx
    # from .sibling import xxx -> from package.sibling import xxx

    # 这需要更复杂的解析，建议使用专门的工具
    return content
```

## 最佳实践

### 1. 先修复导入再移动

在执行 MoveModule 之前，确保所有导入语句是正确的：

```python
# 移动前的检查清单
def validate_imports_before_move(project, source_path):
    """验证源模块的所有导入是否正确"""
    source = project.get_resource(source_path)
    pymodule = project.get_pymodule(source)

    # 使用 rope 的导入分析功能检查导入
    from rope.refactor.importutils import ImportTools

    import_tools = ImportTools(project)
    imports = import_tools.get_imports(pymodule)

    for stmt in imports:
        print(f"导入: {stmt.import_info}")

    return imports
```

### 2. 使用 resources 参数优化性能

对于大型项目，不要让 MoveModule 检查所有文件：

```python
# 只检查源模块的直接导入者
def get_affected_files(project, module_path):
    """获取可能受移动影响的文件"""
    module_name = module_path.replace("/", ".").replace(".py", "")
    affected = []

    for resource in project.get_python_files():
        try:
            content = resource.read()
            if module_name in content:
                affected.append(resource)
        except:
            pass

    return affected

affected = get_affected_files(project, source_path)
changes = mover.get_changes(destination, resources=affected)
```

### 3. 预览变更后再执行

```python
# 总是先预览，再执行
changes = mover.get_changes(destination)

# 检查变更是否合理
if not changes.changes:
    print("警告: 没有生成任何变更")
elif len(changes.changes) > 100:
    print("警告: 变更数量较多，请确认")

# 确认后再执行
if confirm("确认执行这些变更?"):
    project.do(changes)
```

### 4. 备份和版本控制

```python
# 在执行重大移动前，使用 rope 的历史功能
project.history.undo()  # 可以撤销

# 或者先提交到 git
import subprocess

def git_commit_before_move(project_path, message):
    subprocess.run(["git", "add", "-A"], cwd=project_path, check=True)
    subprocess.run(["git", "commit", "-m", message], cwd=project_path, check=True)

# 移动前先提交
git_commit_before_move("/path/to/project", "Before move module")
```

### 5. 测试验证

移动后必须验证：

```python
def verify_move(project_path, source_path, dest_path):
    """验证移动是否成功"""
    import subprocess

    # 1. 检查文件是否在正确位置
    dest_file = os.path.join(project_path, dest_path, "module.py")
    if not os.path.exists(dest_file):
        print(f"错误: 目标文件不存在: {dest_file}")
        return False

    # 2. 尝试导入模块
    result = subprocess.run(
        ["python", "-c", f"import sys; sys.path.insert(0, '{project_path}'); from {dest_path.replace('/', '.')}.module import *"],
        capture_output=True,
        text=True
    )

    if result.returncode != 0:
        print(f"导入错误: {result.stderr}")
        return False

    # 3. 运行测试（如果有）
    # subprocess.run(["pytest"], cwd=project_path)

    return True
```

### 6. 避免移动 __init__.py

尽量只移动具体的模块文件，而不是包的 `__init__.py`：

```python
# 不推荐: 移动 __init__.py（会移动整个包）
source = project.get_resource("package/__init__.py")

# 推荐: 移动具体的模块文件
source = project.get_resource("package/module.py")

# 或者如果确实需要移动包，先手动处理
```

## 相关参考

- **rope 源码**: `/Users/zhushanwen/GitApp/rope/rope/refactor/move.py`
- **负向用例**: `/Users/zhushanwen/.claude/skills/python-refactor/negative-case/raw-case/`
  - `MoveModule不更新不匹配的导入路径/` - 导入路径不匹配的问题
  - `MoveModule-creates-nested-folders/` - 移动 __init__.py 导致嵌套目录
  - `MoveModule-not-update-relative-imports/` - 相对导入未更新问题
  - `MoveModule跨层级移动生成错误导入路径/` - 跨层级移动路径错误问题
