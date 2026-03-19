"""
最小复现代码示例

包含带类型注解的函数参数，用于触发 rope patchedast 的 _arg 处理问题
"""


def process_data(
    items: list[str],
    config: dict[str, str] | None = None,
) -> str:
    """处理数据的函数"""
    if config is None:
        return "no config"

    result = []
    for item in items:
        result.append(item.upper())

    return ", ".join(result)


async def fetch_user(
    user_id: int,
    include_details: bool = True,
) -> dict:
    """获取用户信息"""
    return {"id": user_id, "name": "test"}
