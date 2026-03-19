---
name: python-refactor
description: 使用 rope 库编写 Python 代码重构脚本。触发词：「重构」、「使用 rope」、「重命名」、「移动模块」、「提取方法」、「内联变量」、「批量重构」。
---

# Python Refactor Skill

使用 rope 库编写安全、可靠的 Python 代码重构脚本。

## ⚠️ 重要提示

**所有 API 文档已移至 `reference/` 目录，使用前请查阅对应文档。**

**rope 源代码位于 `~/GitApp/rope`，遇到疑难问题可查阅源码。**

## ⛔ 最高铁律

**一旦开启此 Skill，必须且只能使用 rope 进行重构**

```
⛔ 绝对禁止：
  • 脚本执行出错后，立刻换用正则表达式/str.replace()等其他方法
  • 绕过 rope 直接修改代码文件

✅ 遇到错误时：
  1. 仔细阅读错误信息
  2. 查阅 reference/ 目录中的 API 文档
  3. 检查代码问题（参数错误？路径错误？）
  4. 尝试不同的 rope API 用法
  5. 启动 subagent 查看 ~/GitApp/rope 源代码实现
  6. 穷尽所有 rope 方案后，才能向用户说明情况
```

## 核心规则

### 重构决策流程

```
1. 收到重构需求
       ↓
2. 查找 API 文档：在 reference/ 目录
       ↓
3. 找到 API？
   ├── 是 → 使用 rope API → 结束
   └── 否 → 查看负向用例 → 启动 subagent 查阅 ~/GitApp/rope 源码 → 继续尝试 rope 方法
```

### 绝对禁止

| 禁止的方法 | 原因 |
|-----------|------|
| `re.sub()` / 正则 | 无法区分代码、字符串、注释 |
| `str.replace()` | 会误改无关的同名文本 |
| `shutil.move()` 移动 .py | 不会更新导入语句 |
| 直接 `open()` 读写代码 | 绕过 rope 语义分析 |

### 遇到问题时的处理顺序

1. **先查 API 文档**：`reference/` 目录
2. **再查负向用例**：`negative-case/raw-case/`
3. **查阅 rope 源代码**：启动 subagent 查看 `~/GitApp/rope` 源码
4. **最后才考虑非 rope 方法**

## 工作流程

1. 理解重构需求 - 明确类型、范围、涉及文件
2. 查找 API - 在 reference/ 目录查阅
3. 创建脚本 - `.refactor/{yyyyMMdd-HHmmss}-{kebab-case}.py`
4. 编写脚本 - 使用 rope API，添加 `--dry-run` 预览
5. 输出说明 - 告知脚本位置、执行方法

## API 速查表

| 操作 | API | 文档 |
|------|-----|------|
| 重命名符号 | `Rename` | [reference/rename.md](reference/rename.md) |
| 重命名模块 | `Rename(offset=None)` | [reference/rename.md](reference/rename.md) |
| 移动模块 | `MoveModule` | [reference/move_module.md](reference/move_module.md) |
| 移动方法/全局 | `create_move` | [reference/create_move.md](reference/create_move.md) |
| 提取方法 | `ExtractMethod` | [reference/extract_method.md](reference/extract_method.md) |
| 提取变量 | `ExtractVariable` | [reference/extract_variable.md](reference/extract_variable.md) |
| 内联 | `create_inline` | [reference/create_inline.md](reference/create_inline.md) |
| 改变签名 | `ChangeSignature` | [reference/change_signature.md](reference/change_signature.md) |
| 查找引用 | `create_finder` | [reference/create_finder.md](reference/create_finder.md) |

### 完整 API 列表

| 类别 | API |
|------|-----|
| 基础 | [Project](reference/project.md), [path_to_resource](reference/path_to_resource.md) |
| 重命名 | [Rename](reference/rename.md), [ChangeOccurrences](reference/change_occurrences.md) |
| 移动 | [MoveModule](reference/move_module.md), [create_move](reference/create_move.md) |
| 提取 | [ExtractMethod](reference/extract_method.md), [ExtractVariable](reference/extract_variable.md) |
| 内联 | [create_inline](reference/create_inline.md) |
| 签名 | [ChangeSignature](reference/change_signature.md) |
| 封装 | [EncapsulateField](reference/encapsulate_field.md), [IntroduceFactory](reference/introduce_factory.md) |
| 参数 | [IntroduceParameter](reference/introduce_parameter.md), [LocalToField](reference/local_to_field.md) |
| 模式 | [Restructure](reference/restructure.md), [UseFunction](reference/use_function.md), [MethodObject](reference/method_object.md) |
| 包 | [ModuleToPackage](reference/module_to_package.md) |
| 导入 | [ImportOrganizer](reference/import_organizer.md) |
| 分析 | [create_finder](reference/create_finder.md) |
| 多项目 | [MultiProjectRefactoring](reference/multi_project_refactoring.md) |

## 关键限制

- 重命名模块文件**需要** VCS（git/hg）
- `MoveModule` 只能移动位置，**不能**改变文件名
- 先重命名再移动：`Rename(offset=None)` → `MoveModule`

## 参考文档

| 文档 | 位置 |
|------|------|
| API 文档 | `reference/*.md` |
| 负向用例 | `negative-case/raw-case/` |
| FastAPI 支持 | `references/fastapi-support.md` |
| rope 源代码 | `~/GitApp/rope` |
