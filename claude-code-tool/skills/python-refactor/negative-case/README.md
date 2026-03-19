# 负向用例库

记录使用 rope 重构时遇到的问题及其解决方案，避免重复踩坑。

## 目录结构

```
negative-case/
├── README.md                        # 本说明文件
└── raw-case/                        # 原始用例目录
    └── {问题摘要}/                   # 按问题摘要命名
        ├── analysis.md              # 问题分析和解决方案
        ├── case_script.py           # 出错的脚本
        ├── case_output.txt          # 完整的错误输出
        └── case_src/                # 复现问题的最小源代码（可选）
```

## 用例命名规范

- 目录名：使用简短的中英文描述问题核心
- 命名示例：
  - `MoveModule报错not-under-version-control`
  - `重命名时找不到模块引用`
  - `get_source_folders性能问题`

## analysis.md 必须包含的内容

```markdown
# 用例标题

## 问题概述

简要描述遇到的问题（一句话）。

## 错误现象

```
粘贴错误信息或描述错误现象
```

## 根本原因

分析错误的根本原因。

## 解决方案

描述如何解决这个问题。

## 经验总结

- 关键词1：总结1
- 关键词2：总结2

## 相关文件

- `case_script.py` - 出错的脚本
- `case_output.txt` - 完整的错误输出
- `case_src/` - 复现问题的最小源代码
```

## 使用场景

1. **遇到报错时**：先搜索 `*/analysis.md` 中是否有类似问题
2. **解决问题后**：如果是新问题，记录到用例库中

## 搜索方式

```bash
# 搜索所有分析文件中的关键词
grep -r "关键词" negative-case/raw-case/*/analysis.md
```
