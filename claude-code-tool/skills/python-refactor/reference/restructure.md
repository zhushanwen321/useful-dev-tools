# Restructure API

## 基本信息

- **API 完整路径**: `rope.refactor.restructure.Restructure`
- **类说明**: 基于模式匹配的重构工具

`Restructure` 是 rope 库中强大的批量重构工具，它允许开发者通过定义**模式（pattern）**和**目标（goal）**来批量替换代码中的特定模式。在模式中可以使用**通配符（wildcards）**来匹配任意代码片段，并通过参数进行条件限制。

## 构造函数参数

```python
Restructure(project, pattern, goal, args=None, imports=None, wildcards=None)
```

| 参数 | 类型 | 说明 |
|------|------|------|
| `project` | `Project` | rope 项目对象，必填 |
| `pattern` | `str` | 要匹配的模式字符串，支持通配符语法 `${name}` |
| `goal` | `str` | 替换后的目标代码模板 |
| `args` | `dict` | 可选，通配符参数，用于限制匹配条件 |
| `imports` | `list` | 可选，需要添加的导入语句列表 |
| `wildcards` | `list` | 可选，自定义通配符类型列表 |

### 通配符参数（args）

`args` 参数是一个字典，键是通配符名称，值是通配符的约束条件。约束条件可以是字符串或字典格式。

**字符串格式**: `"key1=value1,key2=value2,..."`

**支持的约束条件**:

- `name`: 匹配具有特定名称的引用
- `type`: 匹配特定类型的表达式（如 `type=mod.MyClass`）
- `object`: 匹配特定对象（如 `object=mod.func`）
- `instance`: 匹配某个类的实例（包括子类）
- `exact`: 仅匹配名称完全相同的引用
- `unsure`: 同时匹配确定的和不确定的引用

### 导入语句（imports）

`imports` 参数是一个字符串列表，每行一个导入语句。rope 会自动处理重复导入，不会添加已经存在的导入。

## 使用场景

### 1. 批量替换代码模式

将所有符合特定模式的代码批量替换为新形式，例如：
- 将 `obj.get_attribute(name)` 转换为 `obj[name]`
- 将 `func(a, b)` 转换为 `a ** b`（当 func 是 pow 函数时）

### 2. 条件重构

通过通配符参数限制匹配条件，只对特定类型或特定对象的代码进行替换：
- 只对特定类的实例方法调用进行替换
- 只对特定类型的变量进行替换
- 只对名称完全匹配的引用进行替换

### 3. 自动添加导入

在重构过程中自动添加必要的导入语句，避免手动添加导入的麻烦。

### 4. 局部/全局重构

可以针对特定文件或整个项目进行重构，灵活性高。

## 代码示例

### 示例 1：基本字符串替换

将项目中所有 `a = 1` 替换为 `a = 0`：

```python
from rope.base.project import Project
from rope.refactor.restructure import Restructure

# 创建项目
project = Project('path/to/your/project')

# 创建重构器
restructure = Restructure(project, "a = 1", "a = 0")

# 执行重构
changes = restructure.get_changes()
project.do(changes)

project.close()
```

### 示例 2：使用通配符

将任意变量赋值 `a = 1` 替换为 `a = int(1)`：

```python
restructure = Restructure(
    project,
    "${a} = 1",
    "${a} = int(1)"
)
changes = restructure.get_changes()
```

### 示例 3：使用 exact 参数

只对名称完全为 `a` 的变量进行替换（不会替换 `b = 1`）：

```python
restructure = Restructure(
    project,
    "${a} = 1",
    "${a} = int(1)",
    args={"a": "exact"}
)
```

### 示例 4：按类型匹配

只对整数类型的表达式进行替换：

```python
restructure = Restructure(
    project,
    "${i} + ${i}",
    "${i} * 2",
    args={"i": "type=__builtin__.int"}
)
# 1 + 1 -> 1 * 2
# "a" + "a" 不会被替换
```

### 示例 5：按对象匹配

只对特定函数的调用进行替换。假设有 `mod.py` 文件中定义了函数 `f`：

```python
restructure = Restructure(
    project,
    "${f}()",
    "${f}(2)",
    args={"f": "object=mod.f"}
)
# 只会替换 mod.f() 的调用，不会替换其他函数
```

### 示例 6：按实例类型匹配

替换特定类的实例方法调用：

```python
# 将 obj.method() 替换为 obj.get_method()
# 只对 MyClass 类的实例生效
restructure = Restructure(
    project,
    "${obj}.method()",
    "${obj}.get_method()",
    args={"obj": "instance=mod.MyClass"}
)
```

### 示例 7：自动添加导入

在替换的同时自动添加导入语句：

```python
restructure = Restructure(
    project,
    "${a} = 2",
    "${a} = myconsts.two",
    imports=["import myconsts"]
)
# 替换后会自动添加: import myconsts
# a = 2 -> import myconsts; a = myconsts.two
```

### 示例 8：多行目标替换

将单行代码替换为多行代码：

```python
restructure = Restructure(
    project,
    "${a} = 2",
    "${a} = 1\n${a} += 1"
)
# a = 2 -> a = 1; a += 1
```

### 示例 9：针对特定文件重构

只对特定文件进行重构，而不是整个项目：

```python
# 假设 mod.py 是目标文件
mod = project.get_resource('mod.py')

restructure = Restructure(project, "1", "2 / 1")
changes = restructure.get_changes(resources=[mod])
```

### 示例 10：使用 unsure 参数

对于类型不确定的引用也进行匹配：

```python
restructure = Restructure(
    project,
    "${s} * 2",
    "dup(${s})",
    args={"s": {"type": "__builtins__.str", "unsure": True}}
)
# 即使类型不确定，也会尝试匹配字符串的 * 操作
```

### 示例 11：复杂模式匹配

将 `x.name in obj.get_attributes()` 转换为 `x.name in obj`：

```python
restructure = Restructure(
    project,
    "${name} in ${pyobject}.get_attributes()",
    "${name} in {pyobject}",
    args={"pyobject": "instance=rope.base.pyobjects.PyObject"}
)
```

### 示例 12：批量替换模块创建

将旧式的模块创建方式替换为新方式：

```python
restructure = Restructure(
    project,
    "${pycore}.create_module(${project}.root, ${name})",
    "generate.create_module(${project}, ${name})",
    imports=["from rope.contrib import generate"],
    args={"project": "type=rope.base.project.Project"}
)
```

## 核心方法

### get_changes()

```python
get_changes(checks=None, imports=None, resources=None, task_handle=taskhandle.DEFAULT_TASK_HANDLE)
```

获取重构所需的更改。

**参数说明**:

| 参数 | 类型 | 说明 |
|------|------|------|
| `checks` | `dict` | **已废弃**，请使用构造函数中的 `args` 参数 |
| `imports` | `dict` | **已废弃**，请使用构造函数中的 `imports` 参数 |
| `resources` | `list` | 可选，要应用重构的文件列表，默认为所有 Python 文件 |
| `task_handle` | `TaskHandle` | 可选，任务进度处理器 |

**返回值**: `ChangeSet` 对象，包含所有需要修改的文件和内容

### make_checks()

```python
make_checks(string_checks)
```

将字符串格式的检查条件转换为 PyObject 格式。此方法主要用于简化 UI 编写。

**参数**:
- `string_checks`: 字符串格式的检查条件字典

**示例**:

```python
# 旧写法
string_checks = {'obj1.type': 'mod.A', 'obj2': 'mod.B'}
restructuring = Restructure(project, pattern, goal)
checks = restructuring.make_checks(string_checks)

# 新写法（推荐）
args = {'obj1': 'type=mod.A', 'obj2': 'name=mod.B'}
restructuring = Restructure(project, pattern, goal, args=args)
```

## 注意事项

1. **通配符命名**: 通配符名称（在 `${name}` 中）必须与 `args` 字典中的键对应
2. **重复匹配**: 默认情况下，重叠的匹配只会替换第一个，后续匹配会跳过重叠部分
3. **导入处理**: rope 自动处理重复导入，不会添加已经存在的导入语句
4. **表达式 vs 语句**: 模式可以匹配表达式或语句，会自动处理两种情况的缩进
5. **类型检查**: 使用 `type` 参数时，需要使用完整的模块路径（如 `__builtin__.int`）

## 底层实现

`Restructure` 类内部使用以下组件：
- `similarfinder.SimilarFinder`: 用于查找匹配的模式
- `similarfinder.CodeTemplate`: 用于生成替换后的代码
- `_ChangeComputer`: 用于计算实际的代码变更
- `patchedast`: 用于处理 AST 补丁

## 相关链接

- 源码位置: `/rope/refactor/restructure.py`
- 测试文件: `/ropetest/refactor/restructuretest.py`
- 相关模块: `rope.refactor.wildcards` (通配符定义)
