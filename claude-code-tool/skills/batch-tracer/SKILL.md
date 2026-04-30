---
name: batch-tracer
description: 批量代码分析调度器。对指定目录下的所有源代码文件执行完整的三阶段分析链路：code-trace（调用链路分析）→ issue-trace（问题验证）→ review-tracer（审查质量评估）。支持 --parallel n 参数设置并行度（默认 3），同一文件内三个阶段串行执行。所有报告保存到项目根目录的 .tracers/ 目录，并生成汇总统计报告和修复计划。当用户说"批量分析"、"batch-tracer"、"全量分析"、"扫描代码"、"分析整个目录"或需要对整个代码目录进行深度分析时使用此 skill。
---

# Batch Tracer - 批量代码分析调度器

对指定目录下的所有源代码文件执行完整的三阶段深度分析，自动调度并生成多维度报告和可执行的修复计划。

## 核心价值

这个 skill 解决的问题是：当你需要对整个代码目录进行深度分析时，手动逐个文件调用 code-trace、issue-trace、review-tracer 三个技能效率低下且容易遗漏。batch-tracer 自动完成整个流程，并生成结构化的报告目录和修复计划。

## 执行架构

```
用户输入目录
    ↓
Coordinator 扫描目录，识别所有源代码文件
    ↓
AI 生成批次名称（简短描述分析内容）
    ↓
并行启动多个文件分析任务（不同文件独立）
    ↓
每个文件任务内部串行执行：
    1. code-tracer Agent → code-trace 报告
    2. issue-tracer Agent → issue-trace 报告（依赖 code-trace）
    3. review-tracer-agent Agent → review-tracer 报告（依赖 issue-trace）
    ↓
所有任务完成后生成：
    - 汇总报告（batch-tracer.md）
    - 修复计划（fix-plan.md）
```

## 执行步骤

### 第一步：解析用户输入并扫描目录

1. **解析用户输入参数**：
   - 从用户输入中提取目录路径和可选参数
   - 支持 `--parallel n` 或 `-p n` 格式设置并行度（n 为正整数）
   - 默认并行度为 3
   - 示例输入：
     - `分析 backend/app/api/` → 使用默认并行度 3
     - `分析 backend/app/api/ --parallel 5` → 使用并行度 5
     - `扫描 frontend/src/components/ -p 2` → 使用并行度 2

2. **验证并解析目录**：
   - 验证目录是否存在
   - 提取有效目录路径

3. **使用 Glob 工具扫描代码文件**：
   - Python: `**/*.py`
   - TypeScript: `**/*.ts`, `**/*.tsx`
   - Vue: `**/*.vue`
   - JavaScript: `**/*.js`

4. **过滤掉不需要分析的文件**：
   - 测试文件：`**/test_*.py`, `**/*.test.ts`, `**/*.spec.ts`, `**/__tests__/**`
   - 配置文件：`**/*.config.*`, `**/.*rc*`, `**/jest.config.*`
   - 构建产物：`**/node_modules/**`, `**/.venv/**`, `**/dist/**`, `**/build/**`
   - 类型声明：`**/*.d.ts`
   - IDE 配置：`**/.vscode/**`, `**/.idea/**`

### 第二步：创建批次目录

1. 生成时间戳：`YYYYMMDD-HHMMSS`
2. **AI 生成批次名称**：
   - 根据分析目录路径和扫描到的文件，自动生成简短描述
   - 命名规范：2-4 个英文单词，用连字符连接
   - 示例：
     - `backend/app/api/chat/` → `chat-api-review`
     - `frontend/src/components/` 多个 Vue 组件 → `vue-components-analysis`
     - `backend/app/services/` → `service-layer-audit`
3. 创建批次目录结构：
   ```
   .tracers/
   └── batch-{timestamp}-{name}/
       ├── files/              # 各文件分析报告（子目录）
       ├── batch-tracer.md     # 汇总报告
       └── fix-plan.md         # 修复计划
   ```
4. 如果 `.tracers/` 目录不存在，先创建

### 第三步：并行启动文件分析任务

**并行度**：使用第一步解析出的并行度（默认 3，可通过 --parallel n 参数设置）

对于每个过滤后的文件，使用 Agent 工具启动一个独立的分析任务。不同文件之间并行执行，但同时运行的文件数量受限于解析出的并行度，超过的文件排队等待。

**实现方式**：
- 将文件列表分成批次，每批最多 {parallel_count} 个文件
- 使用 `run_in_background: true` 启动每批的文件分析任务
- 等待当前批次完成后再启动下一批次
- 如果用户未指定并行度，使用默认值 3

**每个文件分析任务的执行流程（串行）**：

对于每个文件，先创建其专用子目录：`{batch_dir}/files/{basename}/`

1. **阶段一：code-trace**
   - 调用 `batch-code-tracer` agent（subagent_type）
   - 传入参数：文件路径、文件专用目录
   - 等待完成，报告保存为 `{file_dir}/code-trace.md`

2. **阶段二：issue-trace**
   - 调用 `batch-issue-tracer` agent（subagent_type）
   - 传入参数：文件路径、code-trace 报告路径、文件专用目录
   - 等待完成，报告保存为 `{file_dir}/issue-trace.md`

3. **阶段三：review-tracer**
   - 调用 `batch-review-tracer` agent（subagent_type）
   - 传入参数：文件路径、issue-trace 报告路径、code-trace 报告路径、文件专用目录
   - 等待完成，报告保存为 `{file_dir}/review-tracer.md`

### 第四步：监控进度

实时向用户报告进度，格式如下：

```
[=====>                        ] 2/10 文件已完成
  ✓ backend/app/api/chat.py (3/3 阶段完成)
  ✓ backend/app/services/chat_service.py (3/3 阶段完成)
  → backend/app/api/completeness.py (1/3 阶段进行中...)
```

### 第五步：生成汇总报告

所有文件分析完成后，读取所有报告并生成汇总：

**汇总报告格式**：

```markdown
# 批量代码分析汇总报告

## 概述
- 批次名称：{timestamp}-{name}
- 批次时间：{timestamp}
- 分析目录：{directory}
- 扫描文件数：{total}
- 过滤文件数：{filtered}
- 分析文件数：{analyzed}
- 成功完成：{success}
- 失败：{failed}

## 文件清单

| 文件 | Code-Trace | Issue-Trace | Review-Tracer | 状态 |
|-----|-----------|-------------|---------------|------|
| backend/app/api/chat.py | ✓ | ✓ | ✓ | 完成 |
| backend/app/services/x.py | ✓ | ✗ | - | 失败 |

## 问题汇总

### 严重问题（8-10分）
来自各文件的 issue-trace 报告...

### 一般问题（5-7分）
...

### 轻微问题（1-4分）
...

## 审查质量评估

- 平均准确性得分：{X/10}
- 平均完整性得分：{X/10}
- 平均实用性得分：{X/10}

## 错误记录
如有文件分析失败，记录错误信息...
```

**汇总报告保存路径**：`{batch_dir}/batch-tracer.md`

### 第六步：生成修复计划

基于所有报告中的问题，生成可执行的修复计划：

**修复计划格式**：

```markdown
# 代码修复计划

## 概述
- 批次：batch-{timestamp}-{name}
- 生成时间：{timestamp}
- 严重问题数：{N}
- 一般问题数：{N}
- 轻微问题数：{N}

## 优先修复（8-10分）

按优先级排序的严重问题列表。

| 优先级 | 问题描述 | 文件 | 行号 | 修复建议 |
|--------|----------|------|------|----------|
| P0 | {问题描述} | {file} | {line} | {建议} |

## 计划修复（5-7分）

中等问题列表，按影响范围排序。

| 优先级 | 问题描述 | 文件 | 行号 | 修复建议 |
|--------|----------|------|------|----------|
| P1 | {问题描述} | {file} | {line} | {建议} |

## 可选优化（1-4分）

轻微问题和优化建议。

| 问题描述 | 文件 | 优化建议 |
|----------|------|----------|
| {问题描述} | {file} | {建议} |

## 执行建议

1. 先处理所有 P0 级别问题
2. 根据项目进度安排 P1 级别问题
3. 可选优化可在重构时处理
```

**修复计划保存路径**：`{batch_dir}/fix-plan.md`

### 第七步：输出结果

向用户报告：
1. 批次目录路径
2. 汇总统计信息
3. 如有失败，列出失败文件及原因

## Agent 通信协议

当调用 subagent 时，使用以下 prompt 格式：

**batch-code-tracer**:
```
分析文件 {filepath} 的调用链路和数据流。

要求：
- 报告保存到：{file_dir}
- 报告命名格式：code-trace.md
- 完整执行 code-trace 技能的所有步骤
```

**batch-issue-tracer**:
```
根据 code-trace 报告验证问题的真实性。

Code-trace 报告：{code_trace_report_path}
原始文件：{filepath}
文件专用目录：{file_dir}

要求：
- 报告命名格式：issue-trace.md
- 完整执行 issue-trace 技能的所有步骤
```

**batch-review-tracer**:
```
评估 issue-trace 报告的审查质量。

Issue-trace 报告：{issue_trace_report_path}
Code-trace 报告：{code_trace_report_path}
原始文件：{filepath}
文件专用目录：{file_dir}

要求：
- 报告命名格式：review-tracer.md
- 完整执行 review-tracer 技能的所有步骤
```

## 工具使用

- **Glob**: 扫描目录文件
- **Agent**: 调用 subagent（batch-code-tracer、batch-issue-tracer、batch-review-tracer）
- **Read**: 读取生成的报告（用于汇总）
- **Write**: 生成汇总报告
- **Bash**: 创建目录、验证路径

## 输出规范

### 报告目录结构

```
.tracers/
└── batch-{timestamp}-{name}/
    ├── batch-tracer.md           # 汇总报告
    ├── fix-plan.md               # 修复计划
    └── files/                    # 各文件分析报告
        ├── {basename1}/
        │   ├── code-trace.md
        │   ├── issue-trace.md
        │   └── review-tracer.md
        └── {basename2}/
            ├── code-trace.md
            ├── issue-trace.md
            └── review-tracer.md
```

### 报告命名格式

**批次目录**：`batch-{timestamp}-{name}/`
- timestamp: `YYYYMMDD-HHMMSS`
- name: AI 生成的简短描述（2-4个英文单词，连字符连接）

**文件子目录**：`files/{basename}/`
- basename: 源文件的基本名（不含路径和扩展名），特殊字符替换为下划线

**分析报告**：
- code-trace: `code-trace.md`
- issue-trace: `issue-trace.md`
- review-tracer: `review-tracer.md`

**汇总文件**：
- 汇总报告: `batch-tracer.md`
- 修复计划: `fix-plan.md`

## 错误处理

1. **单个文件失败不影响其他文件**：记录错误，继续处理其他文件
2. **超时处理**：如果某个文件分析时间过长（超过 5 分钟），跳过该文件
3. **Subagent 失败**：如果某个 subagent 调用失败，记录并继续
4. **汇总完整性**：汇总报告包含所有文件的成功/失败状态

## 注意事项

1. **并发控制**：并行度默认为 3，可通过 --parallel n 或 -p n 参数设置（n 为正整数），同时最多处理 n 个文件，其余文件排队等待
2. **参数解析**：优先从用户输入中提取 --parallel 或 -p 参数，格式支持 `--parallel 5`、`-p 5` 等
3. **进度反馈**：每完成一个文件就更新进度，不要等到全部完成
4. **目录验证**：确保用户提供的是有效目录，不是文件
5. **报告路径**：所有报告必须保存在批次目录下，便于管理
6. **时间戳一致性**：同一批次使用相同的时间戳
7. **中文输出**：所有报告和汇总使用中文

## 完成后向用户报告

```
批量分析完成！

批次目录：.tracers/batch-{timestamp}-{name}/
分析文件：{N} 个
成功完成：{N} 个
失败：{N} 个

汇总报告：.tracers/batch-{timestamp}-{name}/batch-tracer.md
修复计划：.tracers/batch-{timestamp}-{name}/fix-plan.md

问题统计：
- 严重问题（8-10分）：{N} 个
- 一般问题（5-7分）：{N} 个
- 轻微问题（1-4分）：{N} 个
```

如有失败，列出失败文件及原因。
