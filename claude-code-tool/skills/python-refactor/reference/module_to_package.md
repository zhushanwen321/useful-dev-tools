# ModuleToPackage API 文档

## 1. 基本信息

- **API 完整路径**: `rope.refactor.topackage.ModuleToPackage`
- **模块**: `rope.refactor.topackage`
- **类说明**: 将模块（.py 文件）转换为包（包含 `__init__.py` 的目录）。该重构操作会将模块文件移动到一个同名的子目录中，并在该目录中创建 `__init__.py` 文件，同时自动将模块中的相对导入转换为绝对导入。

## 2. 构造函数

```python
class ModuleToPackage:
    def __init__(self, project, resource):
```

### 构造函数参数

| 参数名 | 类型 | 必填 | 说明 |
|--------|------|------|------|
| `project` | `Project` | 是 | rope 项目对象 |
| `resource` | `File` | 是 | 要转换的模块文件资源对象 |

## 3. 常用方法

### get_changes()

生成将模块转换为包所需的变更集合。

```python
def get_changes(self):
    """生成模块到包转换的变更集"""
```

**返回值**: 返回一个 `ChangeSet` 对象，包含以下变更：

1. **修改模块内容**: 如果模块中使用了相对导入，会自动将相对导入转换为绝对导入形式
2. **创建目录**: 在原模块所在位置创建一个与模块同名的目录
3. **移动文件**: 将原模块文件移动到新创建的目录中，重命名为 `__init__.py`

**返回类型**: `ChangeSet`

## 4. 使用场景

### 4.1 将单个模块转换为包

当你需要将一个 Python 模块文件转换为一个包（package）时使用。这通常是项目结构演进的一部分，允许后续在包中添加更多模块。

```python
# 原始结构
# project/
#   mod1.py

# 转换后结构
# project/
#   mod1/
#     __init__.py
```

### 4.2 处理相对导入

当被转换的模块中使用了相对导入时，API 会自动将其转换为绝对导入。例如：

转换前 (mod1.py):
```python
from . import sibling_module
from .sub import some_func
```

转换后 (mod1/__init__.py):
```python
from package_name import sibling_module
from package_name.sub import some_func
```

### 4.3 扩展项目结构

当你计划将一个模块作为包的入口点，并希望在同目录下添加更多子模块时，这种转换非常有用。

## 5. 代码示例

### 5.1 基础用法

```python
from rope.base.project import Project
from rope.refactor.topackage import ModuleToPackage

# 创建项目
project = Project("/path/to/project")

# 获取要转换的模块
mod = project.get_resource("my_module.py")

# 创建模块转包重构对象
transformer = ModuleToPackage(project, mod)

# 获取变更集
changes = transformer.get_changes()

# 执行重构
project.do(changes)
project.close()
```

### 5.2 完整示例：转换模块并处理导入

```python
from rope.base.project import Project
from rope.refactor import topackage
import testutils  # rope 测试工具

# 创建测试项目
project = Project("/path/to/project")

# 创建测试模块
mod1 = testutils.create_module(project, "mod1")
mod1.write("import mod2\nfrom mod2 import AClass\n")

mod2 = testutils.create_module(project, "mod2")
mod2.write("class AClass(object):\n    pass\n")

# 将 mod2 转换为包
transformer = topackage.ModuleToPackage(project, mod2)
changes = transformer.get_changes()

# 查看变更描述
print(changes.get_description())

# 执行变更
project.do(changes)

# 验证结果
mod2 = project.get_resource("mod2")
root_folder = project.root

# 原始 mod2.py 已不存在
assert not root_folder.has_child("mod2.py")

# 新包已创建，包含 __init__.py
mod2_dir = root_folder.get_child("mod2")
init_file = mod2_dir.get_child("__init__.py")
assert init_file is not None
print(init_file.read())
# 输出: class AClass(object):
#           pass

project.close()
```

### 5.3 处理相对导入的示例

```python
from rope.base.project import Project
from rope.refactor.topackage import ModuleToPackage

project = Project("/path/to/project")

# 假设存在包 pkg，包含 mod1.py
pkg = project.get_resource("pkg")
mod1 = project.get_resource("pkg/mod1.py")

# mod1.py 包含相对导入
# import mod2
# from mod2 import AClass

# 将 mod1 转换为包
transformer = ModuleToPackage(project, mod1)
changes = transformer.get_changes()

project.do(changes)

# 相对导入已被自动转换为绝对导入
new_init = project.get_resource("pkg/mod1/__init__.py")
print(new_init.read())
# 输出:
# import pkg.mod2
# from pkg.mod2 import AClass

project.close()
```

### 5.4 结合历史记录支持撤销

```python
from rope.base.project import Project
from rope.refactor.topackage import ModuleToPackage

project = Project("/path/to/project")

mod = project.get_resource("my_module.py")
transformer = ModuleToPackage(project, mod)
changes = transformer.get_changes()

# 执行转换
project.do(changes)

# 可以撤销操作
project.history.undo()

# 验证已恢复原状
assert project.get_resource("my_module.py") is not None
assert not project.get_resource("my_module/")

project.close()
```

## 6. 注意事项

1. **文件命名**: 只有以 `.py` 结尾的模块文件才能被转换，包目录无法直接通过此 API 转换
2. **相对导入**: API 会自动处理相对导入转换为绝对导入，但这需要正确设置包名
3. **依赖关系**: 转换后可能需要手动更新其他引用该模块的代码，因为导入路径可能需要相应调整
4. **Undo 支持**: 重构操作支持撤销，可以恢复到转换前的状态

## 7. 相关 API

- `rope.refactor.move.MoveModule`: 移动模块到其他位置
- `rope.refactor.importutils.ImportTools.relatives_to_absolutes`: 相对导入转绝对导入的工具函数
