---
category: code-style
created: 2026-03-20
tags: [repository, method-name, consistency]
---

# Repository 方法命名一致性

## 场景

调用 Repository 方法时，方法名与实际定义不匹配导致类型错误。

## 问题

代码中调用 `update_status(execution, ...)`，但 Repository 实际方法是 `update_status_by_id(execution_id, ...)`：

```python
# ❌ 方法不存在
await task_repo.update_status(execution, TaskStatus.FAILED, error_message="...")

# ✅ 正确的方法名
await task_repo.update_status_by_id(execution_id, TaskStatus.FAILED, error_message="...")
```

类型错误：
```
Cannot access attribute "update_status" for class "TaskExecutionRepository"
Attribute "update_status" is unknown
```

## 根本原因

1. **重构后方法名变更**：重构时统一了方法命名规范（添加 `_by_id` 后缀）
2. **调用方未同步更新**：部分调用代码仍使用旧方法名
3. **类型系统检测**：Pyright 捕获到方法不存在

## 修复方案

1. **全局搜索替换**
   ```bash
   # 查找所有使用旧方法名的地方
   grep -r "\.update_status(" backend/
   ```

2. **统一方法命名规范**
   - 按操作对象分类：`update_status_by_id` vs `update_status`
   - 值对象操作：`update(entity)` vs ID 操作：`update_by_id(id, ...)`

3. **类型系统驱动**
   - 依赖 Pyright 类型检查发现不一致
   - 不应使用 `# type: ignore` 忽略此类错误

## 预防措施

1. **重构后全局搜索**
   - 重构方法后，搜索所有调用点
   - 使用 IDE "Find References" 确保无遗漏

2. **类型检查作为防线**
   - 让 Pyright 报告此类错误
   - 不使用 `# type: ignore` 绕过检查

## 相关文件

- 文件: backend/app/infra/task/task_runner.py
- Repository: backend/app/infra/db/repository/task_execution_repository.py
- 提交: f0ab34f
