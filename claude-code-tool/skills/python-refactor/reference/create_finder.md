# rope create_finder API 详细使用文档

## 1. 基本信息

- **API 完整路径**: `rope.refactor.occurrences.create_finder`
- **函数说明**: 创建符号查找器，用于在项目中查找符号的所有引用。返回一个 `Finder` 对象，通过其 `find_occurrences` 方法可以遍历所有匹配的出现位置。
- **源码位置**: `/Users/zhushanwen/GitApp/rope/rope/refactor/occurrences.py`

```python
from rope.refactor.occurrences import create_finder
```

## 2. 函数签名与参数

```python
def create_finder(
    project,
    name,
    pyname,
    only_calls=False,
    imports=True,
    unsure=None,
    docs=False,
    instance=None,
    in_hierarchy=False,
    keywords=True,
):
```

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `project` | `Project` | 必填 | rope 项目对象 |
| `name` | `str` | 必填 | 要查找的符号名称 |
| `pyname` | `PyName` | 必填 | 符号对应的 PyName 对象，表示符号的定义 |
| `only_calls` | `bool` | `False` | 是否只查找函数/方法调用 |
| `imports` | `bool` | `True` | 是否包含 import 语句中的引用 |
| `unsure` | `Callable` | `None` | 一个函数，用于过滤不确定的引用 |
| `docs` | `bool` | `False` | 是否在文档字符串中查找 |
| `instance` | `ParameterName` | `None` | 用于处理隐式接口的场景 |
| `in_hierarchy` | `bool` | `False` | 是否查找类层次结构中的引用 |
| `keywords` | `bool` | `True` | 是否包含关键字参数形式的引用 |

### 参数详细说明

#### project
rope 项目对象，通过 `rope.base.project.Project` 创建。用于访问项目中的文件和进行代码分析。

#### name
要查找的符号名称字符串，例如函数名、变量名、类名等。

#### pyname
符号的 PyName 对象，表示符号的定义信息。可以通过 `PyModule.get_pyname()` 或 `NameFinder` 等方式获取。这个对象用于判断一个引用是否指向同一个符号。

#### only_calls
当设为 `True` 时，只返回函数/方法的调用位置，不包括定义、赋值等。这在你想查找某个函数被哪些地方调用时非常有用。

#### imports
当设为 `False` 时，排除 import 语句中的引用。当设为 `True`（默认值）时，包含 import 语句中的引用。

#### unsure
一个回调函数，接收 `Occurrence` 对象作为参数，返回 `True` 表示保留该不确定引用。这个参数用于处理无法确定引用目标的情况。

#### docs
当设为 `True` 时，查找范围会扩展到文档字符串中。默认只在代码正文中查找。

#### instance
当需要查找隐式接口实现时使用。通常是 `pynames.ParameterName` 类型，用于获取实例方法的不同实现。

#### in_hierarchy
当设为 `True` 时，会查找类层次结构中的所有引用。例如，查找一个父类方法的所有子类重写和调用。这对于重命名可能被继承的方法很有用。

#### keywords
当设为 `False` 时，排除作为关键字参数传递的引用。例如，`func(arg=value)` 中的 `value` 不会被匹配。

## 3. 返回值

返回 `Finder` 对象，具有以下属性和方法：

### 属性

| 属性 | 类型 | 说明 |
|------|------|------|
| `project` | `Project` | rope 项目对象 |
| `name` | `str` | 要查找的符号名称 |
| `docs` | `bool` | 是否在文档中查找 |
| `filters` | `list` | 过滤器列表 |

### 方法

#### find_occurrences(resource=None, pymodule=None)

生成并返回匹配的出现位置。

**参数：**
- `resource`: 资源对象，可选。如果指定，只在该文件中查找
- `pymodule`: PyModule 对象，可选。如果指定，使用该模块进行查找

**返回值：**
生成器，产生 `Occurrence` 对象

**Occurrence 对象的主要方法：**

| 方法 | 返回值 | 说明 |
|------|--------|------|
| `get_word_range()` | `tuple` | 获取符号的起止偏移量 |
| `get_pyname()` | `PyName` | 获取引用的 PyName |
| `get_primary_range()` | `tuple` | 获取主表达式的范围 |
| `is_in_import_statement()` | `bool` | 是否在 import 语句中 |
| `is_called()` | `bool` | 是否是函数调用 |
| `is_defined()` | `bool` | 是否是定义位置 |
| `is_written()` | `bool` | 是否被赋值 |
| `is_unsure()` | `bool` | 是否是不确定的引用 |
| `lineno` | `int` | 所在行号 |
| `resource` | `Resource` | 所在文件资源 |

## 4. 过滤器详解

`create_finder` 内部使用了多个过滤器来精确筛选引用。以下是所有可用的过滤器：

### CallsFilter

只保留函数/方法调用。适用于只想查找某个函数被哪些地方调用的情况。

```python
# 效果等同于 only_calls=True
filters.append(CallsFilter())
```

### InHierarchyFilter

查找类层次结构中的所有引用。当查找父类的方法时，会同时找到子类中的重写和调用。

```python
# 效果等同于 in_hierarchy=True
filters.append(InHierarchyFilter(pyname))
```

### UnsureFilter

保留不确定的引用。当代码中的引用无法确定具体指向哪个定义时（例如使用了动态类型），会被标记为"不确定"。

```python
# unsure 参数示例
def my_unsure_filter(occurrence):
    return True  # 保留所有不确定的引用

finder = create_finder(project, name, pyname, unsure=my_unsure_filter)
```

### NoImportsFilter

排除 import 语句中的引用。

```python
# 效果等同于 imports=False
filters.append(NoImportsFilter())
```

### NoKeywordsFilter

排除作为关键字参数传递的引用。

```python
# 效果等同于 keywords=False
filters.append(NoKeywordsFilter())
```

## 5. 使用场景

### 场景一：查找符号的所有引用

最基本的使用场景，查找某个符号在项目中的所有出现位置。

```python
from rope.base.project import Project
from rope.refactor.occurrences import create_finder

# 创建项目
project = Project('/path/to/your/project')

# 获取要查找的文件和位置
resource = project.get_resource('module.py')
pymodule = project.get_pymodule(resource)

# 假设我们要查找 'my_function' 的引用
# 首先需要获取该符号的 PyName
offset = 100  # 指向符号 'my_function' 的位置
pyname = pymodule.get_pyname_at(offset)
name = 'my_function'

# 创建 finder
finder = create_finder(project, name, pyname)

# 查找所有引用
for occurrence in finder.find_occurrences():
    print(f"文件: {occurrence.resource.path}, 行号: {occurrence.lineno}")
```

### 场景二：只查找函数调用

当你只想知道某个函数被哪些地方调用时，使用 `only_calls=True`。

```python
finder = create_finder(
    project,
    name='process_data',
    pyname=pyname,
    only_calls=True
)

# 只打印调用位置
for occurrence in finder.find_occurrences():
    if occurrence.is_called():
        print(f"调用位置: {occurrence.resource.path}:{occurrence.lineno}")
```

### 场景三：排除 import 语句

当你只想查找代码中的使用，而不关心 import 语句时。

```python
finder = create_finder(
    project,
    name='MyClass',
    pyname=pyname,
    imports=False  # 排除 import 语句
)

for occurrence in finder.find_occurrences():
    if not occurrence.is_in_import_statement():
        print(f"使用位置: {occurrence.resource.path}:{occurrence.lineno}")
```

### 场景四：查找类层次结构中的引用

重命名一个父类方法时，可能需要同时更新子类中的重写。

```python
finder = create_finder(
    project,
    name='BaseClass.method_name',
    pyname=pyname,
    in_hierarchy=True  # 包含子类中的重写
)

# 找到所有相关的引用，包括子类
for occurrence in finder.find_occurrences():
    print(f"引用: {occurrence.resource.path}:{occurrence.lineno}")
```

### 场景五：配合重命名使用

`create_finder` 常与重命名功能配合，用于预览重命名的影响。

```python
from rope.refactor.rename import Rename

# 创建 finder 查找所有引用
finder = create_finder(project, name, pyname)

# 预览所有引用
occurrences = list(finder.find_occurrences())
print(f"共找到 {len(occurrences)} 处引用")

# 执行重命名
rename = Rename(project, resource, offset)
changes = rename.get_changes('new_name')
project.do(changes)
```

### 场景六：分析代码依赖

可以使用 `create_finder` 来分析模块之间的依赖关系。

```python
def find_references_to_module(project, module_name):
    """查找对某个模块的所有引用"""
    resource = project.get_resource(module_name)
    if resource is None:
        return []

    pymodule = project.get_pymodule(resource)
    # 获取模块级别的 PyName
    module_pyname = pymodule.get_pyname()

    finder = create_finder(
        project,
        name=module_name,
        pyname=module_pyname,
        imports=True
    )

    references = []
    for occurrence in finder.find_occurrences():
        if occurrence.resource.path != module_name:
            references.append({
                'file': occurrence.resource.path,
                'line': occurrence.lineno
            })

    return references
```

## 6. 完整示例

### 示例一：基础用法

```python
from rope.base.project import Project
from rope.refactor.occurrences import create_finder

# 创建项目
project = Project('/path/to/project')

# 假设在 module.py 文件中，第 10 行定义了函数 foo
resource = project.get_resource('module.py')
pymodule = project.get_pymodule(resource)

# 获取函数的 PyName（假设函数在偏移量 100 处）
offset = 100
pyname = pymodule.get_pyname_at(offset)

# 获取函数名
name = 'foo'

# 创建 finder，查找所有引用
finder = create_finder(project, name, pyname)

# 遍历所有引用
print("'foo' 的所有引用：")
for occurrence in finder.find_occurrences():
    print(f"  {occurrence.resource.path}:{occurrence.lineno}")
```

### 示例二：高级用法 - 组合多个过滤条件

```python
from rope.base.project import Project
from rope.refactor.occurrences import create_finder

project = Project('/path/to/project')
resource = project.get_resource('my_module.py')
pymodule = project.get_pymodule(resource)

# 获取目标符号
offset = 200
pyname = pymodule.get_pyname_at(offset)
name = 'my_function'

# 创建高级 finder
# - 只查找函数调用
# - 排除 import 语句
# - 排除关键字参数
finder = create_finder(
    project,
    name=name,
    pyname=pyname,
    only_calls=True,
    imports=False,
    keywords=False
)

# 查找并分析引用
call_count = 0
for occurrence in finder.find_occurrences():
    if occurrence.is_called():
        call_count += 1
        print(f"调用: {occurrence.resource.path}:{occurrence.lineno}")

print(f"共找到 {call_count} 处调用")
```

### 示例三：在特定文件中查找

```python
from rope.base.project import Project
from rope.refactor.occurrences import create_finder

project = Project('/path/to/project')

# 获取主模块
main_resource = project.get_resource('main.py')
main_pymodule = project.get_pymodule(main_resource)

# 假设在 main.py 中定义了 Config 类
offset = 50
pyname = main_pymodule.get_pyname_at(offset)
name = 'Config'

# 创建 finder
finder = create_finder(project, name, pyname)

# 只在特定文件中查找
target_file = project.get_resource('utils.py')
for occurrence in finder.find_occurrences(resource=target_file):
    print(f"在 utils.py 中找到: 第 {occurrence.lineno} 行")
```

### 示例四：处理继承层次结构

```python
from rope.base.project import Project
from rope.refactor.occurrences import create_finder

project = Project('/path/to/project')

# 获取基类文件
base_resource = project.get_resource('base.py')
base_pymodule = project.get_pymodule(base_resource)

# 假设 Animal 类在偏移量 100 处
offset = 100
pyname = base_pymodule.get_pyname_at(offset)
name = 'Animal'

# 创建 finder，包含子类层次
finder = create_finder(
    project,
    name=name,
    pyname=pyname,
    in_hierarchy=True
)

# 查找 Animal 类及其所有子类的引用
print("Animal 类及其子类的所有引用：")
for occurrence in finder.find_occurrences():
    print(f"  {occurrence.resource.path}:{occurrence.lineno}")
```

## 7. 注意事项

1. **PyName 获取**：正确获取 `pyname` 是使用 `create_finder` 的关键。可以使用 `pymodule.get_pyname_at(offset)` 或 `NameFinder` 来获取。

2. **性能考虑**：在大型项目中，全项目搜索可能会比较慢。可以通过指定 `resource` 参数来限制搜索范围。

3. **不确定性引用**：Python 是动态类型语言，有些引用可能无法确定具体指向哪个定义。这些引用会通过 `is_unsure()` 方法被标记。

4. **文档字符串搜索**：`docs=True` 参数会显著增加搜索范围，因为文档字符串也会被搜索。

5. **过滤器组合**：`only_calls`、`imports`、`keywords` 等参数实际上是预设的过滤器组合，可以根据需要灵活调整。
