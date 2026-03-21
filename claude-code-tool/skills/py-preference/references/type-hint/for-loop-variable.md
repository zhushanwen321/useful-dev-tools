---
category: type-hint
created: 2026-03-18
tags: [mypy, for-loop, variable, type-inference]
---

# For 循环变量重用时的类型不兼容

## 场景

当在同一个函数中使用多个 for 循环，且循环变量同名时，mypy 会报类型不兼容错误。

**原因**：Python 的 for 循环变量会泄漏到外部作用域，mypy 按此语义处理，认为两次 `item` 是同一个变量。

```python
# mypy 报错：Incompatible types in assignment
for item in cls.Collection:   # item 类型推断为 Collection
    ...

for item in cls.Calculation:  # 尝试赋值 Calculation 类型
    ...
```

## 选项

### A. 使用不同变量名

为每个循环使用语义化的不同变量名。

```python
for item in cls.Collection:
    ...

for calc_item in cls.Calculation:
    ...
```

### B. 添加显式类型注解

在循环前声明变量的类型。

```python
item: StrEnum  # 或 Collection | Calculation

for item in cls.Collection:
    ...

for item in cls.Calculation:
    ...
```

### C. 禁用 mypy 检查

在该行添加 `# type: ignore` 或在配置中禁用 `assignment` 检查。

## 选择

**A. 使用不同变量名**

## 理由

1. 代码更清晰，每个变量有明确的语义
2. 不依赖 mypy 的类型推断行为
3. 改动小，影响范围明确
4. 符合"变量名应表达意图"的原则

## 相关场景

- while 循环变量重用
- 列表/字典/集合推导式中的变量
- with 语句中的 as 变量
- 多个 `except` 块中的异常变量

## 提炼的原则

- **语义优先**：通过变量名表达意图，而非依赖工具的类型推断
- **显式优于隐式**：每个变量有独立的语义名称，代码自解释
- **工具服务于人**：不为了满足 mypy 而牺牲代码可读性
