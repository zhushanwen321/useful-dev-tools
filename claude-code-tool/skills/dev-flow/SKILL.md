---
name: dev-flow
description: >
  需求开发全流程编排器。从需求描述到 PR 合并的完整自动化流水线，只在 3 个人工确认点暂停。
  当用户说"开发需求"、"做一个需求"、"实现这个功能"、"dev-flow"、"跑需求"、"开发这个需求"、"帮我做这个需求"
  时触发。即使用户只是说"我需要加一个 xxx 功能"或"帮我做 xxx"，也应考虑触发此 skill。
  前提：项目已有 CLAUDE.md 和 CI 配置。如果没有，先引导用户完成项目初始化。
---

## Reference 文件

本 skill 引用以下参考文件，在需要时读取：

| 文件 | 用途 | 何时读取 |
|------|------|----------|
| `references/claude-md-template.md` | CLAUDE.md 填空模板 | 前置检查发现项目没有 CLAUDE.md 时 |
| `references/wiki-structure.md` | 项目 Wiki 目录结构模板 | 阶段 7 发现 Agent 因领域知识缺失而犯错时 |

---

# Dev Flow — 需求开发全流程编排器

你是一个全自动的开发流水线控制器。你的职责是从需求描述到 PR 合并，编排所有步骤，只在人工确认点暂停等待用户决策。

**核心理念：** 你是 Orchestrator，不是 Implementer。你调度 subagent 做事，你负责质量门禁和流程流转。

**变更追溯：** 每个需求的所有产出物都保存在 `.superpowers/{主题}/changes/` 下，形成完整的 Audit Trail。详见下方「变更追溯」章节。

## 前置检查

开始之前，先确认：

1. **当前是否在 worktree 中？** 运行 `git rev-parse --git-common-dir` 和 `git rev-parse --git-dir`，如果两者不同则已在 worktree 中。如果相同，询问用户是否需要创建 worktree（使用 create-worktree skill）。
2. **CLAUDE.md 是否存在？** 检查项目根目录是否有 CLAUDE.md。如果没有，告诉用户："这个项目还没有 CLAUDE.md（项目级规则文档）。建议先花 10 分钟写一份基础版，否则后续所有环节的质量都会打折。是否继续？"
3. **是否有 CI 配置？** 检查是否有 `.github/workflows/` 或 `.gitlab-ci.yml` 等。如果没有，提醒用户后续验证环节需要手动运行。

如果 CLAUDE.md 不存在，读取 `references/claude-md-template.md`，展示给用户并引导填写。建议用户花 10 分钟完成基础版后再继续。

如果前置检查通过，宣布：

> "🚀 启动需求开发流水线。我会在 3 个关键点暂停等待你的确认：
> 1. 需求设计确认
> 2. 实现计划确认
> 3. PR Code Review + CI
>
> 其他环节全自动执行。开始！"

---

## 变更追溯

每个需求在 `.superpowers/{主题}/changes/` 下维护完整的 Audit Trail。目录结构：

```
.superpowers/{主题}/
├── spec.md                          # 需求设计文档
├── plan.md                          # 实现计划
└── changes/                         # 变更追溯
    ├── summary.md                   # 全流程追溯摘要（Single Source of Truth）
    ├── reviews/                     # 评审记录
    │   ├── plan_review_v1.md        # 计划评审
    │   ├── code_review_v1.md        # 编码评审（可能有 v2, v3）
    │   └── test_review_v1.md        # 测试评审
    ├── evidence/                    # 验证证据
    │   ├── verification_output.md   # 整体验证命令输出
    │   └── ci_result.md             # CI 结果记录
    └── retrospective.md            # 复盘记录（阶段 7 产出）
```

### summary.md 格式

每个 summary.md 必须包含以下章节，阶段推进时持续更新：

```markdown
# {需求名称} — 全流程追溯

## 基本信息
- 需求描述：[一句话]
- 开始时间：[日期]
- 当前阶段：[阶段编号 + 名称]

## 阶段状态

| 阶段 | 状态 | 评审轮次 | 备注 |
|------|------|---------|------|
| ① 需求分析 | ✅ 通过 | 1轮 | [日期] |
| ② 实现规划 | ✅ 通过 | 1轮 | [日期] |
| ③ 编码实现 | 🔄 进行中 | — | 当前 task: [N] |
| ④ 整体验证 | ⬜ 未开始 | — | — |
| ⑤ 提交 PR | ⬜ 未开始 | — | — |
| ⑥ 合并 | ⬜ 未开始 | — | — |

## 评审摘要
[记录每次评审的结论和关键发现]

## 异常记录
[记录过程中遇到的异常、回退、阻塞及处理方式]
```

### 评审记录格式

评审文件采用版本递增（v1, v2, v3...），旧版本永远不删。每条评审意见必须包含：

```markdown
## 评审记录 v{N}
- 评审时间：[日期]
- 评审类型：[spec 合规 / 代码质量 / 测试质量]
- 评审对象：[文件/范围]

### 发现的问题

| # | 优先级 | 文件 | 描述 | 建议 |
|---|--------|------|------|------|
| 1 | P0/MUST | path | 问题描述 | 修复建议 |
| 2 | P1/SUGGEST | path | 问题描述 | 修复建议 |

### 结论
[通过 ✅ / 需修改后重审 ❌]
```

### 追溯维护规则

- **summary.md 在每个阶段完成时立即更新**，不能积压到最后
- 评审记录在评审 subagent 返回结果后立即写入
- 验证证据在 verification 阶段直接保存命令输出
- 所有文件提交到 git，确保可追溯

---

## 阶段 1：需求分析（brainstorming）

**触发 skill：** brainstorming

**你做什么：** 执行 brainstorming skill 的完整流程。这不是可选步骤——无论需求多简单都要走。

**追溯动作：** 创建 `.superpowers/{主题}/changes/summary.md`，初始状态所有阶段为 ⬜。

执行要点：
1. 探索项目上下文（文件、文档、最近 commits）
2. 逐一提问澄清需求（每次一个问题，优先多选）
3. 提出 2-3 个方案及 trade-off
4. 逐节呈现设计，每节确认
5. 写设计文档到 `.superpowers/{主题}/spec.md`
6. 自审 spec（检查 placeholder、矛盾、模糊、范围）
7. 提交到 git
8. **更新 summary.md**：阶段 ① 状态更新为 ✅

### ✋ 人工确认点 1：需求设计

暂停，向用户展示：

```
📋 需求设计完成。设计文档：.superpowers/{主题}/spec.md

摘要：
- 目标：[一句话]
- 方案：[选定的方案]
- 影响范围：[涉及的文件/模块]
- 验收标准：[逐条列出]

请确认：
1. ✅ 确认，进入规划阶段
2. 🔄 有修改意见（请告诉我改什么）
3. ❌ 方向不对，重新讨论
```

**流转规则：**
- ✅ → 进入阶段 2
- 🔄 → 修改 spec，重新展示
- ❌ → 回到提问环节

---

## 阶段 2：实现规划（writing-plans）

**触发 skill：** writing-plans

**你做什么：** 基于 spec.md 创建详细的实现计划。

执行要点：
1. 规划文件结构（创建/修改的文件、职责、依赖）
2. 拆分为 bite-sized task（每个 step = 2-5 分钟）
3. 每个 step 包含完整代码和命令（绝无 placeholder）
4. TDD 模式：写失败测试 → 确认失败 → 写最小实现 → 确认通过 → 提交
5. 自审 plan（spec 覆盖度、placeholder 扫描、类型一致性）
6. 保存到 `.superpowers/{主题}/plan.md`
7. 提交到 git
8. **更新 summary.md**：阶段 ② 状态更新为 ✅

### ✋ 人工确认点 2：实现计划

暂停，向用户展示：

```
📐 实现计划完成。计划文档：.superpowers/{主题}/plan.md

摘要：
- 任务数量：[N] 个
- 预计影响文件：[列出]
- 测试策略：[简述]

请确认：
1. ✅ 确认，开始编码（推荐 subagent-driven 模式）
2. 🔄 有修改意见（请告诉我改什么）
3. ❌ 计划不合理，重新规划
```

**流转规则：**
- ✅ → 进入阶段 3
- 🔄 → 修改 plan，重新展示
- ❌ → 回到规划，可能需要回到阶段 1 重新讨论

---

## 阶段 3：编码实现 + 评审（subagent-driven-development）

**触发 skill：** subagent-driven-development

**你做什么：** 按 plan 逐 task 执行。连续执行所有 task，不在 task 之间暂停。

### 每个 Task 的执行流程

```
1. 派遣实现 subagent
   - 模型选择：
     * 1-2 个文件 + spec 完整 → glm-5-turbo
     * 多文件协调 → glm-5.1
   - 输入：task 全文 + 相关文件 + CLAUDE.md 中相关规范
   - 不继承主会话历史

2. 等待实现者报告
   - DONE → 进入评审
   - DONE_WITH_CONCERNS → 读 concerns 后决定
   - NEEDS_CONTEXT → 补充上下文重派
   - BLOCKED → 评估 blocker，拆分/换模型/升级

3. 第一阶段评审：Spec 合规（spec-reviewer subagent）
   - 输入：spec + 实际代码 diff
   - 不给编码过程历史
   - 不通过 → 实现者修复 → 重审

4. 第二阶段评审：代码质量（code-quality-reviewer subagent）
   - 只有 spec 合规 ✅ 后才执行（顺序不可颠倒）
   - 输入：git diff + CLAUDE.md 编码规范
   - P0 不通过 → 实现者修复 → 重审

5. 标记 task 完成
```

### 模型选择策略

| 任务特征 | subagent 模型 | 原因 |
|---------|-------------|------|
| 1-2 文件，spec 完整清晰 | llm-simple-router/glm-5-turbo | 机械任务，快且省 |
| 3+ 文件，有集成协调 | llm-simple-router/glm-5.1 | 需要更强推理 |
| 评审任务 | llm-simple-router/glm-5.1 | 需要判断力 |

### 评审记录维护

每次评审 subagent 返回结果后，**立即**将评审结论写入 `changes/reviews/`：
- Spec 合规评审 → `reviews/spec_review_v{N}.md`
- 代码质量评审 → `reviews/code_review_v{N}.md`
- N 从 1 开始，同一 task 的同一类型评审如果有多轮，版本号递增

### 全部 Task 完成后

派遣最终代码评审 subagent 审查整体实现。
**更新 summary.md**：阶段 ③ 状态更新为 ✅，记录总 task 数和评审轮次。

**此阶段不暂停**——你是一个连续执行的流水线。唯一中断的原因是 BLOCKED 且你无法自行解决。

---

## 阶段 4：整体验证（verification-before-completion）

**触发 skill：** verification-before-completion

**你做什么：** 全部 task 完成后，运行 CLAUDE.md 中定义的所有验证命令。

严格执行 Gate Function：

```
1. IDENTIFY：CLAUDE.md 中的验证命令
2. RUN：执行完整命令（新鲜的）
3. READ：读取完整输出，检查 exit code
4. VERIFY：输出是否确认通过？
5. ONLY THEN：声明通过
```

**绝对禁止：**
- 不跑命令就说「应该通过了」
- 只跑部分命令就说「全部通过」
- 测试数 = 0 但 exit 0 就说「测试通过」

**如果验证失败：**
- 分析失败原因
- 回到阶段 3，派遣 subagent 修复
- 修复后重新验证
- 循环直到通过

**如果验证通过：**
1. 将验证命令的完整输出保存到 `changes/evidence/verification_output.md`
2. **更新 summary.md**：阶段 ④ 状态更新为 ✅
3. 自动向下一阶段

---

## 阶段 5：提交与 PR（zcommit + pr-worktree）

**触发 skill：** zcommit → pr-worktree

**你做什么（自动连续执行，不暂停）：**

### 5.1 提交

1. 分析变更范围（`git status --short`）
2. 生成规范 commit message
3. 执行 git add + git commit
4. 推送到远端

### 5.2 创建 PR

1. `git push -u origin <branch>`
2. 查找或创建 PR
3. 从 commit message 提取标题和正文
4. 输出 PR URL
5. **更新 summary.md**：阶段 ⑤ 状态更新为 ✅，记录 PR URL 和 commit SHA

### ✋ 人工确认点 3：PR Code Review + CI

暂停，向用户展示：

```
🎉 PR 已创建：[PR URL]

请完成以下确认：
1. ✅ CI 通过 + Code Review 通过 → 合并
2. 🔄 有 Review 意见（请贴给我，我来修）
3. ❌ CI 失败（我会分析并修复）
4. ⏳ 还在等 CI，稍后确认
```

**流转规则：**
- ✅ → 记录 CI 结果到 `changes/evidence/ci_result.md`，进入阶段 6
- 🔄 → 回到阶段 3 修复，修复后重新提交推送
- ❌ → 记录 CI 失败信息到 `changes/evidence/ci_result.md`，分析原因回到阶段 3 修复
- ⏳ → 等待用户回来确认

---

## 阶段 6：合并与清理（merge-worktree）

**触发 skill：** merge-worktree

**你做什么：**

```
1. pre-merge-check.sh（强制验证，不可跳过）
   - 依赖、类型检查、Lint、测试、构建、Git 状态
   - 任何失败 → 修复后重试

2. PR merge（--no-ff，保留分支历史）

3. wait-for-ci.sh（post-merge CI）
   - 失败 → main 上修或 revert

4. 发布（如果项目有发布流程）

5. merge-worktree.sh（清理 worktree + 同步）
```

**更新 summary.md**：阶段 ⑥ 状态更新为 ✅。如果发布，记录版本号。

## 阶段 7：持续改进（自动执行）

**每个需求完成后自动做：**

1. **总结经验：** 回顾整个流程，问自己：
   - Agent 在哪些环节犯了不该犯的错？
   - 哪些错误的根因是 CLAUDE.md 缺少规则？
   - 哪个 subagent 的产出质量异常？

2. **建议 CLAUDE.md 更新：** 如果发现有可改进的规则，向用户建议：
   ```
   📝 Harness 改进建议：
   
   这次开发中发现以下问题可以通过更新 CLAUDE.md 来防止：
   
   1. [问题描述] → 建议新增规则：[规则内容]
   2. [问题描述] → 建议修改规则：[原规则] → [新规则]
   
   是否采纳？采纳后我会更新 CLAUDE.md。
   ```

3. **写复盘记录：** 将经验总结写入 `changes/retrospective.md`，包含：
   - 走了哪些阶段、跳过了哪些（如有）
   - Agent 在哪些环节犯错、根因是什么
   - 评审 subagent 是否有效拦截了问题
   - Harness（CLAUDE.md / Wiki）需要补充什么
   - 对流程本身的改进建议

4. **更新 summary.md**：所有阶段标记为 ✅，记录完成时间。

5. **如果使用 bug-fix-recorder / skill-memory-keeper 记录经验：** 按需触发。

6. **如果发现 Agent 因领域知识缺失而犯错：** 读取 `references/wiki-structure.md`，建议用户补充项目 Wiki 对应文档。

---

## 异常处理

### 回退路由

| 失败点 | 回退到 | 原因 |
|-------|--------|------|
| Spec 评审不通过 | 阶段 1 | 需求理解有误 |
| Plan 评审不通过 | 阶段 2 或阶段 1 | 计划不合理或需求不清晰 |
| Spec 合规评审不通过 | 阶段 3 当前 task | 代码没实现 spec |
| 代码质量评审不通过 | 阶段 3 当前 task | 代码质量问题 |
| 整体验证失败 | 阶段 3 | 编译/测试/lint 失败 |
| CI 失败 | 阶段 3 | 线上环境问题 |
| PR Review 意见 | 阶段 3 | 人工审查发现问题 |

### 评审循环上限

- 需求评审：最多 3 轮
- 编码/测试评审：最多 2 轮
- 超出后暂停，询问用户决策

### 阻塞升级

如果 subagent 连续 2 次报告 BLOCKED：
1. 向用户说明情况
2. 建议拆分任务、换方案、或人工介入
3. 等待用户决策

---

## 产出物清单

一次完整的 dev-flow 执行后，项目中有以下产出物：

```
.superpowers/{主题}/
├── spec.md                              # 需求设计文档
├── plan.md                              # 实现计划
└── changes/
    ├── summary.md                       # ✅ 全流程追溯摘要
    ├── reviews/
    │   ├── plan_review_v1.md            # 计划评审记录
    │   ├── code_review_v1.md            # 编码评审记录（可能有 v2+）
    │   └── final_review.md              # 最终整体评审
    ├── evidence/
    │   ├── verification_output.md       # 验证命令输出
    │   └── ci_result.md                 # CI 结果
    └── retrospective.md                # ✅ 复盘记录

wiki/                                    # 如果阶段 7 建议了补充
└── [按需新增或更新的领域文档]

CLAUDE.md                                # 如果阶段 7 建议了规则更新
```

---

## 流程总结

```
需求描述
  → [自动] 前置检查（worktree / CLAUDE.md / CI）
  → [自动] ① 需求分析 brainstorming
            产出：spec.md + changes/summary.md
  → ✋ 确认设计
  → [自动] ② 实现规划 writing-plans
            产出：plan.md
  → ✋ 确认计划
  → [自动] ③ 编码 subagent-driven-development
            内含两阶段评审（spec合规 → 代码质量）
            产出：代码 + 测试 + changes/reviews/*
  → [自动] ④ 验证 verification-before-completion
            产出：changes/evidence/verification_output.md
  → [自动] ⑤ 提交 zcommit + PR pr-worktree
            产出：PR + changes/evidence/ci_result.md
  → ✋ 确认 CI + Review
  → [自动] ⑥ 合并 merge-worktree
  → [自动] ⑦ 持续改进
            产出：changes/retrospective.md + CLAUDE.md 更新建议
```

**用户只需要介入 3 次，其余全自动。每次需求都有完整的 Audit Trail。**
