---
category: type-hint
created: 2026-03-18
tags: [mypy, sqlalchemy, type-safety, refactoring]
---

# 正面修复 mypy 类型错误 vs 使用 type: ignore

## 场景

当面对 mypy 报告的类型错误，特别是来自第三方库（如 SQLAlchemy）的类型存根不完整导致的错误时，有两种处理方式。

## 选项

### A. 使用 `# type: ignore` 忽略错误

```python
result = await session.execute(stmt)
return result.rowcount  # type: ignore[attr-defined]
```

### B. 创建类型安全的辅助方法，正面修复

在 BaseRepository 中添加辅助方法：

```python
def _extract_rowcount(self, result: Any) -> int:
    """安全地提取 execute 结果的 rowcount，带类型转换。"""
    rowcount: int | None = cast(int | None, result.rowcount)
    return rowcount or 0
```

然后使用：

```python
result = await session.execute(stmt)
return self._extract_rowcount(result)
```

## 选择

**B - 创建类型安全的辅助方法**

## 理由

1. **类型安全**：使用 `cast` 明确类型，比 `type: ignore` 更精确，不会掩盖其他潜在问题
2. **集中管理**：所有 rowcount 提取逻辑统一在一个方法中，易于统一修改
3. **易于维护**：未来如果 SQLAlchemy 类型定义改变，只需修改一处
4. **代码可读性**：`_extract_rowcount(result)` 比 `result.rowcount or 0` 更清晰表达意图
5. **可测试性**：辅助方法可以单独测试，确保边界情况（如 None）处理正确

## 相关场景

- 任何第三方库类型存根不完整导致 mypy 报错的情况
- 需要频繁进行相同类型转换的代码模式
- 团队协作项目中，需要统一类型处理方式的地方

## 提炼的原则

- **正面修复优于忽略**：优先选择解决类型系统限制的方案，而非绕过检查
- **集中管理重复逻辑**：将重复的类型转换逻辑封装为辅助方法
- **语义化命名**：方法名应表达"做什么"而非"怎么做"（如 `_extract_rowcount` 而非 `_cast_rowcount_to_int`）
