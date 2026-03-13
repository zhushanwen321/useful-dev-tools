# FastAPI Annotated 依赖注入模式支持

FastAPI 使用 `typing.Annotated` 和 `Depends` 实现依赖注入，rope 对这种模式的支持情况如下。

## 支持的操作

| 操作 | 状态 | 示例 |
|-----|------|------|
| AST 解析 | OK | 可以正确解析 `Annotated[...]` 语法 |
| patchedast | OK | 处理时无警告 |
| 识别函数参数 | OK | 可以正确识别 `db` 参数 |
| 重命名参数 | OK | `db` -> `database`，函数体内引用也会更新 |
| 查找引用 | OK | 可以找到参数的使用位置 |
| 重命名依赖函数 | OK | `get_session` -> `create_session` |

**示例代码**：

```python
from typing import Annotated
from fastapi import Depends

def get_session():
    """获取数据库会话"""
    pass

async def get_chat_service(
    db: Annotated[AsyncSession, Depends(get_session)]  # <- db 可重构
) -> ChatService:
    return ChatService(db)
```

**可执行的重构**：

```python
# 1. 重命名参数: db -> database
renamer = Rename(project, resource, offset)
changes = renamer.get_changes('database')

# 2. 重命名函数: get_chat_service -> create_chat_service

# 3. 重命名依赖函数: get_session -> create_session
```

## 有限制或不可用的操作

| 操作 | 状态 | 原因 |
|-----|------|------|
| 重命名 Annotated 内部类型 | 不可用 | 需要类型已定义/导入，否则报错 "not a resolvable python identifier" |
| 重命名 Depends 函数（定位到 def） | 不可用 | 不能定位到 `def` 关键字，需要定位到函数名 |
| 类型推断 Annotated 内部 | 警告 | 只返回左操作数类型 |

**限制说明**：

```python
# 无法直接重命名 Annotated 内部的类型
async def get_chat_service(
    db: Annotated[AsyncSession, Depends(get_session)]  # AsyncSession 无法直接重命名
) -> ChatService:
    pass

# 原因：AsyncSession 必须在项目中已定义或导入
# 解决方案：使用编辑器的全局重命名功能
```

## patchedast 已知限制

`rope.refactor.patchedast` 在处理某些 FastAPI 参数模式时可能失败。

| 模式 | 状态 | 说明 |
|------|------|------|
| 单个 Query/Body/Path | OK | `Query(description="...")` |
| 多个简单参数 | OK | 大多数情况正常 |
| 复杂嵌套参数 | 可能失败 | 多个带字符串的参数在同一函数 |

**示例**：

```python
# OK - 可处理
client_id: Annotated[str, Query(description="客户端ID")] = None

# OK - 可处理
async def simple(
    a: int,
    b: Annotated[str, Query(description="参数")] = None,
):
    pass

# 可能失败 - 复杂嵌套导致 patchedast token 匹配错误
async def complex_nested(
    client_id: Annotated[str, Query(description="客户端标识")] = None,
    user_id: Annotated[str, Query(description="用户标识")] = None,
    data: Annotated[dict, Body(description="数据")] = None,
):
    pass
```

**解决方案**：

```python
# 方案 1: 使用 resources 参数排除复杂文件
excluded_files = {"app/api/route/complex.py"}
all_files = project.get_python_files()
resources = [f for f in all_files if f.path not in excluded_files]
changes = renamer.get_changes('new_name', resources=resources)

# 方案 2: 简化参数，将 description 移到函数文档字符串
async def complex_nested(
    client_id: Annotated[str, Query()] = None,
    user_id: Annotated[str, Query()] = None,
):
    """API 端点

    Args:
        client_id: 客户端标识
        user_id: 用户标识
    """
    pass
```

**注意**：如果 patchedast 失败，rope 会抛出 `MismatchedTokenError`。建议在重构前先测试目标文件是否可以被正确处理。

## 工具函数：精确定位 Annotated 中的元素

```python
def find_annotated_element_offset(resource, element_name):
    """
    在 Annotated 类型提示中查找元素的偏移量

    Args:
        resource: rope 资源对象
        element_name: 要查找的元素名称（如 'AsyncSession', 'get_session'）

    Returns:
        元素的偏移量，未找到返回 None
    """
    import re
    content = resource.read()

    # 匹配 Annotated[X, ...] 或 Annotated[..., X, ...] 中的 X
    patterns = [
        rf'Annotated\[{element_name}[, \]]',  # 第一个参数
        rf'[, ]+{element_name}[, \]]',         # 后续参数
    ]

    for pattern in patterns:
        match = re.search(pattern, content)
        if match:
            start = match.start() + match.group().index(element_name)
            return start

    return content.find(element_name) if element_name in content else None


# 使用示例
offset = find_annotated_element_offset(resource, 'AsyncSession')
if offset:
    renamer = Rename(project, resource, offset)
    changes = renamer.get_changes('DatabaseSession')
```

## FastAPI 项目最佳实践

**推荐工作流程**：

1. **代码结构重构** - 使用 rope
   - 重命名函数、类、参数
   - 提取方法、内联变量
   - 移动模块、重组代码

2. **类型检查** - 使用 mypy/pyright
   - 验证类型注解正确性
   - 检查依赖注入类型匹配

3. **代码格式化** - 使用 ruff/black
   - 统一代码风格
   - 自动排序导入

**注意事项**：

- `Annotated` 内部未导入的类型无法直接重构
- 重命名依赖函数时，确保定位到函数名而非 `def` 关键字
- 函数参数重命名会自动更新函数体内的引用
- rope 会正确处理跨文件的依赖注入函数重命名
