# MoveModule 跨层级移动生成错误的导入路径

## 问题概述

使用 `MoveModule` 将模块从父目录的子目录移动到兄弟目录的子目录时，rope 生成了错误的导入路径，导致 `ModuleNotFoundError`。

## 错误现象

**移动场景**：
```
源位置：backend/app/api/constant/constants.py
目标位置：backend/app/api/shared/constant/constants.py
```

**rope 生成的导入**：
```python
# backend/app/api/route/health.py
from constant.constants import APP_VERSION, app_start_time  # ❌ 错误！
```

**期望的导入**：
```python
from app.api.shared.constant.constants import APP_VERSION, app_start_time  # ✅ 正确
```

**运行时报错**：
```
ModuleNotFoundError: No module named 'constant'
```

## 根本原因

1. **相对路径计算错误**：rope 在计算跨层级移动的导入路径时，错误地将绝对导入转换为相对导入
2. **目录结构感知问题**：rope 无法正确识别"同父目录下 → 兄弟目录的子目录"这种移动模式
3. **source_folders 设置无效**：即使设置了正确的 `source_folders=["backend/app"]`，rope 仍无法正确计算路径

**具体分析**：
- 从 `backend/app/api/` 的角度看，`constant/` 是同级目录
- rope 错误地认为可以简化为 `from constant.constants import`
- 但 `constant/` 实际上不在 Python 路径中，必须使用完整的 `app.api.shared.constant.constants`

## 解决方案

**组合方法：rope 移动文件 + 正则表达式修复导入**

1. 使用 `MoveModule` 移动文件（保留 VCS 集成）
2. 使用正则表达式批量修复错误的导入路径
3. 验证所有文件没有残留错误

**修复规则**：
```python
IMPORT_FIXES = [
    (
        r'from constant\.constants import',
        'from app.api.shared.constant.constants import'
    ),
    (
        r'from app\.api\.constant\.constants import',
        'from app.api.shared.constant.constants import'
    ),
]
```

**完整脚本示例**：见 `case_script.py`

## 经验总结

- **跨层级移动需谨慎**：涉及兄弟目录间的移动时，MoveModule 路径计算不可靠
- **验证是关键**：移动后必须检查生成的导入路径是否正确
- **组合方案实用**：rope 负责 VCS 操作，正则负责导入修复，分工明确
- **预先检测问题**：执行重构前先检查 `get_changes()` 的结果，避免错误的变更

## 相关文件

- `case_script.py` - 组合方案的重构脚本
- `case_output.txt` - rope 生成错误导入的预览输出
`