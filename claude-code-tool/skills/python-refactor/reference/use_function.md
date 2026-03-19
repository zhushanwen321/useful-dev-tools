# UseFunction

## 基本信息

- **API 完整路径**：`rope.refactor.usefunction.UseFunction`
- **类说明**：将代码中符合函数体模式的代码替换为函数调用。这是一个与"内联函数"相反的重构操作，它会在项目中查找并将与函数体逻辑匹配的代码替换为函数调用。

## 构造函数参数

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `project` | `Project` | 是 | rope 项目对象 |
| `resource` | `Resource` | 是 | 包含目标函数的 Python 文件资源 |
| `offset` | `int` | 是 | 函数定义位置的光标偏移量 |

**构造过程说明**：

1. 通过 `evaluate.eval_location()` 评估光标位置对应的 Python 名称
2. 验证所选对象是一个全局函数（非类方法、局部函数等）
3. 检查函数是否符合使用条件：
   - 不能是生成器函数（包含 `yield`）
   - 只能有一个 return 语句
   - return 语句必须是函数的最后一条语句

**抛出异常**：

- `RefactoringError`: 当光标位置无法解析、选择的不是全局函数、或函数不符合内联条件时抛出

## 常用方法

### get_changes(resources=None, task_handle=taskhandle.DEFAULT_TASK_HANDLE)

生成重构变更集合。

**参数**：

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `resources` | `list[Resource]` | `None` | 要处理的文件资源列表，默认为项目所有 Python 文件 |
| `task_handle` | `TaskHandle` | `DEFAULT_TASK_HANDLE` | 任务句柄，用于显示进度 |

**返回值**：`ChangeSet` - 包含所有文件变更的集合

**执行流程**：

1. 首先处理除函数所在文件之外的其他文件（添加 import 语句）
2. 然后处理函数所在的文件（不添加 import）

### get_function_name()

获取目标函数的名称。

**返回值**：`str` - 函数名称

## 使用场景

UseFunction 适用于以下场景：

1. **代码复用**：当代码中存在多处与某个函数体逻辑相同的代码模式时，可以将这些代码替换为函数调用，减少重复代码
2. **提取函数的反向操作**：与 Extract Method（提取方法）相反，将已提取的函数应用到代码中匹配的模式
3. **函数推广**：当你想将某个局部使用的函数推广到更多地方使用时，可以快速将匹配函数体逻辑的代码替换为函数调用
4. **代码重构**：将重复的代码模式统一替换为函数调用，提高代码可读性和可维护性

## 限制条件

使用 UseFunction 时，函数必须满足以下条件：

1. **必须是全局函数**：不能是类方法、静态方法、lambda 或局部函数
2. **不能是生成器**：不能包含 `yield` 关键字
3. **只能有一个 return 语句**：函数体中最多只能有一个 return
4. **return 必须是最后一条语句**：return 必须是函数体的最后一条语句

## 代码示例

### 基本用法

```python
from rope.base.project import Project
from rope.refactor.usefunction import UseFunction

# 创建项目
project = Project('my_project')

# 获取要重构的文件
mod = project.get_resource('module.py')

# 创建 UseFunction 对象，光标在函数定义位置
# 假设我们要使用一个名为 add 的函数
user = UseFunction(project, mod, mod.read().index('def add'))

# 获取变更并应用
changes = user.get_changes()
project.do(changes)
```

### 完整示例：简单函数调用替换

**重构前**：

```python
# module.py
def f(p):
    print(p)

print(1)
```

**代码**：

```python
from rope.base.project import Project
from rope.refactor.usefunction import UseFunction

project = Project('.')
mod = project.get_resource('module.py')
code = mod.read()

# 找到函数定义的位置
offset = code.index('def f')
user = UseFunction(project, mod, offset)

# 应用变更
project.do(user.get_changes())
```

**重构后**：

```python
# module.py
def f(p):
    print(p)

f(1)
```

`print(1)` 被替换为 `f(1)`，符合函数体 `print(p)` 的模式。

### 带参数替换

**重构前**：

```python
# module.py
def f(p):
    print(p + 1)

print(1 + 1)
```

**重构后**：

```python
# module.py
def f(p):
    print(p + 1)

f(1)
```

参数会被正确映射：`p` 替换为 `1`。

### 带返回值的函数

**重构前**：

```python
# module.py
def f(p):
    return p + 1

r = 2 + 1
print(r)
```

**重构后**：

```python
# module.py
def f(p):
    return p + 1

r = f(2)
print(r)
```

当函数有返回值时，赋值语句会被替换为函数调用。

### 单表达式返回值的特殊处理

当函数体只有一个 return 语句且是单一表达式时，会直接替换表达式：

**重构前**：

```python
# module.py
def f(p):
    return p + 1

print(2 + 1)
```

**重构后**：

```python
# module.py
def f(p):
    return p + 1

print(f(2))
```

### 跨模块替换

**重构前**：

```python
# mod1.py
def f(p):
    return p + 1

# mod2.py
print(2 + 1)
```

**重构后**：

```python
# mod1.py
def f(p):
    return p + 1

# mod2.py
import mod1
print(mod1.f(2))
```

其他模块中的匹配代码也会被替换，并自动添加 import 语句。

### 多语句函数

**重构前**：

```python
# module.py
def f(p):
    r = p + 1
    print(r)

r = 2 + 1
print(r)
```

**重构后**：

```python
# module.py
def f(p):
    r = p + 1
    print(r)

f(2)
```

临时变量 `r` 会被正确处理，调用处只需传入参数。

### 处理临时变量名冲突

当函数内的临时变量名与调用处的变量名不同时，会自动处理：

**重构前**：

```python
# module.py
def f(p):
    a = p + 1
    print(a)

b = 2 + 1
print(b)
```

**重构后**：

```python
# module.py
def f(p):
    a = p + 1
    print(a)

f(2)
```

函数内的局部变量 `a` 不会被替换到调用处，这是正确的行为。

### 指定特定文件进行处理

```python
from rope.base.project import Project
from rope.refactor.usefunction import UseFunction

project = Project('.')
mod = project.get_resource('module.py')

# 只对特定文件进行处理
user = UseFunction(project, mod, offset)
changes = user.get_changes(resources=[mod])
project.do(changes)
```

## 错误处理

使用 `try-except` 捕获可能的错误：

```python
from rope.base import exceptions
from rope.refactor.usefunction import UseFunction

try:
    user = UseFunction(project, resource, offset)
    changes = user.get_changes()
    project.do(changes)
except exceptions.RefactoringError as e:
    print(f"重构失败: {e}")
```

常见的错误消息：

- `"Unresolvable name selected"`: 光标位置无法解析为有效的 Python 名称
- `"Use function works for global functions, only."`: 选择的不是全局函数
- `"Use function should not be used on generatorS."`: 函数是生成器
- `"usefunction: Function has more than one return statement."`: 函数有多个 return
- `"usefunction: return should be the last statement."`: return 不是最后一条语句
