---
name: python-refactor
description: 使用 rope 库编写 Python 代码重构脚本。触发词：「重构」、「使用 rope」、「重命名」、「移动模块」、「提取方法」、「内联变量」、「批量重构」。
---

# Python Refactor Skill

使用 rope 库编写安全、可靠的 Python 代码重构脚本。

## 核心规则 - 最高优先级

### 重构决策流程（必须严格遵循）

```
1. 收到重构需求
       ↓
2. 查找 rope API：在下方"API 速查表"或 references/rope-docs/ 中查找
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

| 禁止的方法 | 原因 |
|-----------|------|
| `re.sub()` / 正则表达式 | 无法区分代码、字符串、注释 |
| `str.replace()` | 会误改无关的同名文本 |
| `shutil.move()` 移动 .py 文件 | 不会更新导入语句 |
| 手动解析 AST 后修改代码 | rope 已封装，重复造轮子 |
| 直接 `open()` 读写代码文件 | 绕过 rope 的语义分析 |

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

## 工作流程

1. **理解重构需求** - 明确重构类型、范围、涉及的文件
2. **创建脚本** - 在项目根目录 `.refactor/` 下创建，命名：`{yyyyMMdd-HHmmss}-{kebab-case}.py`
3. **编写脚本** - 使用 rope 重构 API，添加 `--dry-run` 预览
4. **输出说明** - 告知脚本位置、执行方法

## API 速查表

### 基础设置

```python
from rope.base.project import Project
from rope.base.libutils import path_to_resource

project = Project('/path/to/project')
resource = path_to_resource(project, 'path/to/file.py')
```

### 重构操作速查

| 操作 | 导入路径 | 说明 |
|------|----------|------|
| 重命名 | `rope.refactor.rename.Rename` | `offset=None` 时重命名模块 |
| 部分改变 | `rope.refactor.rename.ChangeOccurrences` | 只改变选定的出现位置 |
| 移动模块 | `rope.refactor.move.MoveModule` | 只移动位置，不改文件名 |
| 移动方法/全局 | `rope.refactor.move.create_move` | 自动选择移动类型 |
| 提取方法 | `rope.refactor.extract.ExtractMethod` | `similar=True` 替换相似代码 |
| 提取变量 | `rope.refactor.extract.ExtractVariable` | |
| 内联 | `rope.refactor.inline.create_inline` | 自动选择内联类型 |
| 改变签名 | `rope.refactor.change_signature.ChangeSignature` | 配合 ArgumentAdder/Remover |
| 封装字段 | `rope.refactor.encapsulate_field.EncapsulateField` | |
| 引入工厂 | `rope.refactor.introduce_factory.IntroduceFactory` | |
| 引入参数 | `rope.refactor.introduce_parameter.IntroduceParameter` | |
| 重构结构 | `rope.refactor.restructure.Restricture` | 模式匹配替换 |
| 使用函数 | `rope.refactor.usefunction.UseFunction` | 全局替换为函数调用 |
| 局部转字段 | `rope.refactor.localtofield.LocalToField` | |
| 方法对象 | `rope.refactor.method_object.MethodObject` | 命令模式 |
| 模块转包 | `rope.refactor.topackage.ModuleToPackage` | |
| 导入管理 | `rope.refactor.importutils.ImportOrganizer` | |
| 查找引用 | `rope.refactor.occurrences.create_finder` | 配合 CallsFilter 等 |
| 多项目重构 | `rope.refactor.multiproject.MultiProjectRefactoring` | |
| 撤销/重做 | `project.history.undo()` / `redo()` | |

**详细代码示例**：见 `references/api-examples.md`

## 工具函数

位于 `scripts/helpers.py`：

| 函数 | 用途 |
|------|------|
| `find_offset(resource, pattern)` | 查找模式偏移量 |
| `find_definition_offset(resource, name, type)` | 查找类/函数定义位置 |
| `get_region_offsets(resource, start, end)` | 获取区域偏移 |

## 脚本模板

基础模板：`templates/basic-refactor.py`

命名规范：`{yyyyMMdd-HHmmss}-{kebab-case-标题}.py`

示例：`20260313-143022-rename-user-model.py`

## 关键限制

### 模块操作

- 重命名模块文件**需要**版本控制系统（git/hg）
- `MoveModule` 只能移动位置，**不能**改变文件名
- 先重命名再移动：`Rename(offset=None)` -> `MoveModule`

### 版本控制要求

| 需要 VCS | 不需要 VCS |
|----------|-----------|
| 重命名模块文件 | 重命名代码符号 |
| 撤销/重做 | 提取、内联、改变签名 |

### Python 版本兼容性

rope 使用运行环境的 Python AST 解析器：

| 项目代码类型 | rope 最低运行环境 |
|--------------|------------------|
| `typing.Dict`, `Union` | Python 3.8+ |
| `dict[K, V]` (PEP 585) | Python 3.10+ |
| `X \| Y` (PEP 604) | Python 3.10+ |
| `type` 语句 (PEP 695) | Python 3.12+ |

### FastAPI 项目

`Annotated` 依赖注入模式有特殊限制，详见 `references/fastapi-support.md`。

## 参考文档

| 文档 | 位置 | 用途 |
|------|------|------|
| API 示例 | `references/api-examples.md` | 详细代码示例 |
| FastAPI 支持 | `references/fastapi-support.md` | FastAPI 特殊处理 |
| Rope 用户指南 | `references/rope-docs/overview.rst` | 重构操作示例 |
| Rope API 参考 | `references/rope-docs/library.rst` | API 详细用法 |
| 在线文档 | https://rope.readthedocs.io/ | |

## 常见问题

**Q: 重命名模块报错 "not under version control"**
A: 将项目加入 git/hg 版本控制

**Q: MoveModule 不能同时改变文件名和位置**
A: 先用 `Rename(offset=None)` 重命名，再用 `MoveModule` 移动

**Q: rope 无法识别 Python 3.10+ 的 `int | float` 类型**
A: 使用 `Union[int, float]` 代替，或升级 rope 运行环境
