---
name: ts-taste-check
description: >
  参照代码品味指导文件，审查并重构 TypeScript / Vue 代码。先运行自动化 ESLint 品味
  规则检测 any、魔法数字、静默 catch、不安全的 Object.entries 等，再按
  原则/偏好/反模式逐项人工审查，输出结构化报告并提供重构方案。
  当用户说"品味检查"、"taste check"、"ts-taste-check"、"审查ts代码质量"、
  "按品味标准review"、"重构ts代码"时触发。
  当用户提供 TS/Vue 文件路径或目录路径并要求质量审查时，也应考虑触发。
  即使用户只说"帮我看看这个文件的代码质量"或"review 一下 src/proxy"，
  如果语境是 TS 项目，也应使用此技能。
---

# TypeScript 代码品味检查

对指定目录或文件，参照品味指导文档进行系统化审查和重构。

## 参考文档（必须先读取）

每次执行前读取以下文件，它们定义了所有检查标准：

1. **本质与规范**: `~/Code/coding_config/.codetaste/essence.md`
   — 四条根本原则、决策框架
2. **TypeScript 品味主索引**: `~/Code/coding_config/.codetaste/ts/taste.md`
   — 原则/偏好/反模式三级分类，含 Lint 规则映射

路径不存在时提示用户确认。

## 执行流程

### 1. 确定审查范围

从用户输入提取目标。支持：
- 目录路径 → 递归扫描 `.ts` `.tsx` `.vue` 文件
- 文件路径列表 → 逐个审查

排除：`node_modules/` `dist/` `.nuxt/` `*.d.ts` `*.generated.*` 测试 fixture。

### 2. 运行自动化 lint

如果项目已配置 taste-lint（存在 `taste-lint/` 目录或 `eslint.config.mjs` 中导入了 taste 规则）：

```bash
npx eslint --max-warnings=0 [目标路径]
```

如果项目未配置，可提示用户运行一键集成：
```bash
bash ~/Code/coding_config/.codetaste/ts/init-lint.sh [项目目录]
```

跳过此步不影响后续审查，但建议用户后续集成。将 lint 结果纳入最终报告。

### 3. 逐文件审查

对每个文件读取源码，按以下优先级检查。每项对应品味文档中的规则。

**P0 原则违反（必须修复）**

| 检查项 | 文档来源 | 可自动化 |
|--------|---------|---------|
| 文件超 300 行需审视拆分，超 500 行几乎一定拆分 | taste.md "结构先于一切" | ESLint max-lines |
| 文件混合多种职责：路由+业务+数据访问 | taste.md "单文件多职责" | 人工 |
| 跨文件重复逻辑（80% 相似且 >10 行） | taste.md "消除一切重复" | 人工 |
| 未约束的 `any` | taste.md "类型即契约" | ESLint no-explicit-any |
| `Record<string, unknown>` 无校验直接使用 | essence.md "信任止于边界" | 人工 |
| 错误响应格式不统一 | taste.md "统一优于灵活" | 人工 |

**P1 偏好（推荐修复）**

| 检查项 | 文档来源 | 可自动化 |
|--------|---------|---------|
| 前后端类型混用（Provider vs ProviderForm vs ProviderPayload） | taste.md "前后端类型分离" | 人工 |
| 边界数据缺少运行时校验（zod/TypeBox） | essence.md "信任止于边界" | 人工 |
| `catch` 块静默吞错误（仅 console.error 无 UI 反馈） | taste.md "异步操作无 UI 反馈" | taste/no-silent-catch |
| 异步操作缺少 loading/error 状态 | taste.md "异步操作标配 loading/error" | 人工 |
| 模板中直接调用函数未用 computed 缓存 | taste.md "计算属性缓存" | 人工 |
| 并行数据加载用 Promise.all 而非 allSettled | taste.md "Promise.allSettled" | taste/prefer-allsettled |
| `Object.entries` 拼接 SQL/配置无白名单 | taste.md "动态字段名无白名单" | taste/no-unsafe-object-entries |
| API 层暴露内部实现（如导出 axios 实例） | taste.md "暴露内部实现" | 人工 |
| 魔法数字/字符串缺命名常量 | taste.md "语义化命名" | ESLint no-magic-numbers |

**P2 安全防御（必须修复）**

| 检查项 | 文档来源 | 可自动化 |
|--------|---------|---------|
| 认证操作未使用 timing-safe 比较 | taste.md "安全无例外" | 人工 |
| `v-html` 可替换为组件方式 | taste.md "安全无例外" | vue/no-v-html |
| 敏感数据泄露（日志/明文 API Key/密码） | taste.md "安全无例外" | 人工 |
| `eval()` / `implied-eval` 使用 | taste.md "安全无例外" | ESLint no-eval |

**P3 细节**

| 检查项 | 文档来源 |
|--------|---------|
| 隐式依赖其他模块注册的能力 | taste.md "隐式依赖" |
| Composable 未封装数据逻辑（组件自管全部状态） | taste.md "Composables 模式" |
| Service 层未分离（路由含业务逻辑） | taste.md "Service 层分离" |
| 端点路径散落各处未集中管理 | taste.md "API 层封装" |

### 4. 输出审查报告

对每个有发现的文件：

```
## <文件路径>（<行数> 行）

| 优先级 | 类别 | 位置 | 描述 | 建议 |
|--------|------|------|------|------|
| P0 | 结构 | 全文件 | 450行混合路由+业务逻辑 | 拆为 routes.ts + service.ts |
| P0 | 类型 | L42 | db: any | 改为 db: Database |

统计: P0: X | P1: X | P2: X | P3: X
```

无发现的文件跳过。全部完成后输出汇总：
- 各优先级问题总数
- 跨文件重复的具体位置
- 建议重构顺序（P0 优先，同一文件内自上而下）

### 5. 重构

报告输出后询问用户是否执行重构。确认后：

- 按 P0 → P3 优先级修复
- 每个修复保持最小变更，不做超范围改进
- 修复后运行 `npm run lint`（或 `npx eslint`）和 `npm test`（或项目对应测试命令）验证
- 变更超过 3 个文件时分批执行、逐批验证

### 6. 重构后验证

- 运行 ESLint 确认品味规则全部通过
- 运行测试套件确认无回归
- 对修改过的文件重新执行品味检查
- 输出变更摘要
