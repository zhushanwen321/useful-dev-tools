---
category: type-hint
created: 2026-03-20
tags: [decimal, sqlalchemy, type-cast, ruff]
---

# Decimal 类型转换

## 场景

从数据库读取的 DECIMAL 类型数据赋值给 Python Decimal 类型时，Pyright 报类型不兼容。

## 问题

SQLAlchemy 的 `DECIMAL[Unknown]` 类型与 Python 的 `Decimal` 类型不兼容：

```python
# ❌ Pyright 报告类型不兼容
row["close"]  # type: DECIMAL[Unknown]
value = Decimal(row["close"])  # type: ignore

# ✅ 正确处理
value: Decimal = row["close"]  # type: ignore[assignment]
```

类型错误：
```
Argument of type "DECIMAL[Unknown]" cannot be assigned to parameter "close" of type "Decimal"
"DECIMAL[Unknown]" is not assignable to "Decimal"
```

## 选项

1. **使用 `# type: ignore[assignment]`**
   - 优点：快速绕过检查
   - 缺点：隐藏潜在类型问题

2. **使用 `cast()` 明确转换**
   ```python
   from typing import cast
   value = cast(Decimal, row["close"])
   ```
   - 优点：显式转换，类型安全
   - 缺点：代码冗长

3. **依赖运行时验证**
   - 优点：不加类型注解
   - 缺点：失去类型检查保护

## 选择

**选项 1**：使用 `# type: ignore[assignment]`

```python
# ORM 到领域模型的转换中
return DailyOhlcv(
    stock_code=row["stock_code"],  # type: ignore[assignment]
    trade_date=row["trade_date"],  # type: ignore[assignment]
    close=row["close"],  # type: ignore[assignment]
    open=row["open"],  # type: ignore[assignment]
    high=row["high"],  # type: ignore[assignment]
    low=row["low"],  # type: ignore[assignment]
    volume=row["volume"],  # type: ignore[assignment]
    amount=row["amount"],  # type: ignore[assignment]
)
```

## 理由

1. **工具限制**：这是 SQLAlchemy 类型存根的限制，非代码问题
2. **运行时安全**：运行时会正确转换 Decimal
3. **代码清洁**：避免大量 `cast()` 调用
4. **精确定位**：`[assignment]` 指定忽略范围，不影响其他检查

## 改进空间

如果 SQLAlchemy 类型存根改善（支持 `Decimal` 推断），可移除 `# type: ignore`。

## 相关文件

- 文件: backend/app/infra/db/repository/daily_ohlcv_repository.py
- 文件: backend/app/infra/db/repository/industry_index_daily_repository.py
- 问题: float 到 Decimal 转换
- 提交: f2f59a6
