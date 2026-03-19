# ImportOrganizer API 文档

## 基本信息

- **API 完整路径**: `rope.refactor.importutils.ImportOrganizer`
- **模块位置**: `rope/refactor/importutils/__init__.py`

## 类说明

`ImportOrganizer` 是 rope 库中用于管理模块导入的核心类。它提供了多种导入整理功能，包括排序、去重、移除未使用的导入等。该类的每个方法都会返回一个 `rope.base.change.Change` 对象，用于描述对文件的修改。

## 构造函数

```python
ImportOrganizer(project)
```

### 参数说明

| 参数 | 类型 | 说明 |
|------|------|------|
| project | `rope.base.project.Project` | rope 项目对象，用于访问项目资源和配置 |

## 常用方法

### organize_imports()

整理模块的导入语句。这是使用最频繁的方法，会执行以下操作：

- 移除未使用的导入
- 去除重复的导入
- 移除 self 导入（模块导入自身）
- 对导入进行排序

```python
organize_imports(resource, offset=None)
```

**参数说明**：

| 参数 | 类型 | 说明 |
|------|------|------|
| resource | `rope.base.resource.File` | 要整理导入的文件资源对象 |
| offset | `int`, optional | 偏移量，用于指定只处理特定位置的导入语句。默认为 `None`，表示处理整个文件 |

**返回值**: `rope.base.change.ChangeSet` 或 `None` - 如果有修改返回 ChangeSet 对象，否则返回 `None`

---

### expand_star_imports()

展开星号导入（`from module import *`）为具体的导入语句。

```python
expand_star_imports(resource, offset=None)
```

**参数说明**：

| 参数 | 类型 | 说明 |
|------|------|------|
| resource | `rope.base.resource.File` | 要处理的文件资源对象 |
| offset | `int`, optional | 偏移量，用于指定只处理特定位置的导入语句 |

**返回值**: `rope.base.change.ChangeSet` 或 `None`

---

### froms_to_imports()

将 `from` 导入转换为普通 `import` 语句。

```python
froms_to_imports(resource, offset=None)
```

例如：
```python
# 转换前
from os import path

# 转换后
import os.path
```

**参数说明**：

| 参数 | 类型 | 说明 |
|------|------|------|
| resource | `rope.base.resource.File` | 要处理的文件资源对象 |
| offset | `int`, optional | 偏移量 |

**返回值**: `rope.base.change.ChangeSet` 或 `None`

---

### relatives_to_absolutes()

将相对导入转换为绝对导入。

```python
relatives_to_absolutes(resource, offset=None)
```

例如：
```python
# 转换前
from . import module
from ..package import something

# 转换后
from package.module import something
```

**参数说明**：

| 参数 | 类型 | 说明 |
|------|------|------|
| resource | `rope.base.resource.File` | 要处理的文件资源对象 |
| offset | `int`, optional | 偏移量 |

**返回值**: `rope.base.change.ChangeSet` 或 `None`

---

### handle_long_imports()

处理过长的导入语句，将长导入拆分为多行或使用别名。

```python
handle_long_imports(resource, offset=None)
```

例如：
```python
# 处理前
from very_long_package_name.sub_module.utility import function_one, function_two

# 处理后
from very_long_package_name.sub_module import utility
```

**参数说明**：

| 参数 | 类型 | 说明 |
|------|------|------|
| resource | `rope.base.resource.File` | 要处理的文件资源对象 |
| offset | `int`, optional | 偏移量 |

**返回值**: `rope.base.change.ChangeSet` 或 `None`

---

## 辅助函数

除了 `ImportOrganizer` 类，该模块还提供了以下辅助函数：

### get_imports()

获取指定作用域中使用的导入信息。

```python
get_imports(project, pydefined)
```

**参数说明**：

| 参数 | 类型 | 说明 |
|------|------|------|
| project | `rope.base.project.Project` | rope 项目对象 |
| pydefined | `rope.base.pynames.PyDefined` | Python 定义对象（模块、类、函数等） |

**返回值**: 导入信息列表

---

### get_module_imports()

创建 `ModuleImports` 对象，用于更细粒度地操作导入。

```python
get_module_imports(project, pymodule)
```

**参数说明**：

| 参数 | 类型 | 说明 |
|------|------|------|
| project | `rope.base.project.Project` | rope 项目对象 |
| pymodule | `rope.base.pynames.PyModule` | Python 模块对象 |

**返回值**: `rope.refactor.importutils.module_imports.ModuleImports` 对象

---

### add_import()

添加新的导入语句到模块中。

```python
add_import(project, pymodule, module_name, name=None)
```

**参数说明**：

| 参数 | 类型 | 说明 |
|------|------|------|
| project | `rope.base.project.Project` | rope 项目对象 |
| pymodule | `rope.base.pynames.PyModule` | Python 模块对象 |
| module_name | `str` | 模块名称 |
| name | `str`, optional | 要导入的具体名称（用于 `from module import name` 形式） |

**返回值**: `tuple` - (修改后的源代码, 导入的名称)

---

## 使用场景

### 场景一：整理混乱的 import 语句

当代码库中存在以下问题时，可以使用 `organize_imports()`：

- 重复导入相同模块
- 导入了未使用的模块
- 导入顺序混乱
- 需要按字母排序导入

### 场景二：代码重构前的准备工作

在进行大规模重构前，可以使用以下方法清理导入：

1. `expand_star_imports()` - 展开星号导入，明确依赖
2. `relatives_to_absolutes()` - 统一为绝对导入
3. `handle_long_imports()` - 简化过长的导入路径

### 场景三：自动格式化导入

结合项目配置，可以实现自动格式化导入的功能：

- 设置 `project.prefs['split_imports']` 为 `True` 可以强制使用单行导入
- 使用 `organize_imports()` 可以一键清理所有导入问题

---

## 代码示例

### 示例一：基本使用 - 整理单个文件的导入

```python
from rope.base.project import Project
from rope.refactor.importutils import ImportOrganizer
from rope.base import libutils

# 创建项目
project = Project('/path/to/your/project')

# 创建 ImportOrganizer
organizer = ImportOrganizer(project)

# 获取要处理的文件
resource = project.get_resource('src/example.py')

# 整理导入
changes = organizer.organize_imports(resource)

# 应用修改
if changes:
    project.do(changes)
    print("导入整理完成！")
else:
    print("没有需要整理的导入")

# 关闭项目
project.close()
```

### 示例二：处理特定位置的导入

```python
from rope.base.project import Project
from rope.refactor.importutils import ImportOrganizer

project = Project('/path/to/your/project')
organizer = ImportOrganizer(project)

resource = project.get_resource('src/example.py')

# 假设我们只关心文件第 10 行附近的导入
# 通过 offset 参数指定位置
# 注意：offset 是字符偏移量，不是行号
with open(resource.real_path, 'r') as f:
    lines = f.readlines()
    # 获取第 10 行的偏移量
    offset = sum(len(line) for line in lines[:9])

changes = organizer.organize_imports(resource, offset=offset)

if changes:
    project.do(changes)

project.close()
```

### 示例三：添加新的导入

```python
from rope.base.project import Project
from rope.base import libutils
from rope.refactor.importutils import add_import

project = Project('/path/to/your/project')

# 获取模块
resource = project.get_resource('src/example.py')
pymodule = project.get_pymodule(resource)

# 添加新的导入
new_source, imported_name = add_import(project, pymodule, 'os', 'path')

print(f"已添加导入: {imported_name}")
print(f"修改后的代码:\n{new_source}")

project.close()
```

### 示例四：批量处理多个文件

```python
from rope.base.project import Project
from rope.refactor.importutils import ImportOrganizer

project = Project('/path/to/your/project')
organizer = ImportOrganizer(project)

# 获取所有 Python 文件
py_files = project.get_files('.py')

# 统计
total_changes = 0

for resource in py_files:
    changes = organizer.organize_imports(resource)
    if changes:
        project.do(changes)
        total_changes += 1
        print(f"已整理: {resource.path}")

print(f"共整理了 {total_changes} 个文件")
project.close()
```

### 示例五：完整的导入管理示例

```python
from rope.base.project import Project
from rope.refactor.importutils import ImportOrganizer

# 创建项目时可以指定选项
project = Project('/path/to/your/project', prefs={
    'split_imports': True,  # 强制使用单行导入
})

organizer = ImportOrganizer(project)
resource = project.get_resource('src/example.py')

# 1. 先展开星号导入
print("正在展开星号导入...")
changes = organizer.expand_star_imports(resource)
if changes:
    project.do(changes)

# 2. 转换为绝对导入
print("正在转换为绝对导入...")
changes = organizer.relatives_to_absolutes(resource)
if changes:
    project.do(changes)

# 3. 整理导入（排序、去重、移除未使用）
print("正在整理导入...")
changes = organizer.organize_imports(resource)
if changes:
    project.do(changes)
    print("整理完成！")

project.close()
```

---

## 注意事项

1. **偏移量参数**: `offset` 参数是字符偏移量（character offset），不是行号。如果需要根据行号计算偏移量，需要累加前面所有行的字符长度。

2. **返回值处理**: 所有方法在没有任何修改时会返回 `None`，使用时需要注意空值检查。

3. **项目配置**: 某些功能会受到项目配置影响，例如 `split_imports` 选项会影响 `organize_imports` 的行为。

4. **性能考虑**: 处理大量文件时，建议批量处理并及时调用 `project.do()` 以应用更改。

5. **文件编码**: 确保项目文件使用正确的编码，rope 默认使用 UTF-8 编码。

---

## 相关链接

- [rope 官方文档](https://github.com/python-rope/rope)
- [Project API](./project.md)
- [ChangeSet API](./change_signature.md)
