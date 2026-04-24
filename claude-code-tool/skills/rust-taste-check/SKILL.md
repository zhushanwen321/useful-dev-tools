---
name: rust-taste-check
description: >
  参照代码品味指导文件，审查并重构 Rust 代码。先运行自动化 lint 脚本检测函数长度、
  参数数量、魔法数字、死代码、显式 drop、敏感日志，再按原则(P1-P5)/偏好(B1-B9)/
  反模式(A1-A6)逐项人工审查，输出结构化报告并提供重构方案。
  当用户说"品味检查"、"taste check"、"rust-taste-check"、"审查rust代码质量"、
  "按品味标准review"、"重构rust代码"时触发。
  当用户提供 .rs 文件路径或 Rust 项目目录路径并要求质量审查时，也应考虑触发。
  即使用户只说"帮我看看这个文件的代码质量"或"review 一下 src-tauri/src/services"，
  如果语境是 Rust 项目，也应使用此技能。
---

# Rust 代码品味检查

对指定目录或文件，参照品味指导文档进行系统化审查和重构。

## 参考文档（必须先读取）

每次执行前读取以下文件，它们定义了所有检查标准：

1. **本质与规范**: `~/Code/coding_config/.codetaste/essence.md`
   — 四条根本原则、决策框架
2. **Rust 品味主索引**: `~/Code/coding_config/.codetaste/rust/taste.md`
   — 原则/偏好/反模式三级分类索引
3. **原则细则**: `~/Code/coding_config/.codetaste/rust/principles.md`
   — P1-P5 不可违背规则的详细说明与正反例
4. **偏好细则**: `~/Code/coding_config/.codetaste/rust/preferences.md`
   — B1-B9 推荐实践
5. **反模式细则**: `~/Code/coding_config/.codetaste/rust/anti-patterns.md`
   — A1-A6 必须避免的模式

路径不存在时提示用户确认。第 1-2 项必读，第 3-5 项按需查阅。

## 执行流程

### 1. 确定审查范围

从用户输入提取目标。支持：
- 目录路径 → 递归扫描 `.rs` 文件
- 文件路径列表 → 逐个审查

排除：`target/` `vendor/` `*.generated.rs` 自动生成文件。

### 2. 运行自动化 lint

先执行自动化检查，快速定位可机械检测的问题：

```bash
bash ~/Code/coding_config/.codetaste/rust/lint/check.sh [目标路径]
```

如果路径不存在该脚本，跳过此步并告知用户。将 lint 结果纳入最终报告。

### 3. 逐文件审查

对每个文件读取源码，按以下优先级检查。每项对应品味文档中的规则。

**P0 原则违反（必须修复）**

| 编号 | 检查项 | 文档来源 | 识别方式 |
|------|--------|---------|---------|
| P1 | 跨文件重复逻辑（80%相似且>10行） | principles.md P1 | 人工对比 |
| P2 | 函数超 80 行警告、超 150 行必须拆分 | principles.md P2 | lint + 人工 |
| P2 | 参数超过 5 个未打包为结构体 | principles.md P2 | lint + 人工 |
| P3 | 函数体内硬编码魔法数字（阈值/超时/预算） | principles.md P3 | lint + 人工 |
| P4 | `#[allow(dead_code)]` 长期保留 | principles.md P4 | lint + 人工 |
| P5 | 配置读写路径不一致 | principles.md P5 | 人工 |

**P1 偏好（推荐修复）**

| 编号 | 检查项 | 文档来源 |
|------|--------|---------|
| B1 | 命名不反映实际行为（尤其是有副作用却用纯查询命名） | preferences.md B1 |
| B2 | 结构体 >10 字段未按逻辑分组 | preferences.md B2 |
| B3 | 手动实现 derive 可替代的 trait | preferences.md B3 |
| B4 | 手动资源清理可用 RAII 替代 | preferences.md B4 |
| B5 | 关键路径错误被静默跳过 | preferences.md B5 |
| B6 | 重复的锁操作模式未封装 | preferences.md B6 |
| B7 | 冗长类型(>60字符)出现>3次未定义 type alias | preferences.md B7 |
| B8 | 显式 `drop()` 可用作用域块替代 | preferences.md B8 |
| B9 | 函数参数/返回值使用 `serde_json::Value` 而非强类型 | preferences.md B9 |

**P2 反模式（必须避免）**

| 编号 | 检查项 | 文档来源 |
|------|--------|---------|
| A1 | 关键路径 `ok()?` 跳过错误不记录 | anti-patterns.md A1 |
| A2 | 函数/参数过长（与 P2 重叠，关注拆分方案） | anti-patterns.md A2 |
| A3 | 硬编码魔法数字（与 P3 重叠，关注提取方案） | anti-patterns.md A3 |
| A4 | `#[allow(dead_code)]` 长期保留 | anti-patterns.md A4 |
| A5 | 配置读写使用不同解析方式 | anti-patterns.md A5 |
| A6 | 日志打印完整请求体/敏感信息 | anti-patterns.md A6 |

### 4. 输出审查报告

对每个有发现的文件：

```
## <文件路径>（<行数> 行）

| 优先级 | 类别 | 位置 | 描述 | 建议 |
|--------|------|------|------|------|
| P0 | P1-重复 | L42-L89 | 与 dispatch_agent.rs 的子 Agent 启动逻辑重复 | 提取公共 trait + 泛型方法 |
| P0 | P2-函数 | L15 | run_turn() 200+行 13 参数 | 拆分为 TurnContext + TurnState，每步一个方法 |

统计: P0: X | P1: X | P2: X
```

无发现的文件跳过。全部完成后输出汇总：
- 各优先级问题总数
- 跨文件重复的具体位置
- 建议重构顺序（P0 优先，同一文件内自上而下）

### 5. 重构

报告输出后询问用户是否执行重构。确认后：

- 按 P0 → P2 优先级修复
- 每个修复保持最小变更，不做超范围改进
- 修复后运行 `cargo check` 和 `cargo test` 验证
- 变更超过 3 个文件时分批执行、逐批验证

### 6. 重构后验证

- 运行 `cargo clippy -- -W clippy::all` 确认无警告
- 运行 `cargo test` 确认无回归
- 再次运行 lint 脚本确认机械问题已清除
- 对修改过的文件重新执行品味检查
- 输出变更摘要
