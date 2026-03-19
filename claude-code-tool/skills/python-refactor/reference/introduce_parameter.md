# rope IntroduceParameter API 详细使用文档

## 1. 基本信息

- **API 完整路径**: `rope.refactor.introduce_parameter.IntroduceParameter`
- **类说明**: 将局部变量转换为函数参数。该重构会向函数添加新参数，并用该参数替换函数体内的所有引用。
- **源码位置**: `/Users/zhushanwen/GitApp/rope/rope/refactor/introduce_parameter.py`

```python
from rope.refactor.introduce_parameter import IntroduceParameter
```

## 2. 构造函数参数

```python
IntroduceParameter(project, resource, offset)
```

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `project` | `Project` | 是 | rope 项目对象 |
| `resource` | `Resource` | 是 | 要进行重构的文件资源对象 |
| `offset` | `int` | 是 | 指向要转换为参数的局部变量的偏移量 |

### 关键约束

- **必须在函数内部执行**: `offset` 指定的偏移量必须位于函数体内，否则会抛出 `RefactoringError`
- **必须是可解析的变量**: 偏移量指向的表达式必须能被 rope 解析为有效的 Python 对象，否则会抛出 `RefactoringError`

构造函数内部逻辑：

```python
# rope/refactor/introduce_parameter.py 第 37-52 行
def __init__(self, project, resource, offset):
    self.project = project
    self.resource = resource
    self.offset = offset
    self.pymodule = self.project.get_pymodule(self.resource)
    scope = self.pymodule.get_scope().get_inner_scope_for_offset(offset)
    if scope.get_kind() != "Function":
        raise exceptions.RefactoringError(
            "Introduce parameter should be performed inside functions"
        )
    self.pyfunction = scope.pyobject
    self.name, self.pyname = self._get_name_and_pyname()
    if self.pyname is None:
        raise exceptions.RefactoringError(
            "Cannot find the definition of <%s>" % self.name
        )
```

## 3. 常用方法

### get_changes(new_parameter)

生成引入参数的变更集合。

```python
def get_changes(self, new_parameter):
    """
    参数:
        new_parameter: str - 新参数的名称
    返回:
        ChangeSet - 包含所有代码变更的对象
    """
```

**工作原理**:

1. 读取函数定义信息 (`functionutils.DefinitionInfo`)
2. 将新参数添加到函数参数列表，使用默认值（原始表达式的值）
3. 替换函数体内所有对原始变量的引用为新参数名
4. 返回包含这些变更的 `ChangeSet`

**返回值处理**:

```python
# 获取变更后，可以选择预览或执行
changes = introducer.get_changes("new_param")

# 预览变更
print(changes.get_description())

# 执行变更
project.do(changes)
```

## 4. 使用场景

### 场景一：将局部变量转换为函数参数

当函数内部使用了某个局部变量，希望将该变量作为函数参数传入时使用。

**示例代码转换**:

```python
# 转换前
var = 1
def f():
    b = var

# 转换后 (使用 IntroduceParameter 将 var 转换为参数)
def f(var=var):
    b = var
```

### 场景二：处理属性访问

当函数内部访问对象的属性时，可以将该属性表达式转换为参数。

```python
# 转换前
class C(object):
    a = 10
c = C()
def f():
    b = c.a

# 转换后
def f(p1=c.a):
    b = p1
```

### 场景三：为类方法添加参数

可以在类的成员方法中使用此重构。

```python
# 转换前
var = 1
class C(object):
    def f(self):
        b = var

# 转换后
class C(object):
    def f(self, p1=var):
        b = p1
```

### 场景四：复杂表达式作为默认值

该重构的参数默认值可以是复杂的表达式。

```python
# 转换前
class A(object):
    var = None

class B(object):
    a = A()

b = B()
a = b.a

def f(a):
    x = b.a.var + a.var

# 转换后 (对 a.var 引入参数 p)
def f(p=b.a.var):
    x = p + p
```

## 5. 代码示例

### 示例一：基本用法

假设有以下文件 `example.py`：

```python
var = 1
def f():
    b = var
```

使用 rope 引入参数：

```python
from rope.base.project import Project
from rope.refactor.introduce_parameter import IntroduceParameter

# 创建项目
project = Project("/path/to/your/project")

# 获取文件资源
resource = project.get_resource("example.py")

# 读取文件内容，找到要转换的变量的偏移量
content = resource.read()
offset = content.rindex("var")  # 获取 var 的位置

# 创建 IntroduceParameter 对象
introducer = IntroduceParameter(project, resource, offset)

# 获取变更，将 var 转换为参数
changes = introducer.get_changes("new_param")

# 执行变更
project.do(changes)

# 关闭项目
project.close()
```

执行后的文件内容变为：

```python
var = 1
def f(new_param=var):
    b = new_param
```

### 示例二：使用属性访问

```python
from rope.base.project import Project
from rope.refactor.introduce_parameter import IntroduceParameter

project = Project("/path/to/project")
resource = project.get_resource("example.py")

# 写入测试代码
resource.write("""\
class C(object):
    a = 10
c = C()
def f():
    b = c.a
""")

# 获取 c.a 中 a 的偏移量
content = resource.read()
offset = content.rindex("a")

# 引入参数
introducer = IntroduceParameter(project, resource, offset)
changes = introducer.get_changes("p1")
project.do(changes)

print(resource.read())
# 输出:
# class C(object):
#     a = 10
# c = C()
# def f(p1=c.a):
#     b = p1

project.close()
```

### 示例三：为方法添加参数

```python
from rope.base.project import Project
from rope.refactor.introduce_parameter import IntroduceParameter

project = Project("/path/to/project")
resource = project.get_resource("example.py")

resource.write("""\
var = 1
class C(object):
    def f(self):
        b = var
""")

content = resource.read()
offset = content.rindex("var")

introducer = IntroduceParameter(project, resource, offset)
changes = introducer.get_changes("p1")
project.do(changes)

print(resource.read())
# 输出:
# var = 1
# class C(object):
#     def f(self, p1=var):
#         b = p1

project.close()
```

## 6. 常见错误

### 错误一：在函数外部执行

```python
# 代码
var = 10
b = var

# 错误用法
offset = content.rindex("var")
introducer = IntroduceParameter(project, resource, offset)
# RefactoringError: Introduce parameter should be performed inside functions
```

**解决方案**: 确保 `offset` 指向函数体内的代码。

### 错误二：变量无法解析

```python
# 代码
def f():
    b = var + c  # var 和 c 都未定义

# 错误用法
offset = content.rindex("var")
introducer = IntroduceParameter(project, resource, offset)
# RefactoringError: Cannot find the definition of <var>
```

**解决方案**: 确保要转换的变量是已定义的，可以被 rope 解析。

### 错误三：偏移量位置不正确

```python
# 如果 offset 指向的位置不是有效的变量引用
# 会导致解析失败
```

**解决方案**: 使用 `content.rindex("variable_name")` 或其他方式准确定位变量位置。

## 7. 注意事项

### 7.1 参数默认值

引入的参数会使用原始表达式的值作为默认值。这意味着：

- 如果原代码是 `var = 1; def f(): b = var`
- 转换后是 `def f(var=1): b = var`（默认值是表达式的值）

### 7.2 引用替换范围

该重构只会替换**同一函数体内**的引用，不会影响函数外的代码。

### 7.3 与 Extract Method 的区别

- **IntroduceParameter**: 将函数内的局部变量/表达式提取为函数参数
- **Extract Method**: 将代码片段提取为新方法

两者方向相反：Extract Method 是从函数内提取代码到外部，IntroduceParameter 是将外部变量引入到函数参数。

### 7.4 多次使用

可以对同一个函数多次使用 IntroduceParameter，每次引入一个参数。

```python
# 原始
a = 1
b = 2
def f():
    c = a + b

# 第一次引入参数 a
def f(a=a):
    c = a + b

# 第二次引入参数 b
def f(a=a, b=b):
    c = a + b
```

## 8. 相关类和方法

- `rope.base.project.Project`: rope 项目主类
- `rope.base.resources.File`: 文件资源类
- `rope.base.exceptions.RefactoringError`: 重构异常类
- `rope.refactor.functionutils.DefinitionInfo`: 函数定义信息工具类
- `rope.base.codeanalyze.ChangeCollector`: 代码变更收集器
