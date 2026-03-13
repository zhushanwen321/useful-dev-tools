# Rope API 代码示例

详细代码示例，供参考。SKILL.md 中的速查表格已包含足够信息，此文件用于深入了解用法。

## 基础设置

```python
from rope.base.project import Project
from rope.base.libutils import path_to_resource

project = Project('/path/to/project')
resource = path_to_resource(project, 'path/to/file.py')
```

## 重命名 (Rename)

```python
from rope.refactor.rename import Rename

# 重命名代码符号
renamer = Rename(project, resource, offset)
changes = renamer.get_changes('new_name')

# 重命名模块文件（需要 VCS）
renamer = Rename(project, resource, offset=None)
changes = renamer.get_changes('new_module')
```

## 移动 (Move)

```python
from rope.refactor.move import MoveModule, create_move

# 移动模块
mover = MoveModule(project, resource)
changes = mover.get_changes(destination_folder)

# 移动方法/全局（自动选择类型）
mover = create_move(project, resource, offset)
```

## 提取 (Extract)

```python
from rope.refactor.extract import ExtractMethod, ExtractVariable

# 提取方法
extractor = ExtractMethod(project, resource, start, end)
changes = extractor.get_changes('method_name', similar=True)

# 提取变量
extractor = ExtractVariable(project, resource, start, end)
```

## 内联 (Inline)

```python
from rope.refactor.inline import create_inline

inliner = create_inline(project, resource, offset)
changes = inliner.get_changes(remove=True)
```

## 改变签名 (Change Signature)

```python
from rope.refactor.change_signature import ChangeSignature, ArgumentAdder

changer = ChangeSignature(project, resource, offset)
changes = changer.get_changes([ArgumentAdder(1, 'new_param')])
```

## 封装字段 / 引入工厂 / 引入参数

```python
from rope.refactor.encapsulate_field import EncapsulateField
from rope.refactor.introduce_factory import IntroduceFactory
from rope.refactor.introduce_parameter import IntroduceParameter

# 封装字段
encapsulator = EncapsulateField(project, resource, offset)

# 引入工厂
factory = IntroduceFactory(project, resource, offset)

# 引入参数
introducer = IntroduceParameter(project, resource, offset)
```

## 重构结构 (Restructure)

```python
from rope.refactor.restructure import Restructure

pattern = "${obj}.old_method(${param})"
goal = "new_method(${obj}, ${param})"
restructuring = Restructure(project, pattern, goal)
```

## 导入管理

```python
from rope.refactor.importutils import ImportOrganizer

organizer = ImportOrganizer(project)
changes = organizer.organize_imports(resource)
```

## 查找引用 (Occurrences)

```python
from rope.refactor.occurrences import create_finder, CallsFilter

finder = create_finder(project, resource, offset)
for occ in finder.find_occurrences():
    print(occ.resource.path, occ.offset)

# 只查找调用位置
finder = create_finder(project, resource, offset, filters=[CallsFilter()])
```

## 撤销/重做

```python
project.history.undo()
project.history.redo()
```
