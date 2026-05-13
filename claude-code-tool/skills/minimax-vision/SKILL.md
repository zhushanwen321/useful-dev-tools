---
name: minimax-vision
description: "通过 MiniMax VLM 进行图像理解和分析。当需要理解截图内容、提取图片文字（OCR）、分析 UI 设计、诊断错误截图、解读图表/架构图、对比图片差异、或对图片进行任何形式的问答时使用此 skill。即使用户只是说'看看这个截图'、'图片里写了什么'、'这个界面怎么样'、'帮我分析下这个报错'，也应考虑触发。当图片分析需要中文深度理解、结构化输出、或 Claude 自身 read 工具无法满足的复杂视觉推理场景下，mmx vision 是更好的选择。"
---

# MiniMax Vision

调用 `mmx vision describe` 进行图像理解。底层模型是 MiniMax VLM（coding-plan-vlm），擅长中文场景的图片描述、OCR、UI 审查、图表解读等任务。

## 命令

```bash
mmx vision describe --image <本地路径或URL> --prompt "<你的问题>"
```

快捷写法（等价于 `--image`）：
```bash
mmx vision photo.jpg
```

也可用 `--file-id <id>` 替代 `--image`（用于预上传文件，跳过 base64 编码）。两者互斥。

## Agent 场景下的调用规范

**始终添加这三个 flag**，因为 agent 环境是非交互的：

```bash
mmx vision describe --image <path> --prompt "<问题>" --non-interactive --quiet --output json
```

- `--non-interactive`：缺少参数时直接报错退出，不会挂起等待用户输入
- `--quiet`：stdout 只输出结果，没有进度条和装饰文字
- `--output json`：返回 JSON 对象，用 `jq -r '.content'` 提取描述文本

如果没有解析需求，也可以省略 `--output json`，此时 stdout 直接是描述文本。

## 什么时候用 mmx vision 而不是 Claude 自带的 read

Claude 的 `read` 工具本身支持读取图片。两者各有适用场景：

**优先用 mmx vision 的场景：**
- 需要中文深度理解（read 的视觉能力偏英文）
- 需要结构化分析（指定分析维度、输出格式）
- OCR 文字提取（尤其是中文文档/截图）
- 对同一图片需要多轮、多角度提问（每次可自定义 prompt）
- 需要将结果管道给其他 mmx 命令（speech、text 等）

**用 read 就够的场景：**
- 简单看一眼图片内容（"这张图里有什么"）
- Claude 能直接回答的视觉问题
- 不需要中文优化的场景

## 提示词写法

prompt 的质量直接决定输出质量。有效模式：

```
[具体任务] + [期望的输出结构] + [关注维度]
```

几个经过验证的 prompt 模板：

**OCR 提取**：
```
"请完整提取图片中的所有文字，保持原始格式和层级。不要遗漏任何内容。"
```

**UI 审查**：
```
"审查这个UI截图，从以下维度逐一点评：1)视觉层次 2)对齐一致性 3)间距节奏 4)配色方案 5)字体使用。每个维度给出具体问题和改进建议。"
```

**错误截图诊断**：
```
"分析这个应用错误截图：1)错误类型 2)可能的根因（按可能性排序）3)排查步骤。如果有堆栈信息，一并分析。"
```

**图表分析**：
```
"分析这个数据图表：图表类型、数据趋势、关键数值、异常点。如果有图例或坐标轴标签，一并读取。"
```

**架构图解读**：
```
"分析这个架构/流程图，列出：1)所有组件/节点 2)组件间的连接关系 3)数据流向 4)关键标注文字。"
```

## 多角度分析同一图片

VLM 每次只处理一个 prompt。如果需要全面分析，分多次调用比把所有问题塞进一个 prompt 效果更好——每次聚焦一个维度，输出更精准。

```bash
IMG="./screenshot.png"

# 布局
mmx vision describe --image "$IMG" --prompt "描述页面整体布局和组件结构" --quiet

# 配色
mmx vision describe --image "$IMG" --prompt "提取所有颜色值，分析配色方案" --quiet

# 文字
mmx vision describe --image "$IMG" --prompt "提取页面中所有可见文字" --quiet
```

## 组合模式

```bash
# 先生成图片再分析
URL=$(mmx image generate --prompt "A sunset over mountains" --quiet)
mmx vision describe --image "$URL" --prompt "描述这个风景" --quiet

# 图片分析 → 语音播报
DESC=$(mmx vision describe --image photo.jpg --prompt "详细描述这张图片" --quiet)
mmx speech synthesize --text "$DESC" --out description.mp3 --quiet

# 两张图对比：分别描述后由 agent 做差异分析
mmx vision describe --image ./before.png --prompt "详尽描述所有视觉细节" --quiet > /tmp/v1.txt
mmx vision describe --image ./after.png --prompt "详尽描述所有视觉细节" --quiet > /tmp/v2.txt
```

## 配额与限制

- **coding-plan-vlm**：150 次/日，15000 次/周
- 查看剩余配额：`mmx quota --quiet`
- 支持格式：jpg、png、gif、webp 等常见图片
- 本地文件自动 base64 编码上传，超大文件可能超时
- 不指定 `--prompt` 时默认为 "Describe the image."（英文），建议始终显式指定中文 prompt

## 错误码

| 码 | 原因 | 处理 |
|---|---|---|
| 2 | 参数错误 | 检查 flag |
| 3 | 认证失败 | `mmx auth login` |
| 4 | 配额耗尽 | 等重置 |
| 10 | 内容被过滤 | 换 prompt 或图片 |
