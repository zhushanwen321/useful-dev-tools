# MoveModule 执行后文件未实际移动

## 问题概述

使用 `rope.refactor.move.MoveModule` 移动模块时，`get_changes()` 返回了正确的变化列表，但 `project.do()` 执行后文件实际没有被移动。

## 错误现象

```python
# 重命名模块成功
renamer = Rename(project, resource, offset=None)
rename_changes = renamer.get_changes(new_name)
project.do(rename_changes)  # ✓ 成功

# 移动模块报告成功，但文件未移动
mover = MoveModule(project, renamed_resource)
dest_resource = project.get_folder(str(target_dir))
move_changes = mover.get_changes(dest_resource)  # 返回正确的 changes
project.do(move_changes)  # 报告"✓ 移动完成"，但文件还在原位置
```

## 根本原因

1. **`MoveResource` change 依赖版本控制系统**：`MoveModule` 在内部使用 `MoveResource` change，这个 change 在执行时会调用 VCS 的 `move()` 命令（如 `git mv`）

2. **空目录问题**：当目标目录是新建的空目录时，rope 可能没有正确识别其状态，导致 `MoveResource` 执行失败但不会抛出异常

3. **缺少 `__init__.py`**：目标目录如果不是有效的 Python 包（没有 `__init__.py`），可能导致 rope 无法正确处理移动操作

## 解决方案

### 方案 1：分步执行 + 手动移动

```python
# 1. 先用 rope Rename 重命名文件
renamer = Rename(project, resource, offset=None)
rename_changes = renamer.get_changes(new_name)
project.do(rename_changes)

# 2. 手动使用 git mv 移动文件
import subprocess
subprocess.run(["git", "mv", old_path, new_path])

# 3. 手动更新导入语句（因为 rope 的移动失败，导入可能错误）
```

### 方案 2：确保目标目录是有效的 Python 包

```python
# 创建目标目录前先添加 __init__.py
target_dir = Path("backend/app/infra/shared/constant")
target_dir.mkdir(parents=True, exist_ok=True)
(target_dir / "__init__.py").touch()

# 然后再执行 MoveModule
```

### 方案 3：使用 `ChangeOccurrences` 精确控制

如果只需要更新导入而不移动文件，可以使用 `ChangeOccurrences`：

```python
from rope.refactor.rename import ChangeOccurrences

changer = ChangeOccurrences(project, resource)
changes = changer.get_changes("old.module.name", "new.module.name")
project.do(changes)
```

## 经验总结

1. **不要完全依赖 rope 的文件移动**：`MoveModule` 在某些情况下不可靠，特别是涉及跨目录移动或新建目录时

2. **验证结果很重要**：执行重构后一定要验证文件是否真的被移动了

3. **考虑混合方案**：rope 的 `Rename` 操作通常更可靠，可以先重命名再手动移动文件

4. **目标目录需要是有效的 Python 包**：确保目标目录有 `__init__.py` 文件

5. **版本控制很重要**：rope 的文件移动操作依赖于 VCS，确保项目在 git 版本控制下
