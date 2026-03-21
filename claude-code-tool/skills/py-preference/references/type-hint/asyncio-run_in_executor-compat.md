---
category: type-hint
created: 2026-03-20
tags: [asyncio, multiprocessing, type-ignore, DictProxy, Queue]
---

# asyncio.run_in_executor 类型兼容性

## 场景

使用 `asyncio.loop.run_in_executor()` 在进程池中执行函数时，传递 `DictProxy` 和 `Queue` 对象导致 Pyright 类型不兼容。

## 问题

`run_in_executor` 的类型签名不支持多进程共享对象类型：

```python
# ❌ Pyright 报告类型不兼容
result = await loop.run_in_executor(
    pool,
    _run_task_in_process_wrapper,
    task_name,
    execution_id,
    parameters,
    shared_state.cancel_flags,  # DictProxy[int, bool]
    shared_state.event_queue,     # Queue[Unknown]
    tushare_token,
)
```

类型错误：
```
Argument of type "tuple[..., DictProxy[int, bool], Queue[Unknown], ...]"
cannot be assigned to parameter "args" of type "_Ts@run_in_executor"
"DictProxy[int, bool]" is not assignable to "dict[int, bool]"
```

## 根本原因

1. **类型签名限制**：`run_in_executor` 的类型签名是 `run_in_executor(executor, func, *args: Ts)`
2. **多进程类型未定义**：`DictProxy` 和 `Queue` 不在类型签名支持的类型中
3. **运行时兼容**：实际运行时这些对象可以正确传递

## 选项

1. **使用 `# type: ignore[arg-type]`**
   - 优点：快速解决，保留运行时行为
   - 缺点：绕过类型检查

2. **自定义类型存根**
   - 创建 `loop.run_in_executor` 的类型存根扩展支持类型
   - 优点：类型安全
   - 缺点：增加维护成本

3. **避免使用 `run_in_executor`**
   - 使用其他进程池封装
   - 优点：避免类型问题
   - 缺点：重构成本高

## 选择

**选项 1**：使用 `# type: ignore[arg-type]`

```python
# 提交任务到进程池
# type: ignore[arg-type]  # DictProxy 和 Queue 在运行时兼容
result = await loop.run_in_executor(
    pool,
    _run_task_in_process_wrapper,
    task_name,
    execution_id,
    parameters,
    shared_state.cancel_flags,
    shared_state.event_queue,
    tushare_token,
)
```

## 理由

1. **工具限制**：这是标准库类型存根的限制，非代码问题
2. **运行时验证**：实际运行时多进程对象传递正确工作
3. **精确定位**：`[arg-type]` 只忽略参数类型，不影响其他检查
4. **最小改动**：不改变代码逻辑，只添加类型忽略

## 注意事项

- 添加清晰的注释说明为什么忽略
- 只在确信运行时行为正确的情况下使用
- 如果运行时出现问题，类型系统无法提供帮助

## 相关文件

- 文件: backend/app/infra/task/task_runner.py
- 提交: f0ab34f
- 多进程模块: multiprocessing.managers.DictProxy, multiprocessing.Queue
