---
name: python-refactor
description: 使用 rope 库编写 Python 代码重构脚本。支持重命名、移动、提取、内联、改变签名、封装字段、引入工厂、导入管理、撤销/重做等操作。触发词：「重构」、「使用 rope」、「重命名」、「移动模块」、「提取方法」、「内联变量」、「批量重构」等。
---

# Python Refactor Skill

使用 rope 库编写安全、可靠的 Python 代码重构脚本。

## 核心规则 - 最高优先级

### 重构决策流程（必须严格遵循）

```
1. 收到重构需求
       ↓
2. 查找 rope API：在本文档"完整 API 列表"或 references/rope-docs/ 中查找对应操作
       ↓
3. 找到 API？
   ├── 是 → 使用 rope API 实现重构 → 结束
   └── 否 → 查阅 references/rope-docs/overview.rst 确认是否支持
                ↓
           文档确认不支持？
           ├── 否 → 继续尝试 rope 方法
           └── 是 → 只有此时才能使用非 rope 方法，且必须向用户说明原因
```

### 绝对禁止（无例外）

以下方法**永远禁止**用于 Python 代码重构，无论任何情况：

| 禁止的方法 | 原因 |
|-----------|------|
| `re.sub()` / 正则表达式 | 无法区分代码、字符串、注释 |
| `str.replace()` | 会误改无关的同名文本 |
| `shutil.move()` 移动 .py 文件 | 不会更新导入语句 |
| 手动解析 AST 后修改代码 | rope 已封装，重复造轮子 |
| 直接 `open()` 读写代码文件 | 绕过 rope 的语义分析 |

### rope 必用 API

| 重构类型 | 必须使用的 rope API |
|---------|-------------------|
| 重命名 | `rope.refactor.rename.Rename` |
| 移动模块 | `rope.refactor.move.MoveModule` |
| 提取方法 | `rope.refactor.extract.ExtractMethod` |
| 内联 | `rope.refactor.inline.create_inline` |
| 改变签名 | `rope.refactor.change_signature.ChangeSignature` |
| 组织导入 | `rope.refactor.importutils.ImportOrganizer` |

### 遇到问题时的处理顺序

1. **先查本地文档**：`references/rope-docs/overview.rst` 有所有操作的示例
2. **再查 API 文档**：`references/rope-docs/library.rst` 有详细用法
3. **查已知限制**：本文档"关键限制"章节列出了 rope 的边界
4. **最后才考虑非 rope 方法**：必须先向用户说明"rope 不支持此操作，原因：..."

### 使用非 rope 方法的前置条件

只有同时满足以下条件，才能使用非 rope 方法：

- [ ] 已查阅 `references/rope-docs/` 确认 rope 不支持此操作
- [ ] 已向用户说明 rope 不支持的具体原因
- [ ] 用户已知晓风险并同意使用其他方法

**示例说明**：
> "rope 的 `Restructure` 只支持代码模式替换，不支持文件路径重命名。此操作需要重命名目录结构，rope 无法处理，将使用 `pathlib.Path.rename()` 实现。"

## 工作流程

1. **理解重构需求** - 明确重构类型、范围、涉及的文件和代码位置
2. **创建重构脚本** - 在项目根目录创建 `.refactor` 目录，命名格式：`{yyyyMMdd-HHmmss}-{kebab-case-标题}.py`
3. **编写脚本内容** - 使用 rope 重构 API，添加预览和确认机制
4. **输出说明** - 告知用户脚本位置、执行方法、提醒备份

## Rope 重构 API 速查

### 基础设置

```python
from rope.base.project import Project
from rope.base.libutils import path_to_resource

project = Project('/path/to/project')
resource = path_to_resource(project, 'path/to/file.py')
```

### 重命名 (Rename)

```python
from rope.refactor.rename import Rename

# 重命名代码符号
renamer = Rename(project, resource, offset)
changes = renamer.get_changes('new_name')

# 重命名模块文件（需要 VCS）
renamer = Rename(project, resource, offset=None)
changes = renamer.get_changes('new_module')
```

### 移动 (Move)

```python
from rope.refactor.move import MoveModule, create_move

# 移动模块
mover = MoveModule(project, resource)
changes = mover.get_changes(destination_folder)

# 移动方法/全局（自动选择类型）
mover = create_move(project, resource, offset)
```

### 提取 (Extract)

```python
from rope.refactor.extract import ExtractMethod, ExtractVariable

# 提取方法
extractor = ExtractMethod(project, resource, start, end)
changes = extractor.get_changes('method_name', similar=True)

# 提取变量
extractor = ExtractVariable(project, resource, start, end)
```

### 内联 (Inline)

```python
from rope.refactor.inline import create_inline

inliner = create_inline(project, resource, offset)
changes = inliner.get_changes(remove=True)
```

### 改变签名 (Change Signature)

```python
from rope.refactor.change_signature import ChangeSignature, ArgumentAdder

changer = ChangeSignature(project, resource, offset)
changes = changer.get_changes([ArgumentAdder(1, 'new_param')])
```

### 封装字段 / 引入工厂 / 引入参数

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

### 重构结构 (Restructure)

```python
from rope.refactor.restructure import Restructure

pattern = "${obj}.old_method(${param})"
goal = "new_method(${obj}, ${param})"
restructuring = Restructure(project, pattern, goal)
```

### 导入管理

```python
from rope.refactor.importutils import ImportOrganizer

organizer = ImportOrganizer(project)
changes = organizer.organize_imports(resource)
```

### 查找引用 (Occurrences)

```python
from rope.refactor.occurrences import create_finder, CallsFilter

finder = create_finder(project, resource, offset)
for occ in finder.find_occurrences():
    print(occ.resource.path, occ.offset)

# 只查找调用位置
finder = create_finder(project, resource, offset, filters=[CallsFilter()])
```

### 撤销/重做

```python
project.history.undo()
project.history.redo()
```

## 完整 API 列表

| 操作 | 导入路径 |
|------|----------|
| 重命名 | `rope.refactor.rename.Rename` |
| 部分改变 | `rope.refactor.rename.ChangeOccurrences` |
| 移动模块 | `rope.refactor.move.MoveModule` |
| 移动方法 | `rope.refactor.move.MoveMethod` |
| 移动全局 | `rope.refactor.move.MoveGlobal` |
| 移动工厂 | `rope.refactor.move.create_move` |
| 提取方法 | `rope.refactor.extract.ExtractMethod` |
| 提取变量 | `rope.refactor.extract.ExtractVariable` |
| 内联 | `rope.refactor.inline.create_inline` |
| 改变签名 | `rope.refactor.change_signature.ChangeSignature` |
| 添加参数 | `rope.refactor.change_signature.ArgumentAdder` |
| 删除参数 | `rope.refactor.change_signature.ArgumentRemover` |
| 重排序参数 | `rope.refactor.change_signature.ArgumentReorderer` |
| 封装字段 | `rope.refactor.encapsulate_field.EncapsulateField` |
| 引入工厂 | `rope.refactor.introduce_factory.IntroduceFactory` |
| 引入参数 | `rope.refactor.introduce_parameter.IntroduceParameter` |
| 重构结构 | `rope.refactor.restructure.Restricture` |
| 使用函数 | `rope.refactor.usefunction.UseFunction` |
| 局部转字段 | `rope.refactor.localtofield.LocalToField` |
| 方法对象 | `rope.refactor.method_object.MethodObject` |
| 模块转包 | `rope.refactor.topackage.ModuleToPackage` |
| 导入管理 | `rope.refactor.importutils.ImportOrganizer` |
| 查找引用 | `rope.refactor.occurrences.create_finder` |
| 多项目重构 | `rope.refactor.multiproject.MultiProjectRefactoring` |

## 工具函数

工具函数位于 `scripts/helpers.py`，可直接导入使用：

```python
import sys
sys.path.insert(0, '/path/to/.claude/skills/python-refactor/scripts')
from helpers import find_offset, find_definition_offset, get_region_offsets
```

| 函数 | 用途 |
|------|------|
| `find_offset(resource, pattern)` | 查找模式偏移量 |
| `find_definition_offset(resource, name, type)` | 查找类/函数定义位置 |
| `get_region_offsets(resource, start, end)` | 获取区域偏移 |
| `check_project_health(project)` | 项目健康检查 |
| `pre_refactor_check(project)` | 重构前检查 |
| `validate_imports(project)` | 验证导入 |

## 脚本模板

基础模板位于 `templates/basic-refactor.py`。

### 命名规范

```
{yyyyMMdd-HHmmss}-{kebab-case-标题}.py
```

示例：`20260313-143022-rename-user-model.py`

### 基本结构

```python
#!/usr/bin/env python3
import argparse
from pathlib import Path
from rope.base.project import Project
from rope.base.libutils import path_to_resource
from rope.base.exceptions import RefactoringError

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()

    project = Project(str(Path(__file__).parent.parent))
    try:
        resource = path_to_resource(project, 'path/to/file.py')
        # 实现重构逻辑...

        if args.dry_run:
            print(changes.get_description())
        else:
            project.do(changes)
    except RefactoringError as e:
        print(f"重构错误：{e}")
    finally:
        project.close()

if __name__ == '__main__':
    main()
```

## 关键限制

### 模块重命名

- 重命名模块文件**需要**版本控制系统（git/hg）
- 使用 `Rename(project, resource, offset=None)` 重命名模块
- `MoveModule` 只能移动位置，**不能**改变文件名

### 版本控制要求

**需要 VCS**：重命名模块文件、撤销/重做
**不需要 VCS**：重命名代码符号、提取、内联、改变签名等

### Python 版本兼容性

rope 使用运行环境的 Python AST 解析器：

| 项目代码 | rope 最低运行环境 |
|----------|------------------|
| `typing.Dict`, `Union` | Python 3.8+ |
| `dict[K, V]` (PEP 585) | Python 3.10+ |
| `X \| Y` (PEP 604) | Python 3.10+ |
| `type` 语句 (PEP 695) | Python 3.12+ |

### FastAPI 项目

FastAPI 使用 `Annotated` 依赖注入模式有特殊限制，详见 `references/fastapi-support.md`。

## 参考文档

### 本地文档

位于 `references/rope-docs/`：

| 文档 | 用途 |
|------|------|
| `overview.rst` | 重构操作示例和效果说明 |
| `library.rst` | API 详细用法 |
| `configuration.rst` | 配置选项 |

### 在线资源

- 官方文档：https://rope.readthedocs.io/
- GitHub：https://github.com/python-rope/rope

### 更新本地文档

```bash
cd ~/.claude/skills/python-refactor
./scripts/update_docs.sh
```

## 常见问题

**Q: 重命名模块报错 "not under version control"**
A: 将项目加入 git/hg 版本控制

**Q: MoveModule 不能同时改变文件名和位置**
A: 先用 `Rename(offset=None)` 重命名，再用 `MoveModule` 移动

**Q: rope 无法识别 Python 3.10+ 的 `int | float` 类型**
A: 使用 `Union[int, float]` 代替，或升级 rope 运行环境
