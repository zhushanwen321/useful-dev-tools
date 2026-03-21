---
category: type-hint
created: 2026-03-20
tags: [pyright, generic, ruff, UP049]
---

# 泛型类型参数命名

## 场景

定义泛型类或 Mixin 时，类型参数的命名方式影响 Pyright/Ruff 的类型检查。

## 问题

使用私有类型参数名（前导下划线）触发 Ruff UP049 警告：

```python
# ❌ 触发 UP049
class DateRepositoryMixin[_T](_DependencyValidationMixin):
    _date_column: str = "trade_date"
```

警告信息：
```
UP049 Generic class uses private type parameters
```

## 选项

1. **使用私有类型参数**（`_T`）
   - 优点：约定俗成，表示内部使用
   - 缺点：触发 Ruff UP049 警告

2. **使用公共类型参数**（`T`）
   - 优点：符合 Ruff 规范
   - 缺点：失去"私有"语义

3. **禁用 UP049 规则**
   - 优点：保留 `_T` 命名
   - 缺点：全局禁用可能有意义检查

## 选择

**选项 2**：使用公共类型参数名 `T`

```python
# ✅ 符合规范
class DateRepositoryMixin[T](_DependencyValidationMixin):
    _date_column: str = "trade_date"
```

## 理由

1. **工具兼容性**：遵循 Ruff 规范，避免警告
2. **类型安全**：泛型参数的"私有性"通过类的访问控制实现，而非命名
3. **Python 惯例**：`TypeVar` 也常用 `T` 而非 `_T`
4. **代码清洁**：不增加 ruff 配置复杂度

## 补充说明

如果确实需要表达"内部使用"的语义，通过类的文档字符串或访问控制来实现：

```python
class DateRepositoryMixin[T]:
    """日期相关查询混入类（内部使用）。

    T: 领域模型类型（仅用于类型注解）
    """
```

## 相关文件

- 文件: backend/app/infra/db/repository/mixins.py
- 提交: f2f59a6
- Ruff 规则: UP049
