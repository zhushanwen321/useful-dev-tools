# rope create_inline API 详细使用文档

## 1. 基本信息

- **API 完整路径**: `rope.refactor.inline.create_inline`
- **函数说明**: 自动识别光标位置的代码元素，创建合适的内联重构对象。根据 `resource` 和 `offset` 的位置，自动返回 `InlineMethod`、`InlineVariable` 或 `InlineParameter` 的实例。
- **源码位置**: `/Users/zhushanwen/GitApp/rope/rope/refactor/inline.py`

```python
from rope.refactor.inline import create_inline
```

## 2. 函数参数

```python
create_inline(project, resource, offset)
```

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `project` | `Project` | 是 | rope 项目对象 |
| `resource` | `Resource` | 是 | 要进行内联重构的文件资源对象 |
| `offset` | `int` | 是 | 偏移量，指向要进行内联的元素位置 |

### 参数说明

- **project**: rope 项目对象，通过 `rope.base.project.Project` 创建
- **resource**: 文件资源对象，通常通过 `project.get_resource(path)` 获取
- **offset**: 光标在文件中的字符偏移量（从 0 开始）

### offset 参数的识别逻辑

`create_inline` 函数内部会根据光标位置的内容类型自动选择合适的内联类：

1. **函数定义** (`InlineMethod`): 当 `offset` 指向函数/方法定义时
2. **局部变量** (`InlineVariable`): 当 `offset` 指向局部变量赋值语句时（必须是单次赋值的变量）
3. **函数参数** (`InlineParameter`): 当 `offset` 指向函数参数时

具体判断逻辑如下：

```python
# inline.py 第 60-76 行
pyname = _get_pyname(project, resource, offset)
if isinstance(pyname, pynames.AssignedName):
    return InlineVariable(project, resource, offset)
if isinstance(pyname, pynames.ParameterName):
    return InlineParameter(project, resource, offset)
if pyname.get_object() is not None and isinstance(pyname.get_object(), pyobjects.PyFunction):
    return InlineMethod(project, resource, offset)
```

## 3. 返回值

返回以下三种类型之一：

| 返回类型 | 说明 |
|----------|------|
| `InlineMethod` | 内联方法/函数调用 |
| `InlineVariable` | 内联局部变量 |
| `InlineParameter` | 内联函数参数 |

### 3.1 InlineMethod

用于将函数调用内联到调用处，并可选择删除原函数定义。

**主要方法：**

```python
def get_changes(
    self,
    remove=True,           # 是否删除原函数定义
    only_current=False,    # 是否只内联当前文件中的调用
    resources=None,         # 要处理的文件列表
    task_handle=taskhandle.DEFAULT_TASK_HANDLE
)
```

**get_kind()**: 返回 `"method"`

### 3.2 InlineVariable

用于将局部变量内联到其使用位置。

**主要方法：**

```python
def get_changes(
    self,
    remove=True,           # 是否删除原变量定义
    only_current=False,    # 是否只内联当前文件中的使用
    resources=None,         # 要处理的文件列表
    docs=False,            # 是否保留文档字符串
    task_handle=taskhandle.DEFAULT_TASK_HANDLE
)
```

**限制**: 局部变量必须只被赋值一次才能进行内联。

**get_kind()**: 返回 `"variable"`

### 3.3 InlineParameter

用于内联函数参数，实际效果是将参数默认值内联到所有调用处。

**主要方法：**

```python
def get_changes(self, **kwds)
```

调用 `ChangeSignature.get_changes()` 方法，参数传递给它。

**get_kind()**: 返回 `"parameter"`

## 4. 使用场景

### 4.1 内联方法调用

当需要将函数调用替换为函数体内容时使用：

**重构前：**
```python
def greet(name):
    return f"Hello, {name}!"

message = greet("World")
```

**重构后：**
```python
message = f"Hello, World!"
```

### 4.2 内联变量

当局部变量只是简单赋值，没有必要单独定义时使用：

**重构前：**
```python
x = 10
result = x * 2
```

**重构后：**
```python
result = 10 * 2
```

### 4.3 内联参数

当函数参数有默认值，且所有调用都传递了该参数时，可以将默认值内联到调用处：

**重构前：**
```python
def greet(name, greeting="Hello"):
    return f"{greeting}, {name}!"

greet("Alice", "Hi")
```

**重构后：**
```python
def greet(name):
    return f"Hello, {name}!"

greet("Alice")  # 或直接替换为 "Hello, Alice!"
```

## 5. 代码示例

### 5.1 基本使用流程

```python
from rope.base.project import Project
from rope.refactor.inline import create_inline

# 创建项目
project = Project('/path/to/your/project')

# 获取文件资源
resource = project.get_resource('example.py')

# 假设 example.py 内容如下：
# def double(x):
#     return x * 2
#
# result = double(5)

# 要内联 double 函数，需要获取函数名的位置偏移
# 假设函数定义在第1行第0个字符开始
# 我们需要找到 double 的位置

# 方法一：直接指定偏移量（需要手动计算）
# offset = 4  # "def " 后面就是 "double"

# 方法二：使用 TextOffset 获取
from rope.base import libutils
offset = libutils.TextOffset(resource, 4)

# 创建内联重构对象
inline_refactor = create_inline(project, resource, offset)

# 获取更改
changes = inline_refactor.get_changes()

# 应用更改
project.do(changes)

# 关闭项目
project.close()
```

### 5.2 完整示例：内联变量

```python
from rope.base.project import Project
from rope.refactor.inline import create_inline

# 创建项目
project = Project('/path/to/your/project')

# 示例代码文件内容
# x = 10
# y = x + 5
# print(y)

# 假设我们要内联变量 x
# x 的定义在第1行，偏移量约为 0
# 我们可以使用行号计算偏移量

# 获取资源
resource = project.get_resource('example.py')
source = resource.read()

# 找到变量 x 的位置（假设在文件开头）
# 手动计算：第二行 "y = x + 5" 中的 x 需要偏移到变量定义处
# 这里我们直接用变量定义的位置

# 创建一个包含示例代码的文件
import tempfile
import os

with tempfile.TemporaryDirectory() as tmpdir:
    test_file = os.path.join(tmpdir, 'test.py')
    with open(test_file, 'w') as f:
        f.write("""x = 10
y = x + 5
print(y)
""")

    # 创建新项目
    project = Project(tmpdir)
    resource = project.get_resource('test.py')

    # 获取变量 x 定义的位置偏移
    # "x = 10" 从第 0 个字符开始
    offset = 0

    # 创建内联重构对象
    inline_refactor = create_inline(project, resource, offset)

    print(f"内联类型: {inline_refactor.get_kind()}")

    # 获取更改
    changes = inline_refactor.get_changes()

    # 打印更改
    for change in changes.changes:
        print(f"文件: {change.new_contents}")

    # 应用更改
    project.do(changes)

    # 验证结果
    with open(test_file, 'r') as f:
        print("重构后文件内容:")
        print(f.read())

    project.close()
```

### 5.3 完整示例：内联方法

```python
import tempfile
import os
from rope.base.project import Project
from rope.refactor.inline import create_inline

with tempfile.TemporaryDirectory() as tmpdir:
    test_file = os.path.join(tmpdir, 'test.py')
    with open(test_file, 'w') as f:
        f.write("""def add(a, b):
    return a + b

result = add(1, 2)
print(result)
""")

    project = Project(tmpdir)
    resource = project.get_resource('test.py')

    # 找到函数名 add 的位置
    # "def add(a, b):" 从第 4 个字符开始
    offset = 4

    inline_refactor = create_inline(project, resource, offset)

    print(f"内联类型: {inline_refactor.get_kind()}")

    # 只内联当前文件，不删除原函数定义
    changes = inline_refactor.get_changes(remove=True)

    for change in changes.changes:
        print("重构后的文件内容:")
        print(change.new_contents)

    project.do(changes)
    project.close()

    with open(test_file, 'r') as f:
        print("\n最终文件内容:")
        print(f.read())
```

### 5.4 实际项目中使用

```python
import os
from rope.base.project import Project
from rope.refactor.inline import create_inline
from rope.base import libutils

# 项目路径
project_path = '/your/project/path'

# 创建项目（带fscommands支持更好的文件操作）
project = Project(project_path)

# 要处理的文件
file_path = 'src/utils.py'
resource = project.get_resource(file_path)

# 读取文件找到目标位置
source = resource.read()

# 假设我们要内联 get_name 函数
# 找到 "def get_name" 中 get_name 的偏移量
# 可以通过搜索字符串位置
offset = source.index('def get_name') + 4  # +4 跳过 "def "

# 创建内联重构
inline_obj = create_inline(project, resource, offset)

# 打印内联类型
print(f"将要执行的内联类型: {inline_obj.get_kind()}")

# 执行内联
if inline_obj.get_kind() == 'method':
    # 内联方法
    changes = inline_obj.get_changes(remove=True)
elif inline_obj.get_kind() == 'variable':
    # 内联变量
    changes = inline_obj.get_changes(remove=True)
else:
    # 内联参数
    changes = inline_obj.get_changes()

# 应用更改
project.do(changes)

print("内联重构完成！")

# 关闭项目
project.close()
```

## 6. 注意事项

### 6.1 已知问题

源码中注释说明了内联函数时存在的已知问题：

1. **参数重赋值问题**: 如果函数内部对参数进行了重赋值，直接内联可能导致结果错误

   ```python
   def foo(var1):
       var1 = var1 * 10  # 这里重赋值了参数
       return var1

   # 调用 foo(20) 内联后结果是 20，但应该是 200
   ```

2. **表达式求值问题**: 传递表达式作为参数时，内联结果可能不正确

   ```python
   def foo(var1):
       var2 = var1 * 10
       return var2

   # 调用 foo(10+10) 内联后结果是 110，但应该是 200
   ```

### 6.2 使用限制

- **InlineVariable**: 局部变量必须只被赋值一次
- **InlineMethod**: 不能内联递归调用的函数
- **InlineMethod**: 不能内联包含 `*args` 或 `**kwargs` 的函数

### 6.3 最佳实践

1. **先预览再应用**: 总是先调用 `get_changes()` 查看修改内容，确认无误后再调用 `project.do(changes)`
2. **备份文件**: 对于重要文件，建议先进行版本控制或备份
3. **分步骤执行**: 对于复杂代码，先在小范围内测试（如使用 `only_current=True`）

## 7. 相关 API

- `rope.refactor.inline.InlineMethod`: 方法内联
- `rope.refactor.inline.InlineVariable`: 变量内联
- `rope.refactor.inline.InlineParameter`: 参数内联
- `rope.refactor.rename.Rename`: 重命名重构
- `rope.refactor.extract.ExtractMethod`: 提取方法
- `rope.refactor.extract.ExtractVariable`: 提取变量
