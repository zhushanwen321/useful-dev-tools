---
allowed-tools: Bash, Grep, Glob, Agent, TaskOutput, TaskCreate, TaskUpdate
description: 审查和提交指定目录下的代码变更
---

## 你的任务

### 第一步：列出未提交的变更文件并智能分组

1. 运行 `git status --porcelain` 获取所有未提交的文件变更
2. 根据文件路径对变更进行智能分组（例如：按功能模块、文件类型等）
3. 显示分组列表，使用 AskUserQuestion 让用户选择要审查的分组

### 第二步：对选中的分组执行 code-reviewer（background task）

对每个选中的分组依次执行：

1. 启动 pr-review-toolkit:code-reviewer agent 审查该分组的代码变更
2. **使用 run_in_background: true 执行**
3. 记录返回的 agent ID（用于后续监控）

示例调用：
```
Agent 工具：
- subagent_type: pr-review-toolkit:code-reviewer
- run_in_background: true
- prompt: [审查指定分组的代码变更]
```

### 第三步：监控 code-reviewer 完成并启动 code-simplifier（background task）

当某个 code-reviewer agent 完成时：

1. 使用 TaskOutput 工具获取完成状态
2. 立即启动对应的 pr-review-toolkit:code-simplifier agent
3. **使用 run_in_background: true 执行**
4. 记录返回的 agent ID

### 第四步：监控 code-simplifier 完成并同步执行 commit

当所有分组的 simplifier 都完成后：

1. 同步执行 git add 和 git commit
2. 使用 commit 格式创建提交

## 执行流程

```
[分组1] ──(reviewer bg)──> 完成 ──(simplifier bg)──> 完成 ──> [同步 commit]
[分组2] ──(reviewer bg)──> 完成 ──(simplifier bg)──> 完成 ──┘
[分组3] ──(reviewer bg)──> 完成 ──(simplifier bg)──> 完成 ──┘
```

## 实现要点

1. **并行执行**：多个分组的 reviewer 可以同时运行
2. **链式触发**：每个 reviewer 完成后自动触发对应的 simplifier
3. **等待机制**：使用 TaskOutput(block: true) 等待每个 simplifier 完成
4. **同步提交**：所有 simplifier 完成后才执行 commit
