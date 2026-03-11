---
name: qwen-fast-coder
description: |
  使用 Qwen Code 无头模式执行快速、规则化的代码改动。使用场景：(1) 移动文件并自动更新 import，(2) 批量重构变量名/方法名，(3) 简单的代码格式化/规范化，(4) 其他规则化的批量代码修改。触发词："/qwen"、"快速改动"、"qwen-fast"。
user-invocable: true
---

# Qwen Fast Coder

使用 Qwen Code 的无头模式（headless mode）执行快速、规则化的代码改动。

## 触发条件

用户说以下任一短语时触发：
- `/qwen`
- `/qwen-fast-coder`
- "快速改动"
- "qwen-fast"
- "用 qwen 改"

## 适用场景

此技能适用于**简单、规则化的代码改动**，不适合复杂的功能开发：

| 适用场景 | 不适用场景 |
|---------|-----------|
| 移动文件并更新 import | 复杂的功能实现 |
| 批量重命名变量/方法 | 架构重构决策 |
| 代码格式规范化 | 需要 Claude Code 能力的任务 |
| 批量修改配置 | 需要深度理解上下文的修改 |
| 简单的代码模板生成 | 需要 MCP 工具的任务 |

## 执行步骤

### 步骤 1: 确认任务类型

首先确认用户请求是否适合此技能：

```
如果任务涉及：
- 复杂逻辑实现
- 需要理解项目架构
- 需要使用 MCP 工具（数据库、浏览器等）
- 需要交互式确认

则建议用户直接使用 Claude Code，不要调用 qwen。
```

### 步骤 2: 构建 qwen 命令

根据任务类型构建合适的命令：

#### 基本命令格式

```bash
qwen -p "<prompt>" --yolo
```

#### 常用参数

| 参数 | 说明 | 示例 |
|------|------|------|
| `-p, --prompt` | 要执行的提示（必填） | `-p "重命名变量 foo 为 bar"` |
| `--yolo, -y` | 自动批准所有操作（推荐） | `--yolo` |
| `--output-format, -o` | 输出格式 | `-o json` |
| `--all-files, -a` | 包含所有文件 | `--all-files` |
| `--include-directories` | 指定包含目录 | `--include-directories src,lib` |

### 步骤 3: 执行命令

使用 Bash 工具执行 qwen 命令：

```bash
qwen -p "<用户的改动请求>" --yolo
```

### 步骤 4: 验证结果

执行完成后，检查变更：

```bash
git status --short
git diff --stat
```

如有必要，展示具体变更内容。

## 常用任务模板

### 移动文件并更新 import

```bash
qwen -p "将 src/old/path.ts 移动到 src/new/path.ts，并更新所有文件中的 import 语句" --yolo
```

### 批量重命名变量

```bash
qwen -p "在整个项目中将变量名 'oldName' 重命名为 'newName'" --yolo
```

### 批量重命名方法

```bash
qwen -p "将所有文件中的方法名 'getOldData' 重命名为 'fetchNewData'" --yolo
```

### 代码格式规范化

```bash
qwen -p "将 src/ 目录下所有 Python 文件的 import 语句按 isort 标准排序" --yolo
```

### 批量修改配置

```bash
qwen -p "将所有 .env.example 文件中的 API_KEY 改为 API_TOKEN" --yolo
```

### 从标准输入处理

```bash
cat some_file.py | qwen -p "将这个文件中的所有 print 语句改为 logging.info" --yolo
```

## 高级用法

### 指定工作目录

```bash
qwen -p "在 backend/ 目录下将所有 async def 改为同步函数" --include-directories backend --yolo
```

### JSON 输出（用于脚本集成）

```bash
result=$(qwen -p "统计项目中的 TODO 注释数量" --output-format json --yolo)
echo "$result" | jq -r '.response'
```

### 继续上一次会话

```bash
qwen --continue -p "继续上次的修改，现在处理 test/ 目录" --yolo
```

## 注意事项

1. **--yolo 模式**：此技能默认使用 `--yolo` 参数自动批准所有操作，确保任务确实是简单、规则化的
2. **适用边界**：如果 qwen 执行失败或结果不理想，建议用户切换到 Claude Code
3. **大文件处理**：对于非常大的文件或大量文件，可能需要分批处理
4. **验证变更**：执行后务必检查 git diff 确认变更符合预期

## 与 Claude Code 的协作

当遇到以下情况时，建议切换到 Claude Code：

```
"这个任务比较复杂，建议使用 Claude Code 的完整能力来处理。
你可以直接告诉我你的需求，我会用 Claude Code 来完成。"
```

## 示例对话

**用户**: /qwen 把 utils/helper.ts 移到 lib/helper.ts

**响应**:
好的，我来用 Qwen 执行这个文件移动任务。

```bash
qwen -p "将 utils/helper.ts 移动到 lib/helper.ts，并更新所有文件中的 import 语句" --yolo
```

[执行命令...]

完成！文件已移动，已更新 5 个文件中的 import 语句。
