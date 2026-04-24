---
name: code-taste-review
description: >
  代码品味提炼工作流。系统性地审查项目代码，按业务重要度、复杂度、可扩展性、性能要求
  四个维度分优先级分组，引导用户 review 后提炼出个人代码品味和编程偏好。
  当用户提到"代码品味"、"code taste"、"提炼品味"、"review代码品味"、
  "梳理代码理念"、"总结编码偏好"、"记录代码审美"时触发。
  即使用户只是说"帮我 review 一下代码质量"或"看看这代码写得怎么样"，
  如果语境偏向品味和偏好而非找 bug，也应使用此技能。
---

# 代码品味提炼

通过多轮 review 会话，逐步提炼用户在编码风格、架构选择、抽象层次等方面的个人品味。
品味不是一次性产出的——每次 review 沉淀一小部分，最终积累成完整的编码哲学。

## 目录结构

```
~/.codetaste/
├── essence.md                  # 跨语言根本原则（四条元原则）
├── <lang>/
│   ├── taste.md               # 按语言沉淀的品味索引（原则/偏好/反模式）
│   ├── principles.md          # 原则详细描述
│   ├── preferences.md         # 偏好详细描述
│   ├── anti-patterns.md       # 反模式详细描述
│   └── lint/                  # 自动化检查脚本
│       ├── check.sh           # 总入口
│       ├── init-lint.sh       # 项目集成脚本
│       └── rules/             # 具体规则脚本
├── review/
│   └── <yyyy-MM-dd>/          # 每次会话一个目录
│       ├── session.json       # 会话元数据
│       ├── file_inventory.md  # 项目文件清单 + review 状态
│       ├── groups.md          # TOP 3 分组索引
│       ├── my_review.md       # 用户 review 记录（用户填写）
│       └── taste_extracted.md # 本次提炼结果
└── bin/                        # 工具脚本
    ├── update-inventory.sh    # 从 session.json 更新 file_inventory.md
    └── migrate.sh             # 旧路径迁移工具
```

## 模板文件

以下模板位于 skill 目录下的 `templates/` 中，创建新会话时参照：

- [session.json](templates/session.json)
- [groups.md](templates/groups.md)
- [taste_extracted.md](templates/taste_extracted.md)
- [file_inventory.md](templates/file_inventory.md)

## 入口判断

用户触发此技能时，先判断当前处于哪个阶段：

1. **阶段一**（步骤 1-4）：用户说"开始 review"、"提炼代码品味"、"开始品味 review"
2. **阶段二**（步骤 5）：展示分组，等待用户写 `my_review.md`
3. **阶段三**（步骤 6-9）：用户说"提炼品味"、"我写完了 review"、"帮我整理品味"
4. **进度查询**：用户说"review 进度"、"还剩多少文件"

---

## 阶段一：启动 Review

### 步骤 1：扫描项目文件

扫描当前项目目录的所有源代码文件。

**包含**：`src/`、`lib/`、`app/`、`internal/`、`cmd/`、`pkg/` 等业务代码目录下的源文件。
**排除**：`node_modules/`、`dist/`、`build/`、`vendor/`、`.git/`、`__pycache__/`、测试 fixture、生成的代码（如 `*.generated.*`、`*.pb.go`）、锁文件、配置文件（如 `webpack.config.*`）。

对每个文件记录：相对路径、语言、行数（大致）。

### 步骤 2：检查 Review 历史

扫描 `~/.codetaste/review/` 下所有已有目录，读取每个 `session.json` 和 `file_inventory.md`，汇总哪些文件已被 review 过以及最后 review 日期。

**日期冲突处理**：如果今天日期的目录已存在，追加序号 `-2`、`-3`。

### 步骤 3：创建 Review 会话

创建 review 目录，参照 [session.json 模板](templates/session.json) 写入 `session.json`。

参照 [file_inventory.md 模板](templates/file_inventory.md) 生成文件清单。

### 步骤 4：分组排序

对 **未 review 的文件** 按 4 个维度评分（1-5 分）：

| 维度 | 权重 | 评估依据 |
|------|------|---------|
| 业务重要程度 | 0.3 | 模块在核心请求链路中的位置、被依赖的数量 |
| 代码复杂程度 | 0.2 | 逻辑分支密度、函数长度、嵌套深度 |
| 可扩展性要求 | 0.3 | 未来变更的可能性、配置化程度、接口抽象度 |
| 性能要求 | 0.2 | I/O 密集度、数据处理量、延迟敏感度 |

综合得分 = Σ(维度分数 × 权重)，按得分降序排列。

选出 **TOP 3 分组**，每组 4-5 个文件。分组时考虑文件的逻辑关联性（同模块、同层的文件归为一组），而非单纯按分数切割。

参照 [groups.md 模板](templates/groups.md) 写入。

**完成步骤 4 后，进入阶段二。**

---

## 阶段二：等待用户 Review

### 步骤 5：展示分组并等待

将 `groups.md` 的内容呈现给用户。告知用户：

- review 目录的位置
- 建议按分组顺序 review
- 在 review 目录下创建或编辑 `my_review.md`，写入 review 意见

**Review 文件路径约定**：用户可以逐组写 review，也可以全部写在一个文件中。支持的写法：
- 全部写在一个 `my_review.md` 中
- 按分组写 `group1.md`、`group2.md`、`group3.md`，再加上 `my_review.md`（额外 review 的文件）
- 直接在对话中口述 review 意见

`my_review.md` 是自由格式的文档。用户可以写任何想说的，例如：
- 对代码结构的赞赏或批评
- 命名风格的偏好
- 错误处理模式的看法
- 对抽象层次的判断
- 性能与可读性的权衡观点
- 具体的代码片段引用和点评

**等待用户明确表示"写完了"、"提炼品味"后再进入阶段三。**

---

## 阶段三：提炼品味

### 步骤 6：提取品味

1. 读取所有 review 文件（`my_review.md`、`group*.md` 等）
2. 读取 review 中提及的源代码文件（需要对照原文理解用户的评价）
3. 提取品味要素，按以下维度归类：

| 品味维度 | 关注点 |
|---------|--------|
| 结构与组织 | 文件组织、模块划分、依赖方向、层次分离 |
| 命名品味 | 变量、函数、类的命名风格，语义表达力 |
| 错误处理哲学 | 异常策略、错误传播、降级方案、日志记录 |
| 抽象层次 | 何时抽象、抽象粒度、接口设计 |
| 性能意识 | 在何处关注性能、如何权衡性能与可读性 |
| 可读性标准 | 注释风格、代码密度、表达力、一致性 |
| 测试态度 | 测试策略、覆盖偏好、mock 与真实的选择 |

4. 按**三级分类**组织：
   - **原则**（不可违背）— 用户用强烈语气表达的要求
   - **偏好**（推荐风格）— 用户倾向但认可有例外的情况
   - **反模式**（明确否定）— 用户明确不认可的做法

5. 标注理由和来源

#### 步骤 6b：去重检查

读取 `~/.codetaste/<lang>/taste.md`（以及 `principles.md`、`preferences.md`、`anti-patterns.md`），将提取结果与已有条目交叉比对：

- 完全重复的条目：不重复写入，可选更新描述
- 部分重叠的条目：合并描述，保留更丰富的表述
- 全新条目：标记为新增

在 `taste_extracted.md` 底部增加去重检查表，记录每条提取结果与已有品味的对比。

参照 [taste_extracted.md 模板](templates/taste_extracted.md)。

### 步骤 7：essence.md 交叉验证

读取 `~/.codetaste/essence.md`，验证本次提取的所有品味条目能否归入已有的元原则（通常为四条）。

**四条元原则**：
1. 显式优于隐式
2. 一条路径一个关注点
3. 信任止于边界
4. 反馈不破坏系统

对每条品味条目：
- 如果能归入某条元原则：标注对应关系
- 如果无法归入：思考是否需要新增元原则（需要非常强的理由）

将验证结果追加到 `taste_extracted.md`。

**同步更新 `essence.md`**：
- 为新增条目在对应元原则下补充语言特定的表述
- 补充量化标准（如果有新的可量化阈值被提炼出来）
- 更新自动化能力分析表

### 步骤 8：合并沉淀

将去重后的新品味合并到 `~/.codetaste/<lang>/` 下的对应文件：

- `taste.md` — 更新索引（添加新条目，更新 Lint 列链接）
- `principles.md` — 新增原则
- `preferences.md` — 新增偏好
- `anti-patterns.md` — 新增反模式

品味文档格式：

```markdown
# <Language> 代码品味

> 最后更新：yyyy-MM-dd | 累计 review 次数：N

## 原则

### [P1: 原则名称]
**来源**: review/<date> | **强度**: 不可违背
<原则描述>
**正例**: <代码片段>
**反例**: <代码片段>（如果有）

## 偏好

### [B1: 偏好名称]
**来源**: review/<date> | **强度**: 推荐
<偏好描述>
**注意**: <例外情况>（如果有）

## 反模式

### [A1: 反模式名称]
**来源**: review/<date> | **强度**: 避免
<反模式描述>
**反面示例**: <代码片段>
```

### 步骤 9：Lint 生成（自动化项）

对本次提炼的品味条目，评估自动化可行性。可自动化项的标准：
- 有明确的量化阈值
- 可通过静态分析检测
- 判定规则无歧义

对可自动化项：
1. 在 `~/.codetaste/<lang>/lint/rules/` 下创建对应检测脚本
2. 更新 `~/.codetaste/<lang>/lint/check.sh` 总入口，添加新规则
3. 在 `taste.md` 的对应条目中添加 Lint 列，链接到脚本

脚本要求：
- `set -euo pipefail` + `export LC_ALL=C`（确保 macOS 正则兼容）
- 使用 `变量=$((变量 + 1))` 而非 `((变量++))`（避免 set -e 误杀）
- 支持 `--warn` / `--error` 阈值参数
- 输出格式：`LEVEL: file:line message`

### 更新 session.json

提炼完成后更新状态：
```json
{
  "status": "completed",
  "files_reviewed": ["src/proxy/openai.ts", "..."]
}
```

运行 `bash ~/.codetaste/bin/update-inventory.sh <review目录>` 自动更新 `file_inventory.md`。

---

## 进度查询

当用户问进度时：

1. 读取所有 `~/.codetaste/review/*/session.json`
2. 读取最新项目的 `file_inventory.md`
3. 汇报：
   - 总文件数 / 已 review / 未 review
   - 已完成的 review 会话列表
   - 已沉淀的品味条目数（按语言统计）
   - 已有的 lint 规则数
   - 建议下次从哪里继续
