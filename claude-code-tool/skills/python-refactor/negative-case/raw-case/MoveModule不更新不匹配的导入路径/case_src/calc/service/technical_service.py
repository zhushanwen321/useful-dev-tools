"""技术指标服务。"""

# ⚠️ 问题：这里的导入路径与实际文件位置不匹配
# 实际文件在 calc/atr.py，但导入写的是 indicator.technical.atr
from app.domain.supporting.calculation.indicator.technical.atr import calculate_atr

def calculate_all(prices):
    """计算所有技术指标。"""
    return calculate_atr(prices.high, prices.low, prices.close)
