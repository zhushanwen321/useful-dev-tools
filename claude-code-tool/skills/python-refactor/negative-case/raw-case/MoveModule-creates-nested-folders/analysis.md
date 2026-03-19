# MoveModule 移动 __init__.py 导致嵌套目录结构

## 问题概述

使用 `MoveModule` 移动包的 `__init__.py` 时，rope 会把整个包当作整体移动，导致在目标目录下创建嵌套的包结构。

## 错误现象

```
预期结果：
backend/app/domain/supporting/collection/
  ├── __init__.py
  ├── daily_indicator_provider.py
  ├── daily_trading_provider.py
  └── ...

实际结果：
backend/app/domain/supporting/collection/
  └── collection/           # 嵌套！
      ├── __init__.py
      ├── daily_indicator_provider.py
      ├── daily_trading_provider.py
      └── ...
```

## 根本原因

`MoveModule` 在处理 `__init__.py` 时会自动识别为包结构，并将整个包（包括所有子模块）一起移动到目标目录。当目标目录已经存在时，就会产生嵌套。

相关代码在 `rope/refactor/move.py`:

```python
def __init__(self, project, resource):
    ...
    if not resource.is_folder() and resource.name == "__init__.py":
        resource = resource.parent  # 自动获取父目录
    ...
```

## 解决方案

**方案一：只移动 provider 文件，不移动 `__init__.py`**

```python
# 不要移动 __init__.py
moves = {
    "backend/app/infra/.../collection/daily_indicator_provider.py": "backend/app/domain/supporting/collection",
    # ... 其他 provider 文件
    # 注意：不要包含 __init__.py
}
```

**方案二：如果必须移动整个包**

先手动清空或删除目标目录，然后再移动。

## 经验总结

- **`MoveModule` 和 `__init__.py`**：移动 `__init__.py` 会触发整个包的移动
- **检查目标目录**：移动前确保目标目录结构符合预期
- **优先移动单个文件**：只移动需要的 `.py` 文件，避免移动包结构

## 相关文件

- 完整的重构脚本：`/Users/zhushanwen/Code/stock-data-crawler/.refactor/20260316-110500-move-providers-to-supporting.py`
- 失败的脚本：`/Users/zhushanwen/Code/stock-data-crawler/.refactor/20260316-110000-move-providers-to-supporting.py`
