# rope MultiProjectRefactoring API 详细使用文档

## 1. 基本信息

- **API 完整路径**: `rope.refactor.multiproject.MultiProjectRefactoring`
- **类说明**: 跨多个项目进行重构的代理类，用于在主项目和依赖项目之间同步执行重构操作
- **源码位置**: `/Users/zhushanwen/GitApp/rope/rope/refactor/multiproject.py`

```python
from rope.refactor import multiproject
```

## 2. 构造函数参数

```python
MultiProjectRefactoring(refactoring, projects, addpath=True)
```

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `refactoring` | `type` 或 `callable` | 必填 | 重构类（如 `Rename`、`Move`）或工厂函数（如 `create_move`） |
| `projects` | `list[Project]` | 必填 | 依赖项目列表（不包括主项目） |
| `addpath` | `bool` | `True` | 是否将主项目的源码文件夹添加到依赖项目的 Python 路径中 |

### 参数说明

- **`refactoring`**: 接受任何 rope 重构类的构造函数或工厂函数。例如 `rename.Rename`、`move.create_move` 等
- **`projects`**: 这是依赖主项目的其他 rope 项目列表。主项目（包含要修改的定义的项目）会在调用时单独传入
- **`addpath`**: 设为 `True` 时，rope 会自动将主项目的源码文件夹添加到依赖项目的 Python 路径中，这样依赖项目就能正确解析主项目中的模块

## 3. 常用方法

### __call__(project, *args, **kwds)

创建多项目重构对象。

```python
def __call__(self, project, *args, **kwds):
    """Create the refactoring"""
    return _MultiRefactoring(
        self.refactoring, self.projects, self.addpath, project, *args, **kwds
    )
```

| 参数 | 类型 | 说明 |
|------|------|------|
| `project` | `Project` | 主项目（包含要修改的定义的项目） |
| `*args` | 可变位置参数 | 重构类的构造参数（如 resource, offset） |
| `**kwds` | 可变关键字参数 | 重构类的构造关键字参数 |

### get_all_changes(*args, **kwds)

获取所有项目的变更集合。注意：此方法是返回的多项目重构对象的方法，不是 `MultiProjectRefactoring` 类的直接方法。

```python
def get_all_changes(self, *args, **kwds):
    """Get a project to changes dict"""
    result = []
    for project, refactoring in zip(self.projects, self.refactorings):
        args, kwds = self._resources_for_args(project, args, kwds)
        result.append((project, refactoring.get_changes(*args, **kwds)))
    return result
```

| 参数 | 类型 | 说明 |
|------|------|------|
| `*args` | 可变位置参数 | 与对应重构类的 `get_changes()` 方法参数相同 |
| `**kwds` | 可变关键字参数 | 与对应重构类的 `get_changes()` 方法参数相同 |

**返回值**: 返回 `list[(Project, ChangeSet)]` 格式的列表，每个元素是一个元组，包含项目和对应的变更集合

### perform(project_and_changes)

执行多项目变更的辅助函数。

```python
def perform(project_changes):
    for project, changes in project_changes:
        project.do(changes)
```

| 参数 | 类型 | 说明 |
|------|------|------|
| `project_and_changes` | `list[(Project, ChangeSet)]` | 由 `get_all_changes()` 返回的变更列表 |

## 4. 使用场景

### 场景一：跨项目重命名

当一个项目（主项目）中的函数、类、变量被其他项目（依赖项目）引用时，需要同时在所有项目中进行重命名。

```python
# 假设 project_a 是主项目，project_b 依赖 project_a
# 现在需要重命名 project_a 中的某个函数
```

### 场景二：跨项目移动模块

当移动主项目中的模块时，需要同步更新依赖项目中的导入语句。

### 场景三：跨项目提取方法

在主项目中提取方法后，需要确保依赖项目中的调用也能正确工作。

### 场景四：跨项目内联

将主项目中的函数或变量内联后，依赖项目中的使用也需要相应更新。

## 5. 代码示例

### 示例一：跨项目重命名

```python
from rope.base.project import Project
from rope.refactor import multiproject, rename

# 创建项目
main_project = Project("/path/to/main_project")
dependent_project = Project("/path/to/dependent_project")

# 创建依赖项目列表（不包括主项目）
projects = [dependent_project]

# 创建跨项目重命名代理
CrossRename = multiproject.MultiProjectRefactoring(
    rename.Rename,
    projects
)

# 获取要重命名的资源
resource = main_project.get_resource("module.py")

# 创建重命名重构对象
# 假设我们要重命名 module.py 中偏移量为 100 的位置处的名称
renamer = CrossRename(main_project, resource, offset=100)

# 获取所有项目的变更
changes = renamer.get_all_changes("new_name")

# 执行变更
multiproject.perform(changes)

# 关闭项目
main_project.close()
dependent_project.close()
```

### 示例二：跨项目移动模块

```python
from rope.base.project import Project
from rope.refactor import multiproject
from rope.refactor.move import create_move

# 创建项目
main_project = Project("/path/to/main_project")
dependent_project = Project("/path/to/dependent_project")

# 创建跨项目移动代理
CrossMove = multiproject.MultiProjectRefactoring(
    create_move,
    [dependent_project]
)

# 获取要移动的模块
module = main_project.get_resource("old_module.py")

# 创建移动重构对象
mover = CrossMove(main_project, module)

# 目标文件夹
target_folder = main_project.get_resource("new_package")

# 获取所有项目的变更
changes = mover.get_all_changes(target_folder)

# 执行变更
multiproject.perform(changes)

# 关闭项目
main_project.close()
dependent_project.close()
```

### 示例三：带详细选项的重命名

```python
from rope.base.project import Project
from rope.refactor import multiproject, rename

# 创建项目
main_project = Project("/path/to/main_project")
project_b = Project("/path/to/project_b")
project_c = Project("/path/to/project_c")

# 创建依赖项目列表
projects = [project_b, project_c]

# 创建跨项目重命名代理，禁用自动添加路径
CrossRename = multiproject.MultiProjectRefactoring(
    rename.Rename,
    projects,
    addpath=False  # 禁用自动将主项目添加到依赖项目的 Python 路径
)

# 获取要重命名的资源
resource = main_project.get_resource("module.py")

# 创建重命名重构对象
renamer = CrossRename(main_project, resource, offset=100)

# 获取所有项目的变更，带更多选项
changes = renamer.get_all_changes(
    "new_name",
    docs=True,           # 同时重命名文档字符串和注释中的名称
    resources=None,      # 处理所有 Python 文件
)

# 或者手动遍历处理每个项目
for project, project_changes in changes:
    print(f"Project: {project.address}")
    print(f"Changes: {project_changes.get_description()}")
    project.do(project_changes)

# 关闭项目
main_project.close()
project_b.close()
project_c.close()
```

### 示例四：不使用 perform 函数，手动处理每个项目

```python
from rope.base.project import Project
from rope.refactor import multiproject, rename

# 创建项目
main_project = Project("/path/to/main_project")
dependent_project = Project("/path/to/dependent_project")

# 创建跨项目重命名代理
CrossRename = multiproject.MultiProjectRefactoring(
    rename.Rename,
    [dependent_project]
)

# 创建重命名重构对象
resource = main_project.get_resource("module.py")
renamer = CrossRename(main_project, resource, offset=100)

# 获取所有项目的变更
project_and_changes = renamer.get_all_changes("new_name")

# 手动处理每个项目
for project, changes in project_and_changes:
    # 可以先预览变更
    print(f"Previewing changes for {project.address}:")
    for change in changes.changes:
        print(f"  - {change.old_contents} -> {change.new_contents}")

    # 执行变更
    project.do(changes)

# 关闭项目
main_project.close()
dependent_project.close()
```

## 6. 注意事项

1. **项目依赖关系**: 确保依赖项目确实依赖主项目，否则可能会产生不必要的变更
2. **Python 路径**: 默认情况下，主项目的源码文件夹会自动添加到依赖项目的 Python 路径中。如果不想自动添加，可以设置 `addpath=False`
3. **资源转换**: `_MultiRefactoring` 会自动处理不同项目之间的资源转换，确保资源引用正确
4. **性能考虑**: 跨项目重构可能涉及大量文件的扫描和分析，对于大型项目可能需要较长时间
5. **错误处理**: 在执行变更前，建议先预览变更内容，确认无误后再执行

## 7. 相关 API

- `rope.refactor.rename.Rename`: 重命名重构
- `rope.refactor.move.create_move`: 移动模块工厂函数
- `rope.refactor.inline`: 内联重构
- `rope.refactor.extract`: 提取重构
- `rope.base.project.Project`: 项目类
