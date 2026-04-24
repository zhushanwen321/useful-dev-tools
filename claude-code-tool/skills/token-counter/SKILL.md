---
name: token-counter
description: |
  使用 DeepSeek V3 BPE tokenizer 计算 token 数量，附带 Claude Code chars/N 粗略估算对比。
  触发词："计算token"、"token数"、"token计数"、"统计token"、"token占用"、"提示词大小"、"prompt大小"。
  用于计算 skill、agent、command、CLAUDE.md、hooks 等 Claude Code 配置文件占用的 token 数量。
user-invocable: true
argument-hint: "[文件或目录路径]"
---

# Token Counter

计算 Claude Code 相关文件（skills、agents、commands、hooks、CLAUDE.md 等）的 token 占用。

## Claude Code 的 Token 计算策略

Claude Code 源码中**没有本地 tokenizer**，采用三层回退策略：

| 优先级 | 方式 | 精度 |
|--------|------|------|
| 1 | API `countTokens()` | 精确 |
| 2 | Haiku 发最小请求回退 | 精确（花一次 API 调用） |
| 3 | `chars / 4`（JSON: `chars / 2`） | 粗略 |

本工具使用 DeepSeek V3 BPE tokenizer 做本地计数（精度介于 1 和 3 之间），同时输出 Claude Code 风格的 chars/N 粗略估算供对比。

## 工具位置

```
claude-code-tool/custom-tools/deepseek_tokenizer/count_tokens.py
```

## 前置依赖

```bash
pip3 install transformers
```

## 使用方式

### 1. 统计单个文件

```bash
python3 claude-code-tool/custom-tools/deepseek_tokenizer/count_tokens.py --file <文件路径>
```

### 2. 统计多个文件

```bash
python3 claude-code-tool/custom-tools/deepseek_tokenizer/count_tokens.py --files <文件1> <文件2> ...
```

### 3. 统计目录下所有文本文件

```bash
python3 claude-code-tool/custom-tools/deepseek_tokenizer/count_tokens.py --dir <目录路径>
```

### 4. 统计文本字符串

```bash
python3 claude-code-tool/custom-tools/deepseek_tokenizer/count_tokens.py --text "要计算的文本"
```

### 5. 从管道读取

```bash
echo "some text" | python3 claude-code-tool/custom-tools/deepseek_tokenizer/count_tokens.py --stdin
```

## 输出字段说明

| 字段 | 含义 |
|------|------|
| `bpe` | DeepSeek V3 BPE tokenizer 计算的 token 数 |
| `chars` | 字符数 |
| `rough` | Claude Code 风格的 chars/N 估算（括号内为与 bpe 的偏差百分比） |
| `ratio` | bpe / chars，反映 token 密度 |

## 执行步骤

当用户要求计算 token 时：

1. **明确统计范围** — 确定用户想统计哪些文件：
   - 单个文件：`--file`
   - 某个 skill 目录：`--dir skills/<skill-name>`
   - 所有 skills：`--dir skills/`
   - 所有 agents：`--dir agents/`
   - CLAUDE.md 及其规则：`--files` 列出
   - 全部 Claude Code 配置：分别统计后汇总

2. **执行命令** — 使用 Bash 工具运行 `count_tokens.py`

3. **结果解读** — 向用户报告各文件 token 数、总占用、上下文窗口占比（按 200K 上下文估算）

## 常用统计场景

### 统计所有 skills

```bash
python3 claude-code-tool/custom-tools/deepseek_tokenizer/count_tokens.py --dir claude-code-tool/skills/
```

### 统计所有 agents

```bash
python3 claude-code-tool/custom-tools/deepseek_tokenizer/count_tokens.py --dir claude-code-tool/agents/
```

### 统计当前项目的 CLAUDE.md 及 rules

```bash
python3 claude-code-tool/custom-tools/deepseek_tokenizer/count_tokens.py --files CLAUDE.md .claude/rules/*.md
```

### 统计某个 skill 的完整内容

```bash
python3 claude-code-tool/custom-tools/deepseek_tokenizer/count_tokens.py --dir claude-code-tool/skills/<skill-name>/
```

## 精度说明

DeepSeek V3 BPE tokenizer（128K 词表）与 Claude 实际 tokenizer 有差异，但作为估算工具：
- 英文文本：误差通常在 5-10% 以内
- 中文文本：误差可能稍大，但趋势一致
- 主要用途是**比较不同文件的相对大小**，而非精确计量
- `rough` 列展示 Claude Code 源码中 chars/N 估算与 BPE 计数的偏差
