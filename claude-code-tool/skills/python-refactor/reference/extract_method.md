# ExtractMethod

## 基本信息

- **API 完整路径**: `rope.refactor.extract.ExtractMethod`
- **模块**: `rope.refactor.extract`
- **类说明**: 将选中的代码片段提取为独立的方法。该重构功能会自动分析选中代码的依赖变量，将其作为参数传递，并创建新的方法来封装提取的代码逻辑。这是重构中常用的技术，用于简化过长函数、消除重复代码。

## 继承关系

```
ExtractMethod
    └── _ExtractRefactoring
```

`ExtractMethod` 继承自 `_ExtractRefactoring` 基类，提供了方法提取的核心功能。

## 构造函数

```python
ExtractMethod(project, resource, start_offset, end_offset)
```

### 参数说明

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `project` | `Project` | 是 | rope 项目对象，用于访问项目资源和代码分析功能 |
| `resource` | `Resource` | 是 | 要进行重构的文件资源对象（如 `File` 对象） |
| `start_offset` | `int` | 是 | 选中代码的起始偏移量（字符索引，从 0 开始） |
| `end_offset` | `int` | 是 | 选中代码的结束偏移量（字符索引） |

### 偏移量说明

- 偏移量是基于文件内容的字符位置
- `start_offset` 指向要提取代码的第一个字符位置
- `end_offset` 指向要提取代码的最后一个字符之后的位置
- rope 会自动处理边界处的空白字符

### 获取偏移量的方法

可以使用 `rope.base.codeanalyze.SourceLinesAdapter` 来转换行号为偏移量：

```python
from rope.base import codeanalyze

lines = codeanalyze.SourceLinesAdapter(source_code)
start_offset = lines.get_line_start(start_line)  # 第 start_line 行的起始位置
end_offset = lines.get_line_end(end_line)        # 第 end_line 行的结束位置
```

## 常用方法

### get_changes()

```python
get_changes(extracted_name, similar=False, global_=False, kind=None)
```

执行提取方法重构并返回变更集合。

#### 参数说明

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `extracted_name` | `str` | 必填 | 新方法的名字 |
| `similar` | `bool` | `False` | 是否替换所有相似的代码片段 |
| `global_` | `bool` | `False` | 是否将提取的方法设为全局函数 |
| `kind` | `str` | `None` | 方法类型，可选值：`"function"`、`"method"`、`"staticmethod"`、`"classmethod"` |

#### 返回值

返回 `ChangeSet` 对象，包含文件内容的变更。

#### 方法名前缀特殊语法

可以通过方法名前缀指定方法类型：

- `$method_name` - 提取为静态方法（staticmethod）
- `@method_name` - 提取为类方法（classmethod）

示例：
```python
# 提取为静态方法
extractor.get_changes("$calculate")

# 提取为类方法
extractor.get_changes("@process")
```

## 使用场景

### 场景一：将重复代码提取为独立方法

当代码中存在重复的代码片段时，可以将重复部分提取为独立方法：

```python
# 原始代码
def process_data(data):
    # 数据验证
    if not data:
        raise ValueError("数据不能为空")
    if len(data) > 1000:
        raise ValueError("数据量过大")

    # 数据处理
    result = []
    for item in data:
        result.append(item * 2)
    return result

def process_other(other_data):
    # 重复的数据验证
    if not other_data:
        raise ValueError("数据不能为空")
    if len(other_data) > 1000:
        raise ValueError("数据量过大")

    # 其他处理
    return [item + 1 for item in other_data]
```

使用 ExtractMethod 将重复的验证逻辑提取为 `validate_data` 方法。

### 场景二：简化过长函数

当一个函数过长、承担了过多职责时，可以将其中的部分逻辑提取为独立方法：

```python
# 原始代码
def generate_report(data, format_type):
    # 数据收集
    collected = []
    for item in data:
        collected.append({
            'id': item.id,
            'name': item.name,
            'value': item.value
        })

    # 数据排序
    sorted_data = sorted(collected, key=lambda x: x['name'])

    # 格式化输出
    if format_type == 'json':
        return json.dumps(sorted_data)
    elif format_type == 'csv':
        lines = [','.join(str(v) for v in row.values()) for row in sorted_data]
        return '\n'.join(lines)
    else:
        return str(sorted_data)
```

可以将数据收集、数据排序、格式化输出分别提取为独立方法。

## similar 参数详解

`similar` 参数控制是否替换代码中与选中部分相似的其他代码。

### similar=False（默认）

只替换用户选中的代码部分：

```python
code = """
a = 1
b = 1
"""

# 选中第一个 "1" 并提取
extractor = ExtractMethod(project, resource, start, start + 1)
changes = extractor.get_changes("one", similar=False)
# 结果: a = one()  /  b = 1 (未改变)
```

### similar=True

替换所有与选中代码相似的部分：

```python
code = """
a = 1
b = 1
"""

# 选中第一个 "1" 并提取
extractor = ExtractMethod(project, resource, start, start + 1)
changes = extractor.get_changes("one", similar=True)
# 结果: a = one()  /  b = one() (全部替换)
```

### 相似性判断规则

- 相同的字面量值（如数字、字符串）
- 相同的表达式结构
- 相同的语句结构

## 代码示例

### 完整示例：从模块文件中提取方法

```python
from rope.base.project import Project
from rope.base import libutils
from rope.refactor.extract import ExtractMethod

# 创建项目
project = Project('path/to/your/project')

# 获取要重构的文件
resource = project.get_resource('module.py')

# 读取文件内容确定偏移量
source_code = resource.read()
print(f"原始代码:\n{source_code}")

# 假设我们要提取第 2-3 行（打印语句）
# 方法1：使用行号转换
from rope.base import codeanalyze
lines = codeanalyze.SourceLinesAdapter(source_code)
start_offset = lines.get_line_start(2)  # 第2行起始
end_offset = lines.get_line_end(3)      # 第3行结束

# 方法2：直接指定字符偏移量
# start_offset = 30
# end_offset = 60

# 创建提取器
extractor = ExtractMethod(project, resource, start_offset, end_offset)

# 获取变更（将提取的方法命名为 "extracted"）
changes = extractor.get_changes("extracted")

# 应用变更
project.do(changes)

# 查看变更后的代码
new_code = resource.read()
print(f"变更后的代码:\n{new_code}")

# 关闭项目
project.close()
```

### 完整示例：使用相似代码替换

```python
from rope.base.project import Project
from rope.refactor.extract import ExtractMethod

project = Project('path/to/your/project')
resource = project.get_resource('example.py')

source_code = resource.read()
# 原始代码:
# a = 1 + 2
# b = 1 + 2

# 选中第一个 "1 + 2" 表达式
start = source_code.index("1 + 2")
end = start + len("1 + 2")

extractor = ExtractMethod(project, resource, start, end)

# similar=True: 替换所有相似表达式
changes = extractor.get_changes("calculate", similar=True)
project.do(changes)

# 结果:
# a = calculate()
# b = calculate()
#
# def calculate():
#     return 1 + 2

project.close()
```

### 完整示例：提取为类方法

```python
from rope.base.project import Project
from rope.refactor.extract import ExtractMethod

project = Project('path/to/your/project')
resource = project.get_resource('myclass.py')

source_code = resource.read()
"""
class MyClass:
    def process(self):
        result = 10 * 5
        return result
"""

# 选中 "10 * 5"
start = source_code.index("10 * 5")
end = start + len("10 * 5")

extractor = ExtractMethod(project, resource, start, end)

# 提取为类方法（默认行为，在类内部会自动成为实例方法）
changes = extractor.get_changes("calculate")
project.do(changes)

# 结果:
# class MyClass:
#     def process(self):
#         result = self.calculate()
#         return result
#
#     def calculate(self):
#         return 10 * 5

project.close()
```

### 完整示例：提取为静态方法

```python
# 方式1：使用 kind 参数
changes = extractor.get_changes("calculate", kind="staticmethod")

# 方式2：使用前缀语法（推荐）
changes = extractor.get_changes("$calculate")
# 结果: MyClass.$calculate() -> MyClass.calculate()（静态方法）
```

## 常见问题

### Q1: 提取方法时如何确定偏移量？

**答**：可以使用 `rope.base.codeanalyze.SourceLinesAdapter` 将行号转换为偏移量：

```python
from rope.base import codeanalyze

lines = codeanalyze.SourceLinesAdapter(source_code)
start = lines.get_line_start(行号)
end = lines.get_line_end(行号)
```

### Q2: 为什么提取的方法包含我不想要的变量？

**答**：rope 会自动分析选中代码中使用的变量，并将需要传入的变量作为参数。如果某些变量不应该被传入，可以考虑先提取相关代码再进行调整。

### Q3: similar=True 没有替换相似的代码怎么办？

**答**：确保选中的代码片段足够具体，rope 使用结构相似性来判断。如果相似代码位于不同的作用域，可能不会被替换。

### Q4: 提取方法后原来的代码报错怎么办？

**答**：检查是否是因为变量作用域问题。提取的方法无法访问原函数中的局部变量，需要通过参数传入。

### Q5: 如何提取为全局函数而不是类方法？

**答**：将 `global_` 参数设为 `True`：

```python
changes = extractor.get_changes("my_function", global_=True)
```

### Q6: 提取方法时如何处理返回值？

**答**：如果选中的代码包含返回值语句，rope 会自动将提取的代码改为返回值形式。例如：

```python
# 选中 "a + b"
# 会自动提取为:
def new_method(a, b):
    return a + b

# 原位置变为:
result = new_method(a, b)
```

### Q7: 构造函数参数中的 `project` 和 `resource` 从哪里获取？

**答**：

```python
from rope.base.project import Project

# 创建项目
project = Project('path/to/project')

# 获取资源（文件）
resource = project.get_resource('filename.py')

# 或者创建新文件
resource = libutils.new_file(project, 'newmodule.py')
```

### Q8: get_changes() 返回的 ChangeSet 如何使用？

**答**：

```python
changes = extractor.get_changes("method_name")

# 查看变更内容
print(changes.get_description())

# 应用变更到项目
project.do(changes)

# 如果想撤销
project.undo()
```

## 注意事项

1. **偏移量边界**：确保 `start_offset` 和 `end_offset` 正确对应要提取的代码区域
2. **变量依赖**：rope 会自动分析并传递需要的变量作为参数
3. **返回值处理**：如果选中的代码有返回值，会自动添加 return 语句
4. **方法位置**：提取的方法会放置在合适的位置（同类中或模块级）
5. **错误处理**：如果选中的代码无法提取（如跨作用域变量依赖），会抛出异常
