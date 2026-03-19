# Task Group Plan

## 基本信息

| 字段 | 值 |
|------|-----|
| **生成时间** | {{TIMESTAMP}} |
| **输入来源** | {{INPUT_SOURCE}} |
| **输出目录** | {{OUTPUT_DIR}} |

## 执行摘要

| 指标 | 数值 |
|------|------|
| 总任务数 | {{TOTAL_TASKS}} |
| 分组数 | {{TOTAL_GROUPS}} |
| 并行组数 | {{PARALLEL_GROUPS}} |
| 串行组数 | {{SEQUENTIAL_GROUPS}} |

## 分组详情

{{#each GROUPS}}
### Group {{inc @index}}: {{name}}

**执行模式**: {{execution_mode}}
**前置依赖**: {{#if dependencies}}{{{dependencies}}}{{else}}无{{/if}}
**预估上下文大小**: ~{{estimated_tokens}} tokens
**任务列表**:

{{#each tasks}}
{{inc @index}}. {{description}}
{{/each}}

---

{{/each}}

## 执行顺序

### 阶段 1：并行执行

{{#each parallel_groups}}
- [ ] **Group {{group_number}}**: {{group_name}}
  - 任务: {{task_summary}}
{{/each}}

### 阶段 2：串行执行（按依赖顺序）

{{#each sequential_groups}}
- [ ] **Group {{group_number}}**: {{group_name}}
  - 前置依赖: {{dependencies}}
  - 任务: {{task_summary}}
{{/each}}

## 原始输入

```markdown
{{original_input}}
```

## 附录：分组依据

### 依赖关系图

```
{{dependency_graph}}
```

### 上下文规模估算

| 任务 | 预估 tokens | 分组理由 |
|------|-------------|----------|
{{#each task_estimates}}
| {{task_name}} | ~{{tokens}} | {{reason}} |
{{/each}}
