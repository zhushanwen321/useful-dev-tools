# MoveModule 不会更新不匹配的相对导入

## 问题概述

使用 `MoveModule` 移动模块后，源代码中的一些相对导入语句没有被自动更新为正确的绝对导入路径。

## 错误现象

移动前（源文件位置）：
```python
# backend/app/infra/completeness/providers/calculation/financial_factor_provider.py
from base_providers import StockBasedCompletenessProvider  # ← 相对导入
from provider_base import CompletenessProvider             # ← 相对导入
```

移动后（新位置）：
```python
# backend/app/domain/supporting/calculation/financial_factor_provider.py
from base_providers import StockBasedCompletenessProvider  # ← 未更新！错误
from provider_base import CompletenessProvider             # ← 未更新！错误
```

运行时报错：
```
ModuleNotFoundError: No module named 'base_providers'
ModuleNotFoundError: No module named 'provider_base'
```

## 根本原因

`MoveModule` 主要更新**显式的绝对导入路径**（如 `from app.infra.xxx`），但对于：

1. **相对导入** - `from base_providers import`
2. **隐式导入** - 依赖于当前包结构的导入

rope 无法智能判断这些导入应该如何更新。这是 rope 的一个已知限制。

相关代码位置：
- `base_providers`: `app/infra/completeness/framework/base_providers.py`
- `provider_base`: `app/infra/completeness/framework/provider_base.py`

## 解决方案

**使用 sed 批量修复未更新的导入**：

```bash
# 修复 base_providers 导入
find app/domain/supporting -name "*_provider.py" -type f \
  -exec sed -i '' 's/from base_providers import/from app.infra.completeness.framework.base_providers import/g' {} +

# 修复 provider_base 导入
find app/domain/supporting -name "*_provider.py" -type f \
  -exec sed -i '' 's/from provider_base import/from app.infra.completeness.framework.provider_base import/g' {} +
```

**更好的实践**：在移动前先将相对导入改为绝对导入。

## 经验总结

- **相对导入问题**：rope 移动模块时不会自动更新相对导入
- **验证导入**：移动后必须运行测试验证导入是否正确
- **批量修复工具**：使用 `sed` 可以快速批量修复未更新的导入
- **最佳实践**：源代码应避免使用相对导入，使用绝对导入更利于重构

## 相关文件

- 影响的文件：12 个 provider 文件
- 修复命令：见上文
