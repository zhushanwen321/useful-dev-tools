# ExtractVariable

## 基本信息

- **API 完整路径**: `rope.refactor.extract.ExtractVariable`
- **模块**: `rope.refactor.extract`
- **类说明**: 将选中的表达式提取为变量。该重构功能会将代码中选中的表达式提取到一个新的变量中，并用该变量替换原来的表达式位置，从而提高代码的可读性和可维护性。

## 继承关系

```
ExtractVariable
    └── _ExtractRefactoring
```

`ExtractVariable` 继承自 `_ExtractRefactoring` 基类，提供了变量提取的核心功能。

## 构造函数

```python
ExtractVariable(project, resource, start_offset, end_offset)
```

### 参数说明

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `project` | `Project` | 是 | rope 项目对象，用于访问项目资源和代码分析功能 |
| `resource` | `Resource` | 是 | 要进行重构的文件资源对象（如 `File` 对象） |
| `start_offset` | `int` | 是 | 选中表达式的起始偏移量（字符索引，从 0 开始） |
| `end_offset` | `int` | 是 | 选中表达式的结束偏移量（字符索引） |

### 偏移量说明

- 偏移量是基于文件内容的字符位置
- `start_offset` 指向要提取表达式的第一个字符位置
- `end_offset` 指向要提取表达式的最后一个字符之后的位置
- rope 会自动处理边界处的空白字符

## 常用方法

### get_changes()

```python
get_changes(extracted_name, similar=False, global_=False, kind=None)
```

执行提取变量重构并返回变更集合。

#### 参数说明

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `extracted_name` | `str` | 必填 | 提取后变量的名称 |
| `similar` | `bool` | `False` | 是否替换相似的表达式。如果为 `True`，会自动查找并替换代码中所有与选中表达式相似的表达式 |
| `global_` | `bool` | `False` | 是否将提取的变量定义为全局变量。如果为 `True`，变量将被提取到模块级别 |
| `kind` | `str` | `None` | 目标类型（主要用于 ExtractMethod，ExtractVariable 中较少使用） |

#### 返回值

返回 `ChangeSet` 对象，包含对文件的修改内容。

#### 使用示例

```python
# 基本用法
extractor = ExtractVariable(project, resource, start, end)
changes = extractor.get_changes("new_variable_name")
changes.apply()  # 应用变更
```

### 获取偏移量的方法

在实际使用中，通常需要确定要提取的表达式的位置。以下是一些常用的方法：

1. **使用行号和列号计算偏移量**:
   ```python
   from rope.base.project import File

   resource = project.get_resource('example.py')
   content = resource.read()
   # 计算第 5 行第 10 列的偏移量
   lines = content.split('\n')
   offset = sum(len(lines[i]) + 1 for i in range(4)) + 9  # 第 5 行从 index 4 开始，第 10 列从 index 9 开始
   ```

2. **使用 rope 内置的文本搜索**:
   ```python
   content = resource.read()
   start = content.index('expression_to_extract')
   end = start + len('expression_to_extract')
   ```

## 使用场景

### 1. 提取复杂表达式

将复杂的计算表达式提取为变量，使代码更易读：

```python
# 重构前
result = (user.age + 10) * 2 - calculate_discount(user.membership) / 100

# 重构后
discount_factor = user.membership / 100
discount = calculate_discount(discount_factor)
age_bonus = (user.age + 10) * 2
result = age_bonus - discount
```

### 2. 消除重复计算

当同一表达式在代码中多次出现时，提取为变量可以避免重复计算：

```python
# 重构前
if user.authenticated and user.has_permission('read'):
    print(user.authenticated and user.has_permission('read'))

# 重构后（使用 similar=True）
has_access = user.authenticated and user.has_permission('read')
if has_access:
    print(has_access)
```

### 3. 提高嵌套表达式的可读性

处理多层嵌套的条件表达式：

```python
# 重构前
return user.is_active and (user.role == 'admin' or (user.role == 'editor' and user.can_edit))

# 重构后
is_admin = user.role == 'admin'
is_editor = user.role == 'editor'
can_edit_as_editor = is_editor and user.can_edit
is_privileged = is_admin or can_edit_as_editor
return user.is_active and is_privileged
```

## 代码示例

### 示例 1: 基本的变量提取

```python
from rope.base.project import Project
from rope.refactor.extract import ExtractVariable

# 创建项目
project = Project('.')

# 获取要修改的文件
resource = project.get_resource('example.py')
content = resource.read()
print("原始内容:")
print(content)

# 假设我们要提取 "1 + 2" 这个表达式
# 首先需要找到它的偏移量
source = "result = 1 + 2\nprint(result)"
start = source.index("1 + 2")
end = start + len("1 + 2")

# 创建提取器
extractor = ExtractVariable(project, resource, start, end)

# 执行提取，指定变量名
changes = extractor.get_changes("sum_value")

# 查看变更
print("\n变更描述:")
print(changes.get_description())

# 应用变更
changes.apply()

# 验证结果
new_content = resource.read()
print("\n重构后的内容:")
print(new_content)

# 清理项目
project.close()
```

### 示例 2: 使用 similar 参数替换相似表达式

```python
from rope.base.project import Project
from rope.refactor.extract import ExtractVariable

project = Project('.')
resource = project.get_resource('example.py')

# 源文件内容示例:
# x = a + b
# y = a + b
# z = x + a + b

# 提取第一个 "a + b"
source = "x = a + b\ny = a + b\nz = x + a + b"
start = source.index("a + b")
end = start + len("a + b")

extractor = ExtractVariable(project, resource, start, end)

# 使用 similar=True 替换所有相似的表达式
changes = extractor.get_changes("ab_sum", similar=True)
changes.apply()

# 结果:
# ab_sum = a + b
# x = ab_sum
# y = ab_sum
# z = x + ab_sum

project.close()
```

### 示例 3: 完整的交互式示例

```python
import rope.base.project
from rope.refactor.extract import ExtractVariable

# 创建项目
project = rope.base.project.Project('/path/to/your/project')

# 获取文件
filename = 'sample.py'
resource = project.get_resource(filename)

# 读取文件内容
content = resource.read()
print("原始文件内容:")
print(content)
print("-" * 40)

# 方式1: 手动指定偏移量
# 假设我们要提取第 2 行的 "10 + 20" 表达式
source_lines = content.split('\n')
# 找到 "10 + 20" 在第几行
target_line = None
for i, line in enumerate(source_lines):
    if '10 + 20' in line:
        target_line = i
        break

if target_line is not None:
    # 计算偏移量
    line_start = sum(len(source_lines[j]) + 1 for j in range(target_line))
    expr_start = source_lines[target_line].index('10 + 20')
    start_offset = line_start + expr_start
    end_offset = start_offset + len('10 + 20')

    print(f"提取表达式: 10 + 20")
    print(f"起始偏移量: {start_offset}, 结束偏移量: {end_offset}")

    # 执行提取
    extractor = ExtractVariable(project, resource, start_offset, end_offset)
    changes = extractor.get_changes('computed_value')

    print("\n变更内容:")
    print(changes.get_description())

    # 应用变更
    changes.apply()

    # 验证
    print("\n重构后的文件内容:")
    print(project.get_resource(filename).read())

# 清理
project.close()
```

### 示例 4: 在测试中使用

```python
import unittest
from rope.base.project import Project
from rope.refactor.extract import ExtractVariable

class TestExtractVariable(unittest.TestCase):
    def setUp(self):
        self.project = Project('.')
        # 创建测试文件
        self.test_file = 'test_extract.py'
        with open(self.test_file, 'w') as f:
            f.write("result = (1 + 2) * 3\n")

    def tearDown(self):
        # 清理测试文件
        import os
        if os.path.exists(self.test_file):
            os.remove(self.test_file)
        self.project.close()

    def test_extract_basic(self):
        resource = self.project.get_resource(self.test_file)
        source = resource.read()

        # 提取 "(1 + 2)"
        start = source.index("(1 + 2)")
        end = start + len("(1 + 2)")

        extractor = ExtractVariable(self.project, resource, start, end)
        changes = extractor.get_changes("temp_value")

        # 验证变更
        self.assertIn("temp_value", changes.get_description())
        changes.apply()

        # 验证结果
        new_content = resource.read()
        self.assertIn("temp_value = (1 + 2)", new_content)
        self.assertIn("result = temp_value * 3", new_content)

if __name__ == '__main__':
    unittest.main()
```

## 注意事项

1. **偏移量计算**: 使用 rope 的 `TextChange` 或其他 API 来获取精确的偏移量通常更可靠，手动计算可能因特殊字符（如制表符、Unicode 字符）而出错。

2. **作用域**: 提取的变量会被放置在适当的作用域中（函数内、类内或模块级），取决于选中表达式的位置。

3. **similar 参数**: 使用 `similar=True` 时要小心，因为它会自动修改代码中所有相似的表达式，可能会引入意外的更改。

4. **错误处理**: 如果选中的表达式无法被提取（例如在某些特殊语法上下文中），rope 会抛出 `RefactoringError` 异常。

5. **批量操作**: 对于多个文件的批量重构，可以创建多个 `ExtractVariable` 实例并分别调用 `get_changes()`，但要注意正确管理项目资源。

## 相关 API

- `rope.refactor.extract.ExtractMethod`: 提取为方法
- `rope.refactor.inline`: 内联变量/函数
- `rope.refactor.rename`: 重命名变量
- `rope.base.project.Project`: 项目对象
