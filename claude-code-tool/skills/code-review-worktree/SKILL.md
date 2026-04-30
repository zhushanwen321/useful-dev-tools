---
name: code-review-worktree
description: >
  对当前 worktree 的变更进行全面的代码审查。自动识别项目语言，并发运行通用 code-review
  和语言特定的 taste-check（ts-taste-check / rust-taste-check），汇总问题清单后分组修复。
  当用户说"代码审查"、"review代码"、"审查变更"、"code-review-worktree"、"检查代码质量"、
  "审查一下"时使用此 skill。即使用户只是说"帮我看看代码有没有问题"，也应考虑触发。
---

# Code Review Worktree

对当前 worktree 的变更进行全面代码审查和修复。

## 脚本

### review-context.sh — 收集审查上下文

```bash
review-context.sh [--against main] [--staged] [--path <dir>]
```

收集语言检测、diff 统计、lint 结果、工作量评估、文件分组建议，输出 JSON。

| 参数 | 说明 |
|------|------|
| `--against <ref>` | 对比基准分支，默认 `main` |
| `--staged` | 只检查已暂存的变更（`git diff --cached`） |
| `--path <dir>` | 限制审查范围到指定目录 |

**用法示例**：

```bash
# 审查当前分支相对于 main 的所有变更
bash ~/.claude/skills/code-review-worktree/review-context.sh

# 只审查已暂存的变更
bash ~/.claude/skills/code-review-worktree/review-context.sh --staged

# 审查指定目录
bash ~/.claude/skills/code-review-worktree/review-context.sh --path src/proxy
```

**输出示例**：

```json
{
  "total_files": 8,
  "total_insertions": 234,
  "total_deletions": 56,
  "languages": [
    {"language": "TypeScript/Vue", "agent": "ts-taste-check", "file_count": 6, "files": "src/proxy/handler.ts src/types.ts ..."},
    {"language": "Other", "agent": "code-reviewer", "file_count": 2, "files": "package.json CLAUDE.md"}
  ],
  "effort": "simple",
  "suggested_groups": [
    {"group": 1, "directory": "src/proxy", "files": "handler.ts types.ts resilience.ts", "file_count": 3},
    {"group": 2, "directory": "src/metrics", "files": "extractor.ts transform.ts", "file_count": 2}
  ],
  "lint": {
    "tool": "eslint",
    "result": "failed",
    "output": "...eslint errors..."
  }
}
```

**脚本行为**：

1. 统计 diff 文件数、插入/删除行数
2. 按文件扩展名检测语言（`.ts/.tsx/.vue` → TypeScript, `.rs` → Rust, `.py` → Python）
3. 评估工作量：`simple`（<10 文件 <500 行）/ `medium`（<30 文件 <3000 行）/ `complex`
4. 按目录自动分组，每组最多 5 个文件
5. 运行 lint：检测到 `eslint.config.*` 则 `npx eslint`；检测到 `Cargo.toml` 则 `cargo clippy`

## AI 操作流程

### 步骤 1: 运行 review-context.sh 收集上下文

```bash
bash ~/.claude/skills/code-review-worktree/review-context.sh
```

从输出中获取：
- `effort`：工作量级别，决定 subagent 使用策略
- `languages`：需要哪些审查 agent
- `suggested_groups`：文件分组建议
- `lint.result`：lint 是否已通过

### 步骤 2: 根据工作量决定策略

| effort | 文件数 | 策略 |
|--------|--------|------|
| `simple` | <10 | 主会话直接审查，不用 subagent |
| `medium` | 10-30 | 按 `suggested_groups` 每组分派 1 个 subagent，并发 <= 3 |
| `complex` | >30 | 先拆分为功能模块，每个模块独立 subagent |

向用户报告评估结果。

### 步骤 3: 并行审查（subagent）

对每种语言和每个分组，使用对应的 agent：

| 语言 | Agent | 说明 |
|------|-------|------|
| TypeScript/Vue | `ts-taste-check` | 品味审查（P0-P3） |
| Rust | `rust-taste-check` | 品味审查（P0-P2） |
| Python / 通用 | `code-reviewer` | bug/逻辑/性能/安全 |
| 所有语言 | `code-reviewer` | 通用审查可跟品味检查并行 |

**每个 subagent 必须传递的上下文**：
- `git diff` 输出（或文件路径让其读取）
- 变更文件列表
- 品味文档路径（如 `~/Code/coding_config/.codetaste/ts/taste.md`）

### 步骤 4: 汇总问题清单

从所有 subagent 输出提取问题，按 P0/P1/P2 汇总。展示给用户确认。

### 步骤 5: 分组修复（subagent）

用户确认后，按文件分组使用 `code-fixer` agent 修复。每组不超过 5 个文件、1000 行。

### 步骤 6: 验证

```bash
npx eslint --max-warnings=0 <modified-files>
npm test 2>&1 | tail -20
```

## Subagent 使用规范

1. 先评估再分派：`simple` 任务不用 subagent
2. 并发不超过 3 个 subagent
3. 每个 subagent 修改不超过 5 个文件
4. 上下文必须完整（diff + 文件列表 + 品味文档路径）
