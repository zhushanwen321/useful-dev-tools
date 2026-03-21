# Python 开发偏好记录

本目录存放用户的 Python 开发偏好记录，供 `py-preference` skill 读取和应用。

## 目录结构

```
references/
├── type-hint/          # 类型标注偏好
├── error-handling/     # 错误处理偏好
├── code-style/         # 代码风格偏好
├── refactoring/        # 重构策略偏好
└── tool-config/        # 工具配置偏好（mypy, ruff 等）
```

## 记录格式

每条记录遵循以下模板：

```markdown
---
category: <类别>
created: YYYY-MM-DD
tags: [tag1, tag2]
---

# <偏好标题>

## 场景
（什么情况下需要做这个决策）

## 选项
（列出可能的方案）

## 选择
（用户选择的方案）

## 理由
（为什么选择这个方案）

## 相关场景
（其他可能适用此偏好的场景）
```

## 使用方式

- **记录偏好**：调用 `/py-preference-optimize` skill
- **应用偏好**：调用 `/py-preference` skill（AI 会自动读取）

## 现有记录

### type-hint (4)
| 记录 | 描述 | 创建日期 |
|------|------|----------|
| [for-loop-variable](./type-hint/for-loop-variable.md) | for 循环变量重用时的类型不兼容处理 | 2026-03-18 |
| [generic-type-parameter-naming](./type-hint/generic-type-parameter-naming.md) | 泛型类型参数命名（`T` vs `_T`） | 2026-03-20 |
| [decimal-type-conversion](./type-hint/decimal-type-conversion.md) | SQLAlchemy DECIMAL 类型转换 | 2026-03-20 |
| [asyncio-run_in_executor-compat](./type-hint/asyncio-run_in_executor-compat.md) | asyncio.run_in_executor 类型兼容性 | 2026-03-20 |

### code-style (1)
| 记录 | 描述 | 创建日期 |
|------|------|----------|
| [repository-method-naming](./code-style/repository-method-naming.md) | Repository 方法命名一致性 | 2026-03-20 |

### tool-config (1)
| 记录 | 描述 | 创建日期 |
|------|------|----------|
| [pyrightconfig-location](./tool-config/pyrightconfig-location.md) | Pyright 配置文件位置 | 2026-03-20 |

---

**统计**：共 6 条偏好记录，最后更新于 2026-03-20
