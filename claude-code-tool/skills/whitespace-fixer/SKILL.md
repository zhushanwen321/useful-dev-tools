---
name: whitespace-fixer
description: 修复源代码文件中的缩进（tab/空格）和空白字符问题，确保 edit 工具的 oldText 能精确匹配。当 edit 操作因 whitespace 不匹配而失败、用户说"whitespace问题"、"tab空格问题"、"缩进错误"、"indentation mismatch"、"edit失败"、"oldText不匹配"、"Could not find the exact text" 时使用此 skill。在执行任何多文件编辑任务前，也可以先运行此 skill 做预防性修复。支持 Python、Rust、TypeScript、JavaScript、Java、Go、C/C++、Vue、Ruby 等语言。
---

# Whitespace Fixer

解决 AI coding agent 使用 `edit` 工具时的经典痛点：**oldText 因 tab/空格不一致而无法精确匹配**。

核心原理：先规范化文件，再执行 edit。脚本用纯 Python 3 stdlib 实现，无外部依赖。

## 什么时候用

1. **edit 失败** — 报错 `Could not find the exact text in <file>. The old text must match exactly including all whitespace and newlines.`
2. **预防性修复** — 在对文件做批量 edit 之前，先规范化 whitespace
3. **CI/检查** — 检查项目文件是否有 whitespace 问题

## 快速修复（3 步走）

### 第 1 步：检测问题

```bash
python3 ~/.agents/skills/whitespace-fixer/scripts/fix_whitespace.py <file>
```

这会 dry-run 显示所有 whitespace 问题，不会修改文件。

### 第 2 步：修复问题

```bash
python3 ~/.agents/skills/whitespace-fixer/scripts/fix_whitespace.py --fix <file>
```

这会就地修复文件。

### 第 3 步：重新执行 edit

修复后重新执行之前失败的 edit 操作。此时 oldText 应该能精确匹配。

## 常见场景

### 场景 1：edit 失败时一键修复

当看到 `Could not find the exact text` 错误时：

```bash
# 1. 先修复 whitespace
python3 ~/.agents/skills/whitespace-fixer/scripts/fix_whitespace.py --fix /path/to/file.ts

# 2. 重新执行 edit（此时 whitespace 已规范化，oldText 能匹配）
```

### 场景 2：批量修复整个目录

```bash
# 修复所有源代码文件
find src -type f \( -name "*.py" -o -name "*.ts" -o -name "*.rs" -o -name "*.java" \) \
  -exec python3 ~/.agents/skills/whitespace-fixer/scripts/fix_whitespace.py --fix {} +
```

### 场景 3：查看不可见字符

调试时显示 tab (→) 和 space (·)：

```bash
python3 ~/.agents/skills/whitespace-fixer/scripts/fix_whitespace.py --show-invisibles <file>
```

### 场景 4：提取精确文本用于 edit

当你需要从文件中提取某几行的精确文本（包含原始 whitespace）：

```bash
# 提取第 10-20 行的精确文本
python3 ~/.agents/skills/whitespace-fixer/scripts/fix_whitespace.py --extract 10:20 <file>
```

### 场景 5：只修复特定类型的问题

```bash
# 只修复 tab 问题
python3 ~/.agents/skills/whitespace-fixer/scripts/fix_whitespace.py --fix --issues tabs <file>

# 只修复 trailing whitespace
python3 ~/.agents/skills/whitespace-fixer/scripts/fix_whitespace.py --fix --issues trailing <file>

# 修复 tab 和 trailing
python3 ~/.agents/skills/whitespace-fixer/scripts/fix_whitespace.py --fix --issues tabs,trailing <file>
```

## 脚本完整参数

```
python3 fix_whitespace.py [--fix] [--check] [--json] [--show-invisibles]
                          [--issues CATEGORIES] [--indent-size N] [--use-tabs]
                          [--extract START:END]
                          <file> [file ...]
```

| 参数 | 说明 |
|------|------|
| `--fix` | 就地修复文件（默认 dry-run） |
| `--check` | 有问题时返回 exit code 1（CI 用） |
| `--json` | JSON 格式输出 |
| `--show-invisibles` | 显示 tab(→) 和 space(·) |
| `--issues` | 只修复指定类别：`tabs,trailing,mixed-indent,crlf,final-newline,blank-lines` |
| `--indent-size N` | 强制缩进大小（如 2 或 4） |
| `--use-tabs` | 使用 tab 而非空格 |
| `--extract START:END` | 提取指定行号的精确文本（1-indexed, inclusive） |

## 检测和修复的问题类型

| 类别 | 说明 |
|------|------|
| `tabs` | Hard tab ↔ Spaces 转换 |
| `trailing` | 行尾多余空格/tab |
| `mixed-indent` | 同一行前导空白混用 tab 和 space |
| `crlf` | Windows CRLF 换行符 → LF |
| `final-newline` | 确保文件以换行符结尾 |
| `blank-lines` | 连续 3+ 空行压缩为 2 行 |

## 多行字符串保护

脚本会自动识别并**跳过**多行字符串内部的 whitespace，不对其做任何修改：

| 语言 | 保护的语法 |
|------|----------|
| Python | `"""..."""` 和 `'''...'''` |
| Rust | `r#"..."#`、`r##"..."##` 等 raw string |
| JS/TS | 反引号模板字面量 `` ` ... ` `` |
| Ruby | heredoc 和多行字符串 |

这意味着你可以放心对包含内嵌代码片段、SQL 语句、HTML 模板的文件运行修复，不会破坏字符串内容。

## 自动检测逻辑

脚本按以下优先级确定缩进风格：

1. **CLI 参数** `--indent-size` / `--use-tabs`
2. **`.editorconfig`** 文件配置
3. **文件内容启发式** — 分析前 500 行的缩进模式
4. **语言默认值** — Python 4空格, TS/JS 2空格, Rust 4空格, Java 4空格, Go hard tabs

## 各语言默认缩进

| 语言 | 缩进 | 文件扩展名 |
|------|------|-----------|
| Python | 4 spaces | `.py` `.pyw` `.pyi` |
| Rust | 4 spaces | `.rs` |
| TypeScript | 2 spaces | `.ts` `.tsx` |
| JavaScript | 2 spaces | `.js` `.jsx` `.mjs` |
| Java | 4 spaces | `.java` |
| Go | tabs | `.go` |
| C/C++ | 4 spaces | `.c` `.h` `.cpp` `.hpp` |
| Vue | 2 spaces | `.vue` |
| Ruby | 2 spaces | `.rb` |
| YAML | 2 spaces | `.yml` `.yaml` |

## 注意事项

- **多行字符串保护不是万能的**：对于非常复杂的嵌套引号、字符串拼接等场景，保护可能会失效。修复前建议先 dry-run 检查 diff
- **备份建议**：如果是重要文件，可以先 dry-run 确认再 `--fix`
- **Git 集成**：在 git 管理的项目中，修复后可以用 `git diff` 检查变更

## 工作流建议

### 在批量 edit 前做预防性修复

```bash
# 一次性修复所有目标文件
for f in src/foo.ts src/bar.ts src/baz.ts; do
  python3 ~/.agents/skills/whitespace-fixer/scripts/fix_whitespace.py --fix "$f"
done

# 然后再做 edit 操作
```

### 与 CI 集成

```bash
# CI pipeline 中检查
find src -type f \( -name "*.py" -o -name "*.ts" -o -name "*.rs" \) \
  -exec python3 ~/.agents/skills/whitespace-fixer/scripts/fix_whitespace.py --check {} +
```

## 为什么这个 skill 有用

AI agent（如 Claude、GPT）在生成 edit 操作时，最常见的问题是：

1. **把 tab 当空格** — AI 看到缩进时无法区分 tab 和空格，导致 oldText 不匹配
2. **行尾空白不可见** — 文件可能有 trailing space/tab，但 AI 生成的 oldText 里没有
3. **CRLF 换行** — Windows 编辑器产生的文件，AI 按 LF 匹配就会失败
4. **不一致缩进** — 文件内部混用 tab 和 space，AI 假设了一致性

脚本通过规范化这些不一致，让文件进入一个「干净状态」，此时 AI 的 oldText 就能精确匹配了。
