---
description: 根据功能规格创建概要设计（HLD），然后调用 plan 并传入 sketch 引用
---

## 用户输入

```text
$ARGUMENTS
```

如果用户输入不为空，你**必须**在继续之前考虑用户输入。

## 执行大纲

1. **初始化设置**：从仓库根目录运行 `.specify/scripts/bash/check-prerequisites.sh --json`，解析 JSON 获取 FEATURE_DIR 和 AVAILABLE_DOCS。所有路径必须是绝对路径。对于包含单引号的参数如 "I'm Groot"，使用转义语法：例如 'I'\''m Groot'（或尽可能使用双引号："I'm Groot"）。

2. **验证前置条件**：检查 FEATURE_DIR 中是否存在 spec.md。如果不存在，输出错误并提示用户先运行 `/speckit.specify`。

3. **生成概要设计（HLD）**：

   **加载上下文**：
   - 读取 FEATURE_SPEC（FEATURE_DIR/spec.md）了解功能需求
   - 如果存在 constitution.md（.specify/memory/constitution.md），读取以了解项目原则
   - 加载 sketch 模板（~/.claude/commands/sketch/sketch-template.md）

   **生成 sketch.md**，包含以下结构（创建在 FEATURE_DIR/sketch.md）：

   ```markdown
   # 概要设计 (High-Level Design)

   ## 1. 系统架构
   - 架构类型（单体/微服务/Serverless/等）
   - 架构图（使用 ASCII diagram）
   - 核心组件及其关系

   ## 2. 模块设计
   - 前端模块划分（如果有）
   - 后端模块划分
   - 模块间的依赖关系
   - 模块职责边界

   ## 3. 技术栈
   - 前端技术选型（框架、状态管理、UI 库等）
   - 后端技术选型（语言、框架、中间件等）
   - 数据库选型（关系型/文档型/等）
   - 其他关键技术

   ## 4. 页面/屏幕结构（如果是 UI 功能）
   - 页面列表
   - 页面层级关系
   - 页面导航流程

   ## 5. 数据设计（概要）
   - 核心实体（不包含详细字段）
   - 实体间关系（不包含详细 schema）

   ## 6. 技术挑战
   - 预期的技术难点
   - 需要调研的技术点
   - 性能/安全考虑

   ## 7. 设计系统集成（如适用）
   - Design System 使用
   - 组件库选择
   - 样式管理方案

   ## 8. 与现有系统的集成
   - 与现有模块的集成点
   - API 集成策略
   - 数据迁移考虑（如适用）
   ```

   **HLD 的关键原则**：
   - **仅限高层级**：不包含实现细节、具体 API schema、详细数据库字段
   - **关注架构**：关注系统组织、模块划分、技术选型
   - **ASCII 图表**：使用简单清晰的图表说明架构和数据流
   - **技术决策**：明确技术选型及其理由

4. **调用 plan**：执行 `/speckit.plan 阅读概要设计文档（$FEATURE_DIR/sketch.md），为每个模块/页面生成详细设计文档，概要设计文档和详细设计文档双向链接` 以生成包含 HLD 引用的详细实现计划

5. **报告结果**：输出完成消息及路径：
   - ✅ HLD 已创建：$FEATURE_DIR/sketch.md
   - ✅ 详细计划：$FEATURE_DIR/plan.md（包含 HLD 引用）

## 关键规则

- **HLD 范围**：专注于架构、模块、技术选型。不包含实现细节。
- **ASCII 图表**：使用基于文本的图表来表示架构、数据流、页面结构
- **技术清晰度**：明确说明技术选型及其理由
- **模块边界**：清晰定义模块职责和接口
- **向后兼容**：如果 sketch.md 已存在，询问用户是否要覆盖

## 上下文

功能上下文：$ARGUMENTS
