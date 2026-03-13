---
name: python-refactor
description: 使用 rope 库编写 Python 代码重构脚本。当用户需要进行 Python 代码重构时使用此 skill，包括：重命名（类、函数、方法、变量、模块）、移动（模块、包、类、方法、全局）、提取（方法、变量）、内联（方法、变量、参数）、改变签名（添加、删除、重排序、标准化参数）、封装字段、引入工厂、引入参数、重构结构、使用函数、局部变量转字段、方法对象、模块转包、导入管理、高级查找（Occurrences）、撤销/重做、部分改变、组合重构等。适用于单文件重构、目录级重构、批量文件重构、大规模代码重组等场景。当用户说「重构」、「使用 rope」、「重命名」、「移动模块」、「提取方法」、「内联变量」、「批量重构」、「代码重组」、「封装字段」、「工厂方法」、「组织导入」、「查找引用」、「分析调用」、「影响范围预览」、「撤销重构」、「回滚变更」、「部分修改」等关键词时触发。
---

# Python Refactor Skill

使用 rope 库编写安全、可靠的 Python 代码重构脚本。

## 为什么使用 Rope？

**重要**：Rope 是一个专业的 Python 重构工具，相比手动重构（如查找替换、AST 解析）有以下优势：

1. **理解代码语义**：Rope 解析 Python 语法树，理解作用域、继承关系、导入依赖
2. **自动更新引用**：自动找到并更新所有引用，包括跨文件引用
3. **安全可靠**：不会误改无关代码，支持预览和撤销
4. **处理导入语句**：自动重构导入语句，保持代码一致性
5. **继承层次感知**：在整个继承层次结构中更新引用

**对比**：
- 手动查找替换：可能误改注释、字符串中的同名内容
- AST 手动解析：需要大量代码，容易出错
- **使用 Rope**：一行代码完成，安全可靠

## 工作流程

1. **理解重构需求**
   - 明确用户想要执行的重构类型
   - 确定涉及的范围（单个文件、目录、整个项目）
   - 识别所有需要处理的文件和代码位置

2. **创建重构脚本**
   - 在项目根目录创建 `.refactor` 目录（如果不存在）
   - 使用当前时间戳和描述性标题命名脚本
   - **命名格式**：`{yyyyMMdd-HHmmss}-{kebab-case-标题}.py`
   - 示例：`20260313-143022-rename-olduser-to-user.py`

3. **编写脚本内容**
   - **优先使用 rope 的重构 API**（不要手动实现）
   - 导入必要的 rope 模块
   - 设置项目路径和重构参数
   - 实现具体的重构逻辑
   - 添加预览和确认机制
   - 包含错误处理

4. **输出说明**
   - 告知用户脚本的位置和用途
   - 说明如何执行脚本
   - 提醒用户在执行前做好代码备份

## Rope 重构功能完整列表

### 1. 重命名 (Rename)

重命名类、函数、方法、变量、模块、包等，自动更新所有引用和导入。

```python
from rope.refactor.rename import Rename
from rope.base.project import Project
from rope.base.libutils import path_to_resource

project = Project('/path/to/project')
resource = path_to_resource(project, '/path/to/file.py')
renamer = Rename(project, resource, offset)
changes = renamer.get_changes('new_name')
project.do(changes)
```

**适用场景：**
- 重命名类、函数、方法
- 重命名变量或参数
- 重命名模块或包
- 批量重命名多个符号

### 2. 移动 (Move)

移动模块、包、类、方法或全局变量到其他位置，自动更新所有导入语句。

#### 2.1 移动模块 (MoveModule)

```python
from rope.refactor.move import MoveModule

project = Project('/path/to/project')
resource = project.get_resource('module.py')
mover = MoveModule(project, resource)
changes = mover.get_changes(destination)
project.do(changes)
```

#### 2.2 移动方法 (MoveMethod)

```python
from rope.refactor.move import create_move

project = Project('/path/to/project')
resource = path_to_resource(project, '/path/to/file.py')
mover = create_move(project, resource, offset)
# 将方法移动到另一个类
changes = mover.get_changes('dest_attr')  # 目标属性名
project.do(changes)
```

#### 2.3 移动全局 (MoveGlobal)

```python
from rope.refactor.move import MoveGlobal

project = Project('/path/to/project')
resource = path_to_resource(project, 'source.py')
mover = MoveGlobal(project, resource, offset)
changes = mover.get_changes('destination_module')
project.do(changes)
```

#### 2.4 移动工厂函数

```python
from rope.refactor.move import create_move

# 自动根据偏移量选择合适的移动类型
mover = create_move(project, resource, offset)
changes = mover.get_changes(destination)
project.do(changes)
```

**适用场景：**
- 重组目录结构
- 移动模块到不同包
- 移动类到其他模块
- 移动方法到其他类
- 移动全局函数/变量

### 3. 提取 (Extract)

从代码中提取方法或变量，自动推断参数。

#### 3.1 提取方法 (ExtractMethod)

```python
from rope.refactor.extract import ExtractMethod

project = Project('/path/to/project')
resource = path_to_resource(project, '/path/to/file.py')

# 提取为普通方法
extractor = ExtractMethod(project, resource, start, end)
changes = extractor.get_changes('new_method_name')

# 提取为静态方法 (name 前缀 $)
changes = extractor.get_changes('$static_method')

# 提取为类方法 (name 前缀 @)
changes = extractor.get_changes('@class_method')

# 替换所有相似的代码
changes = extractor.get_changes('new_method', similar=True)

# 提取为全局函数
changes = extractor.get_changes('new_function', global_=True)

project.do(changes)
```

#### 3.2 提取变量 (ExtractVariable)

```python
from rope.refactor.extract import ExtractVariable

extractor = ExtractVariable(project, resource, start, end)
changes = extractor.get_changes('new_var_name')
project.do(changes)
```

**适用场景：**
- 提取重复代码为方法
- 提取复杂表达式为变量
- 改善代码可读性
- 统一重复逻辑

### 4. 内联 (Inline)

内联方法、变量或参数，将调用替换为实际代码。

```python
from rope.refactor.inline import create_inline

project = Project('/path/to/project')
resource = path_to_resource(project, '/path/to/file.py')
inliner = create_inline(project, resource, offset)

# 内联方法
changes = inliner.get_changes(remove=True, only_current=False, resources=None)

# 如果是 InlineVariable 或 InlineParameter，API 相同
project.do(changes)
```

**内联类型：**
- **InlineMethod**：内联方法
- **InlineVariable**：内联局部变量
- **InlineParameter**：内联参数（提取为局部变量）

**适用场景：**
- 简化简单的方法
- 内联临时变量
- 移除不必要的抽象层
- 优化性能

### 5. 改变签名 (Change Signature)

修改函数或方法的参数列表。

```python
from rope.refactor.change_signature import ChangeSignature
from rope.refactor.change_signature import (
    ArgumentAdder,
    ArgumentRemover,
    ArgumentReorderer,
    ArgumentNormalizer,
    ArgumentDefaultInliner,
)

project = Project('/path/to/project')
resource = path_to_resource(project, '/path/to/file.py')
changer = ChangeSignature(project, resource, offset)

# 获取当前参数列表
args = changer.get_args()  # [(name, default), ...]

# 组合多个签名修改
changes = changer.get_changes([
    ArgumentAdder(1, 'new_param', default='value'),  # 添加参数
    ArgumentRemover(2),                             # 删除第2个参数
    ArgumentReorderer([2, 0, 1]),                  # 重排序: 新位置[2,0,1]
])

project.do(changes)
```

**签名修改器类型：**

| 修改器 | 描述 |
|--------|------|
| `ArgumentNormalizer` | 标准化参数名称和默认值 |
| `ArgumentRemover` | 删除参数 |
| `ArgumentAdder` | 添加新参数 |
| `ArgumentDefaultInliner` | 内联默认值到调用处 |
| `ArgumentReorderer` | 重新排列参数顺序 |
| `PermuteArguments` | 交换两个参数位置 |

**适用场景：**
- 添加新的函数参数
- 删除不再使用的参数
- 重新排列参数顺序
- 添加或修改默认值
- 统一参数名称

### 6. 封装字段 (Encapsulate Field)

为类的属性创建 getter 和 setter 方法，保护数据访问。

```python
from rope.refactor.encapsulate_field import EncapsulateField

project = Project('/path/to/project')
resource = path_to_resource(project, '/path/to/file.py')
encapsulator = EncapsulateField(project, resource, offset)

# 可选：指定 getter/setter 名称
changes = encapsulator.get_changes(
    getter='get_field',
    setter='set_field',
    resources=None
)

project.do(changes)
```

**适用场景：**
- 为公共属性添加访问控制
- 实现数据验证
- 延迟计算属性值
- 通知观察者属性变化

### 7. 引入工厂 (Introduce Factory)

为类创建工厂方法，替代直接构造。

```python
from rope.refactor.introduce_factory import IntroduceFactory

project = Project('/path/to/project')
resource = path_to_resource(project, '/path/to/file.py')
factory = IntroduceFactory(project, resource, offset)

# 创建静态工厂方法
changes = factory.get_changes('create_instance', global_factory=False)

# 或创建全局工厂函数
changes = factory.get_changes('create_instance', global_factory=True)

project.do(changes)
```

**适用场景：**
- 需要缓存对象实例
- 根据参数返回不同子类
- 封装复杂的初始化逻辑
- 解耦对象创建和使用

### 8. 引入参数 (Introduce Parameter)

将函数内的表达式提取为参数，支持默认值。

```python
from rope.refactor.introduce_parameter import IntroduceParameter

project = Project('/path/to/project')
resource = path_to_resource(project, '/path/to/file.py')
introducer = IntroduceParameter(project, resource, offset)
changes = introducer.get_changes('new_parameter')
project.do(changes)
```

**适用场景：**
- 将硬编码值提取为参数
- 提高函数灵活性
- 支持依赖注入

### 9. 重构结构 (Restructure)

按模式匹配和替换代码，支持通配符。

```python
from rope.refactor.restructure import Restructure

project = Project('/path/to/project')

# 定义模式、目标和通配符
pattern = "${obj}.get_attr(${name})"
goal = "${obj}[${name}]"
args = {
    "obj": "instance=rope.base.pyobjects.PyObject"
}

restructuring = Restructure(project, pattern, goal, args=args)
changes = restructuring.get_changes(resources=None)
project.do(changes)
```

**常用模式示例：**

```python
# 1. API 迁移
pattern = "${obj}.old_method(${param})"
goal = "new_method(${obj}, ${param})"

# 2. 属性访问迁移
pattern = "${inst}.longtask(${p1}, ${p2})"
goal = """
${inst}.subtask1(${p1})
${inst}.subtask2(${p2})
"""

# 3. 添加导入
pattern = "${pow}(${param1}, ${param2})"
goal = "${param1} ** ${param2}"
imports = ["import math"]
```

**适用场景：**
- 批量替换 API 调用
- 统一代码风格
- 重构设计模式
- 批量提取重复代码

### 10. 使用函数 (UseFunction)

将代码中的重复模式替换为函数调用。

```python
from rope.refactor.usefunction import UseFunction

project = Project('/path/to/project')
resource = path_to_resource(project, '/path/to/file.py')
user = UseFunction(project, resource, offset)

# 将所有匹配该函数体的代码替换为函数调用
changes = user.get_changes(resources=None)
project.do(changes)
```

**适用场景：**
- 统一代码逻辑
- 提取重复代码为函数
- 在整个项目中应用相同的模式

### 11. 局部变量转字段 (Local To Field)

将方法的局部变量转换为类的字段。

```python
from rope.refactor.localtofield import LocalToField

project = Project('/path/to/project')
resource = path_to_resource(project, '/path/to/file.py')
converter = LocalToField(project, resource, offset)
changes = converter.get_changes()
project.do(changes)
```

**适用场景：**
- 需要在多个方法间共享状态
- 延迟初始化属性
- 将临时数据持久化

### 12. 方法对象 (Method Object)

将复杂方法转换为独立的类（命令模式）。

```python
from rope.refactor.method_object import MethodObject

project = Project('/path/to/project')
resource = path_to_resource(project, '/path/to/file.py')
method_obj = MethodObject(project, resource, offset)

# 创建名为 ClassName 的新类
changes = method_obj.get_changes(classname='ComplexTask')
project.do(changes)
```

**适用场景：**
- 减少方法的复杂度
- 需要多个方法共享状态
- 实现命令模式

### 13. 模块转包 (Module To Package)

将单个模块文件转换为包目录。

```python
from rope.refactor.topackage import ModuleToPackage

project = Project('/path/to/project')
resource = project.get_resource('mymodule.py')
converter = ModuleToPackage(project, resource)
changes = converter.get_changes()
project.do(changes)
```

**适用场景：**
- 模块变得太大需要拆分
- 需要添加子模块
- 组织相关功能

### 14. 导入管理 (Import Organizing)

自动组织和优化导入语句。

```python
from rope.refactor.importutils import ImportOrganizer

project = Project('/path/to/project')
organizer = ImportOrganizer(project)

# 整理导入
changes = organizer.organize_imports(resource)

# 展开通配符导入
changes = organizer.expand_star_imports(resource)

# from ... import 转为 import
changes = organizer.froms_to_imports(resource)

# 相对导入转绝对导入
changes = organizer.relatives_to_absolutes(resource)

# 处理长导入行
changes = organizer.handle_long_imports(resource)
```

**适用场景：**
- 清理和排序导入
- 展开通配符
- 统一导入风格
- 优化导入语句

### 15. 多项目重构 (MultiProject)

跨多个关联项目执行重构。

```python
from rope.refactor.multiproject import MultiProjectRefactoring

# 创建多项目重构
multi = MultiProjectRefactoring()

# 添加多个项目
multi.add_project(project1)
multi.add_project(project2)

# 执行跨项目重构
changes = multi.get_changes()
multi.do(changes)
```

**适用场景：**
- 跨项目重命名
- 共享代码的统一重构
- 微服务架构重构

### 16. 高级查找 (Occurrences)

精确查找符号的所有出现位置，支持多种过滤条件。

```python
from rope.refactor.occurrences import create_finder
from rope.refactor.occurrences import (
    CallsFilter,           # 只查找调用（不包括定义）
    InHierarchyFilter,     # 在继承层次中查找
    NoImportsFilter,       # 排除导入语句
    NoKeywordsFilter,      # 排除关键字
)

project = Project('/path/to/project')
resource = path_to_resource(project, '/path/to/file.py')

# 创建查找器
finder = create_finder(project, resource, offset)

# 获取所有出现位置
for occurrence in finder.find_occurrences():
    print(f"文件: {occurrence.resource.path}")
    print(f"偏移量: {occurrence.offset}")
    print(f"是调用: {occurrence.is_called()}")
    print(f"是定义: {occurrence.is_definition()}")

# 使用过滤器查找
# 只查找调用位置（不包括定义）
from rope.refactor.occurrences import CallsFilter
finder = create_finder(project, resource, offset, filters=[CallsFilter()])

# 在整个继承层次中查找
from rope.refactor.occurrences import InHierarchyFilter
finder = create_finder(project, resource, offset, filters=[InHierarchyFilter()])
```

**过滤器类型：**

| 过滤器 | 描述 |
|--------|------|
| `CallsFilter` | 只返回函数调用，不包括定义位置 |
| `InHierarchyFilter` | 在整个继承层次中查找（包括子类重写） |
| `NoImportsFilter` | 排除导入语句中的引用 |
| `NoKeywordsFilter` | 排除关键字同名的引用 |
| `PyNameFilter` | 按名称过滤 |
| `UnsureFilter` | 包含不确定的引用 |

**适用场景：**
- 在重构前预览影响范围
- 只查找函数调用而不修改定义
- 在继承体系中查找重写的方法
- 排除导入和关键字，只关注实际使用

### 17. 组合重构 (Multi-Refactoring)

一次执行多个重构操作。

```python
from rope.refactor.extract import ExtractMethod
from rope.refactor.rename import Rename
from rope.refactor.move import create_move

project = Project('/path/to/project')
resource = path_to_resource(project, '/path/to/file.py')

# 步骤 1: 提取方法
start, end = get_region_offsets(resource, "# TODO: extract", "# end extract")
if start and end:
    extractor = ExtractMethod(project, resource, start, end)
    changes = extractor.get_changes('extracted_method')
    project.do(changes)

# 重新获取资源（内容已变化）
resource = path_to_resource(project, '/path/to/file.py')

# 步骤 2: 重命名提取的方法
offset = find_definition_offset(resource, 'extracted_method', 'def')
renamer = Rename(project, resource, offset)
changes = renamer.get_changes('process_data')
project.do(changes)

print("✓ 组合重构完成！")
```

**适用场景：**
- 复杂的重构任务
- 需要多个步骤的重构
- 大规模代码重组

### 18. 撤销和重做 (Undo/Redo)

Rope 支持撤销和重做重构操作。

```python
from rope.base.project import Project

project = Project('/path/to/project')

# 执行重构
changes = renamer.get_changes('new_name')
project.do(changes)

# 撤销上一次操作
project.history.undo()

# 重做上一次撤销的操作
project.history.redo()

# 查看某个文件的撤销历史
undo_list = project.history.get_file_undo_list(resource)
for item in undo_list:
    print(f"操作: {item}")

# 清空历史记录
project.history.clear()
```

**适用场景：**
- 重构后发现问题需要回退
- 测试不同的重构方案
- 批量重构时需要分步验证

### 19. 部分改变 (ChangeOccurrences)

只改变选定的出现位置，而不是全部位置。

```python
from rope.refactor.rename import ChangeOccurrences
from rope.refactor.occurrences import create_finder, CallsFilter

project = Project('/path/to/project')
resource = path_to_resource(project, '/path/to/file.py')

# 创建查找器，只查找调用（不包括定义）
finder = create_finder(project, resource, offset, filters=[CallsFilter()])

# 创建部分改变对象
changer = ChangeOccurrences(project, resource, offset)

# 只改变指定的出现位置
changes = changer.get_changes([occurrence1, occurrence2, ...])
project.do(changes)
```

**与 Rename 的区别：**
- `Rename`：改变所有出现位置（包括定义和所有引用）
- `ChangeOccurrences`：只改变选定的出现位置

**适用场景：**
- 只重命名部分引用
- 逐步迁移 API（先改一部分，再改另一部分）
- 条件性重构（例如只改某个模块内的引用）

## 工具函数库

### Rope 基础工具函数

```python
from rope.base.libutils import (
    path_to_resource,           # 路径转资源对象
    get_string_module,          # 获取字符串形式的模块
    get_string_scope,           # 获取字符串作用域
    is_python_file,             # 检查是否为 Python 文件
    analyze_module,             # 分析单个模块
    analyze_modules,            # 分析多个模块
    path_relative_to_project_root,  # 获取相对于项目根的路径
    report_change,              # 报告变更
)

# 常用示例
resource = path_to_resource(project, 'path/to/file.py')
scope = get_string_scope(project, 'def foo(): pass')
python_files = [f for f in project.get_files() if is_python_file(f)]
```

### 查找代码偏移量

```python
def find_offset(resource, pattern, start=0):
    """
    在资源中查找模式的偏移量

    Args:
        resource: rope 资源对象
        pattern: 要查找的字符串或正则表达式
        start: 搜索起始位置

    Returns:
        匹配位置的偏移量，未找到返回 None
    """
    content = resource.read()
    if isinstance(pattern, str):
        offset = content.find(pattern, start)
        return offset if offset != -1 else None
    else:
        import re
        match = re.search(pattern, content[start:])
        return match.start() + start if match else None
```

### 查找类/函数定义

```python
def find_definition_offset(resource, name, definition_type='class'):
    """
    查找类或函数定义的偏移量

    Args:
        resource: rope 资源对象
        name: 类名或函数名
        definition_type: 'class' 或 'def'
    """
    if definition_type == 'class':
        pattern = f'class {name}'
    else:
        pattern = f'def {name}'
    return find_offset(resource, pattern)
```

### 计算代码区域偏移量

```python
def get_region_offsets(resource, start_pattern, end_pattern):
    """
    查找代码区域的起始和结束偏移量

    Returns:
        (start_offset, end_offset) 或 None
    """
    start_offset = find_offset(resource, start_pattern)
    if start_offset is None:
        return None

    # 从起始位置后查找结束模式
    content = resource.read()
    end_offset = content.find(end_pattern, start_offset)
    if end_offset == -1:
        return None

    return (start_offset, end_offset)
```

### 验证文件存在

```python
def ensure_file_exists(file_path):
    """验证文件存在，不存在则抛出异常"""
    if not Path(file_path).exists():
        raise FileNotFoundError(f"文件不存在: {file_path}")
```

### 生成时间戳

```python
from datetime import datetime

# 获取当前时间戳
timestamp = datetime.now().strftime('%Y%m%d-%H%M%S')
```

## 脚本命名规范

### 格式要求

所有重构脚本存放在项目根目录的 `.refactor` 目录下，命名格式为：

```
{yyyyMMdd-HHmmss}-{kebab-case-标题}.py
```

### 命名组成部分

1. **时间戳** `{yyyyMMdd-HHmmss}`
   - `yyyy`：4 位年份
   - `MM`：2 位月份（01-12）
   - `dd`：2 位日期（01-31）
   - `HH`：2 位小时（00-23）
   - `mm`：2 位分钟（00-59）
   - `ss`：2 位秒（00-59）

2. **分隔符** `-` (连字符)

3. **标题** `{kebab-case-标题}`
   - 使用小写字母
   - 单词之间用连字符 `-` 分隔
   - 简明扼要地描述重构内容
   - 避免使用特殊字符

### 命名示例

✅ **正确的命名**：
- `20260313-143022-rename-user-model.py`
- `20260313-153145-move-auth-modules.py`
- `20260313-161234-extract-validation-method.py`
- `20260313-170545-reorganize-api-directory.py`

❌ **不正确的命名**：
- `rename.py` (缺少时间戳和描述)
- `20260313-renameClass.py` (使用了驼峰命名)
- `20260313_重命名.py` (使用了中文和非标准字符)
- `20260313.py` (缺少描述)

## 脚本模板

### 基本脚本结构

```python
#!/usr/bin/env python3
"""
重构脚本：{描述}

用途：{详细说明}
创建时间：{时间}

使用方法：
    python .refactor/{filename}

注意事项：
    - 建议先使用 git commit 备份当前代码
    - 可以使用 --dry-run 参数预览变更
"""

import sys
import argparse
from pathlib import Path
from rope.base.project import Project
from rope.base.libutils import path_to_resource
from rope.base.exceptions import RefactoringError
from rope.refactor.{module} import {RefactoringClass}

def main():
    # 解析命令行参数
    parser = argparse.ArgumentParser(description='{描述}')
    parser.add_argument('--dry-run', action='store_true', help='预览模式，不实际修改文件')
    args = parser.parse_args()

    # 配置项目路径
    project_path = Path(__file__).parent.parent
    project = Project(str(project_path))

    try:
        # 执行重构
        resource = path_to_resource(project, 'path/to/file.py')

        # 查找代码偏移量
        offset = find_definition_offset(resource, 'ClassName')

        refactoring = {RefactoringClass}(project, resource, offset)
        changes = refactoring.get_changes(...)

        if args.dry_run:
            print("预览变更：")
            print(changes.get_description())
        else:
            print("执行重构...")
            project.do(changes)
            print("重构完成！")

    except RefactoringError as e:
        print(f"重构错误：{e}")
        return 1
    except Exception as e:
        print(f"错误：{e}")
        import traceback
        traceback.print_exc()
        return 1
    finally:
        project.close()

    return 0

if __name__ == '__main__':
    sys.exit(main())
```

## 重构场景快速参考

### 重命名类

```python
from rope.refactor.rename import Rename

renamer = Rename(project, resource, offset)
changes = renamer.get_changes('NewName')
```

### 移动模块

```python
from rope.refactor.move import MoveModule

mover = MoveModule(project, resource)
changes = mover.get_changes(destination)
```

### 提取方法

```python
from rope.refactor.extract import ExtractMethod

extractor = ExtractMethod(project, resource, start, end)
changes = extractor.get_changes('method_name', similar=True)
```

### 内联方法

```python
from rope.refactor.inline import create_inline

inliner = create_inline(project, resource, offset)
changes = inliner.get_changes()
```

### 修改签名

```python
from rope.refactor.change_signature import ChangeSignature, ArgumentAdder

changer = ChangeSignature(project, resource, offset)
changes = changer.get_changes([ArgumentAdder(1, 'new_param')])
```

### 封装字段

```python
from rope.refactor.encapsulate_field import EncapsulateField

encapsulator = EncapsulateField(project, resource, offset)
changes = encapsulator.get_changes(getter='get_x', setter='set_x')
```

### 引入工厂

```python
from rope.refactor.introduce_factory import IntroduceFactory

factory = IntroduceFactory(project, resource, offset)
changes = factory.get_changes('create', global_factory=True)
```

### 组织导入

```python
from rope.refactor.importutils import ImportOrganizer

organizer = ImportOrganizer(project)
changes = organizer.organize_imports(resource)
```

## 最佳实践

### 1. 始终使用 rope 的重构 API

- 不要手动处理导入语句
- 不要使用正则表达式替换
- 不要手动修改文件

### 2. 正确处理项目

- 使用 `try-finally` 确保 `project.close()` 被调用
- 每次重构后重新获取资源（如果内容可能变化）

### 3. 预览变更

- 先使用 `get_changes()` 获取变更
- 使用 `changes.get_description()` 查看变更描述
- 确认后再调用 `project.do(changes)`

### 4. 处理偏移量

- 使用工具函数查找定义位置
- 偏移量是字符位置，从 0 开始
- 类名偏移量应该是类名开始的位置（跳过 "class "）

### 5. 选择合适的重构操作

- **重命名 vs 移动**：只改变名称用重命名，改变位置用移动
- **提取 vs 内联**：减少重复用提取，简化过度抽象用内联
- **MoveModule vs MoveMethod**：移动整个文件用 MoveModule，移动方法用 create_move
- **ExtractMethod vs UseFunction**：单个位置提取用 ExtractMethod，全局替换用 UseFunction

### 6. 组合重构策略

- 先做小步骤重构，每次验证
- 使用 git commit 在每步后提交
- 重构顺序建议：提取 → 重命名 → 移动 → 内联
- 避免在一个脚本中执行太多操作

## API 参考

### 核心类

- **Project**: `rope.base.project.Project` - 项目接口，必须首先创建
- **libutils**: `rope.base.libutils` - 工具函数
  - `path_to_resource()` - 路径转资源
  - `get_string_module()` - 获取字符串模块
  - `get_string_scope()` - 获取字符串作用域

### 工厂函数

- **create_move**: `rope.refactor.move.create_move` - 创建移动操作（自动选择类型）
- **create_inline**: `rope.refactor.inline.create_inline` - 创建内联操作（自动选择类型）

### 基础重构类

- **Rename**: `rope.refactor.rename.Rename` - 重命名
- **MoveModule**: `rope.refactor.move.MoveModule` - 移动模块
- **MoveMethod**: `rope.refactor.move.MoveMethod` - 移动方法
- **MoveGlobal**: `rope.refactor.move.MoveGlobal` - 移动全局
- **ExtractMethod**: `rope.refactor.extract.ExtractMethod` - 提取方法
- **ExtractVariable**: `rope.refactor.extract.ExtractVariable` - 提取变量
- **InlineMethod**: `rope.refactor.inline.InlineMethod` - 内联方法
- **InlineVariable**: `rope.refactor.inline.InlineVariable` - 内联变量
- **InlineParameter**: `rope.refactor.inline.InlineParameter` - 内联参数

### 高级重构类

- **ChangeSignature**: `rope.refactor.change_signature.ChangeSignature` - 改变签名
- **EncapsulateField**: `rope.refactor.encapsulate_field.EncapsulateField` - 封装字段
- **IntroduceFactory**: `rope.refactor.introduce_factory.IntroduceFactory` - 引入工厂
- **IntroduceParameter**: `rope.refactor.introduce_parameter.IntroduceParameter` - 引入参数
- **Restructure**: `rope.refactor.restructure.Restricture` - 重构结构
- **UseFunction**: `rope.refactor.usefunction.UseFunction` - 使用函数
- **LocalToField**: `rope.refactor.localtofield.LocalToField` - 局部变量转字段
- **MethodObject**: `rope.refactor.method_object.MethodObject` - 方法对象
- **ModuleToPackage**: `rope.refactor.topackage.ModuleToPackage` - 模块转包

### 签名修改器

- **ArgumentNormalizer**: `rope.refactor.change_signature.ArgumentNormalizer` - 参数标准化
- **ArgumentRemover**: `rope.refactor.change_signature.ArgumentRemover` - 删除参数
- **ArgumentAdder**: `rope.refactor.change_signature.ArgumentAdder` - 添加参数
- **ArgumentDefaultInliner**: `rope.refactor.change_signature.ArgumentDefaultInliner` - 默认值内联
- **ArgumentReorderer**: `rope.refactor.change_signature.ArgumentReorderer` - 重排序参数
- **PermuteArguments**: `rope.refactor.change_signature.PermuteArguments` - 置换参数

### 导入管理

- **ImportOrganizer**: `rope.refactor.importutils.ImportOrganizer` - 组织导入
- **ImportTools**: `rope.refactor.importutils.ImportTools` - 导入工具

### 高级查找

- **Finder**: `rope.refactor.occurrences.Finder` - 查找符号出现位置
- **create_finder**: `rope.refactor.occurrences.create_finder` - 创建查找器
- **CallsFilter**: `rope.refactor.occurrences.CallsFilter` - 只查找调用
- **InHierarchyFilter**: `rope.refactor.occurrences.InHierarchyFilter` - 继承层次查找
- **NoImportsFilter**: `rope.refactor.occurrences.NoImportsFilter` - 排除导入
- **NoKeywordsFilter**: `rope.refactor.occurrences.NoKeywordsFilter` - 排除关键字
- **Occurrence**: `rope.refactor.occurrences.Occurrence` - 单个出现位置

### 撤销/重做

- **History**: `rope.base.history.History` - 历史记录管理
  - `undo()` - 撤销上一次操作
  - `redo()` - 重做上一次撤销的操作
  - `clear()` - 清空历史记录
  - `get_file_undo_list()` - 获取文件的撤销历史

### 部分改变

- **ChangeOccurrences**: `rope.refactor.rename.ChangeOccurrences` - 部分改变出现位置

### 变更对象

- **ChangeSet**: `rope.base.change.ChangeSet` - 变更集合
  - `get_description()` - 获取变更描述
  - `get_changed_resources()` - 获取受影响的资源
- **ChangeContents**: `rope.base.change.ChangeContents` - 修改文件内容
- **MoveResource**: `rope.base.change.MoveResource` - 移动资源
- **CreateResource**: `rope.base.change.CreateResource` - 创建资源
- **RemoveResource**: `rope.base.change.RemoveResource` - 删除资源

### 资源对象

- **Resource**: `rope.base.resources.Resource` - 资源基类
- **File**: `rope.base.resources.File` - 文件资源
- **Folder**: `rope.base.resources.Folder` - 文件夹资源
- `read()` - 读取文件内容
- `write()` - 写入文件内容
- `get_children()` - 获取子资源

### 多项目

- **MultiProjectRefactoring**: `rope.refactor.multiproject.MultiProjectRefactoring` - 多项目重构

### 异常

- **RefactoringError**: `rope.base.exceptions.RefactoringError` - 重构错误
- **ResourceNotFoundError**: `rope.base.exceptions.ResourceNotFoundError` - 资源不存在错误
- **ModuleNotFoundError**: `rope.base.exceptions.ModuleNotFoundError` - 模块不存在错误
- **NameNotFoundError**: `rope.base.exceptions.NameNotFoundError` - 名称未找到错误
- **AttributeNotFoundError**: `rope.base.exceptions.AttributeNotFoundError` - 属性未找到错误
- **ModuleSyntaxError**: `rope.base.exceptions.ModuleSyntaxError` - 模块语法错误
- **ModuleDecodeError**: `rope.base.exceptions.ModuleDecodeError` - 模块解码错误
- **HistoryError**: `rope.base.exceptions.HistoryError` - 历史记录错误
- **RopeError**: `rope.base.exceptions.RopeError` - Rope 基础异常
