---
name: zai-vision
description: "替代 @z_ai/mcp-server 的智谱 AI 视觉分析工具。当需要分析图片、视频、UI 截图转代码、OCR 提取文字、错误截图诊断、技术图表理解、数据可视化分析、UI 对比检查时使用此 skill。通过 Python CLI 调用智谱 AI GLM-4V 视觉模型，无需启动 MCP 进程。触发词：分析图片、分析视频、UI 转代码、OCR、错误诊断、图表分析、数据可视化、UI 对比、图像分析、vision、screenshot。"
---

# ZAI Vision

通过 Python CLI 调用智谱 AI `glm-4.6v` 视觉模型，替代 `@z_ai/mcp-server`。

## 前置条件

- Python 3.10+（仅使用 stdlib，零额外依赖）
- 环境变量 `Z_AI_API_KEY`（必需）

验证：
```bash
echo $Z_AI_API_KEY
python3 scripts/zai_vision.py --help
```

## MCP 工具对照表

| 原 MCP 工具 | CLI 子命令 |
|------------|-----------|
| `analyze_image` | `analyze-image` |
| `analyze_video` | `analyze-video` |
| `extract_text_from_screenshot` | `extract-text` |
| `diagnose_error_screenshot` | `diagnose-error` |
| `understand_technical_diagram` | `understand-diagram` |
| `analyze_data_visualization` | `analyze-chart` |
| `ui_diff_check` | `ui-diff` |
| `ui_to_artifact` | `ui-to-artifact` |

CLI 脚本路径：`scripts/zai_vision.py`（相对本 skill 目录）

---

## 命令详解

### analyze-image — 通用图像分析

支持本地文件路径和远程 URL，图片限制 5MB（jpg/jpeg/png）。

```bash
python3 scripts/zai_vision.py analyze-image <图片路径或URL> "<分析需求>"
```

示例：
```bash
python3 scripts/zai_vision.py analyze-image screenshot.png "描述页面布局和主要组件"
python3 scripts/zai_vision.py analyze-image https://example.com/img.png "识别图中所有物体"
```

### analyze-video — 视频分析

视频限制 8MB，支持 MP4/MOV/M4V/AVI/WMV/WebM。

```bash
python3 scripts/zai_vision.py analyze-video <视频路径或URL> "<分析提示>"
```

示例：
```bash
python3 scripts/zai_vision.py analyze-video demo.mp4 "描述视频中的关键操作步骤"
```

### extract-text — OCR 文本提取

从截图中精确提取文字，可选指定编程语言提升准确度。

```bash
python3 scripts/zai_vision.py extract-text <截图路径或URL> "<提取指令>" [--lang python]
```

示例：
```bash
python3 scripts/zai_vision.py extract-text error.png "提取所有错误信息"
python3 scripts/zai_vision.py extract-text code.png "提取代码内容" --lang javascript
```

### diagnose-error — 错误截图诊断

分析错误截图，提供根因和修复方案。

```bash
python3 scripts/zai_vision.py diagnose-error <截图路径或URL> "<错误描述>" [--context "发生场景"]
```

示例：
```bash
python3 scripts/zai_vision.py diagnose-error stacktrace.png "npm build 失败" --context "during npm install"
```

### understand-diagram — 技术图表分析

分析架构图、流程图、UML、ER 图等。

```bash
python3 scripts/zai_vision.py understand-diagram <图表路径或URL> "<分析需求>" [--type architecture]
```

`--type` 可选值：`architecture` / `flowchart` / `uml` / `er-diagram` / `sequence`

示例：
```bash
python3 scripts/zai_vision.py understand-diagram arch.png "解释系统架构和数据流" --type architecture
```

### analyze-chart — 数据可视化分析

从图表中提取趋势、异常、指标。

```bash
python3 scripts/zai_vision.py analyze-chart <图表路径或URL> "<洞察需求>" [--focus trends]
```

`--focus` 可选值：`trends` / `anomalies` / `comparisons` / `performance metrics`

示例：
```bash
python3 scripts/zai_vision.py analyze-chart dashboard.png "提取关键业务指标" --focus trends
```

### ui-diff — UI 对比检查

对比期望设计和实际实现的截图，输出差异和修复建议。

```bash
python3 scripts/zai_vision.py ui-diff <期望图路径或URL> <实际图路径或URL> "<对比指令>"
```

示例：
```bash
python3 scripts/zai_vision.py ui-diff design.png impl.png "检查布局和颜色差异"
```

### ui-to-artifact — UI 截图转代码/规格

将 UI 截图转换为代码、提示词、设计规格或描述。

```bash
python3 scripts/zai_vision.py ui-to-artifact <截图路径或URL> <输出类型> "<生成指令>"
```

`输出类型`：`code`（前端代码）/ `prompt`（AI 提示词）/ `spec`（设计规格）/ `description`（自然语言描述）

示例：
```bash
python3 scripts/zai_vision.py ui-to-artifact mockup.png code "生成 Vue 3 组件代码"
python3 scripts/zai_vision.py ui-to-artifact mockup.png spec "生成完整设计规格文档"
```

---

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `Z_AI_API_KEY` | (必需) | API 密钥 |
| `Z_AI_BASE_URL` | `https://open.bigmodel.cn/api/paas/v4/` | API 地址 |
| `Z_AI_VISION_MODEL` | `glm-4.6v` | 视觉模型 |
| `Z_AI_TIMEOUT` | `600` | 基础超时秒数（下限 300s，大文件自动追加） |

## 与 MCP 版本的差异

- 不使用 `thinking: { type: 'enabled' }` 参数（该参数可能增加延迟和 token 消耗）
- 无重试机制（MCP 版本有 3 次指数退避重试，CLI 版本失败直接报错）
- 无日志文件输出（结果直接输出到 stdout，错误到 stderr）
