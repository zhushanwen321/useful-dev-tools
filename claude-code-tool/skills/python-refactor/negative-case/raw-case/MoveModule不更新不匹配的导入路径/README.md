# MoveModule 不更新不匹配的导入路径

## 问题说明

当使用 `rope.refactor.move.MoveModule` 移动 Python 模块时，如果某些代码文件中的导入语句指向的路径与实际模块位置不匹配，Rope 不会更新这些导入语句。

## 目录结构

```
MoveModule不更新不匹配的导入路径/
├── analysis.md      # 详细的问题分析和解决方案
├── case_script.py   # 重现问题的 Python 脚本
├── case_output.txt  # 脚本运行输出
├── case_src/        # 最小复现示例的源代码
└── README.md        # 本文件
```

## 快速重现

运行脚本重现问题：

```bash
python case_script.py
```

## 核心问题

**重构前的导入**：
```python
from app.domain.supporting.calculation.indicator.technical.atr import calculate_atr
```

**实际文件位置**：
```
calc/atr.py  # 不在 indicator/technical/ 目录下！
```

**执行移动**：
```python
MoveModule(project, atr_resource)  # calc/atr.py -> calc/util/atr.py
```

**结果**：
- ✅ 正确的导入（`from calc.atr`）被更新为 `from calc.util.atr`
- ❌ 错误的导入（`from indicator.technical.atr`）**没有被更新**

## 根本原因

Rope 的 `MoveModule` 只会更新那些**直接引用被移动模块**的导入语句：
- Rope 知道移动的是 `calc.atr`
- Rope 只搜索 `from calc.atr import ...` 或 `import calc.atr`
- Rope 无法识别 `indicator.technical.atr` 是对 `calc.atr` 的引用

## 解决方案

参见 `analysis.md` 中的详细解决方案。

## 相关问题

- 类似问题可能出现在 `Rename` 操作中
- 任何依赖导入路径分析的重构操作都可能受影响
