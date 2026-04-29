---
name: chrome-automation
description: "替代 chrome-devtools MCP 的 CDP 浏览器自动化工具。当需要自动化 Chrome 浏览器操作（导航、点击、填写、截图、执行 JS、获取页面快照、网络请求监控）时使用此 skill。通过 CDP (Chrome DevTools Protocol) 直接与 Chrome 通信，使用 curl + Node.js 脚本，无需 npx 启动 MCP 进程。触发词：chrome 自动化、浏览器操作、网页截图、网页点击、页面快照、CDP、debugging。"
---

# Chrome Automation

通过 CDP (Chrome DevTools Protocol) 替代 `chrome-devtools-mcp`。

本 skill 使用两种方式与 Chrome 通信：
1. **HTTP API**（curl）— 页面列表、新建/关闭/切换标签
2. **WebSocket API**（附带的 `scripts/cdp.js`）— 导航、点击、截图、执行 JS 等

## 前置条件

Chrome 需以远程调试模式启动：

```bash
/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome --remote-debugging-port=9222
```

获取 WebSocket URL（后续命令用 `$WS_URL`）：

```bash
WS_URL=$(curl -s http://localhost:9222/json/list | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['webSocketDebuggerUrl'])")
```

---

## HTTP API（curl 直接可用）

| MCP 工具 | 命令 |
|---------|------|
| list_pages | `curl -s http://localhost:9222/json/list \| python3 -m json.tool` |
| new_page | `curl -s "http://localhost:9222/json/new?https://example.com"` |
| close_page | `curl -s "http://localhost:9222/json/close/<pageId>"` |
| select_page | `curl -s "http://localhost:9222/json/activate/<pageId>"` |

浏览器版本：`curl -s http://localhost:9222/json/version`

---

## WebSocket API

使用 `scripts/cdp.js`（基于 Node.js v24 内置 WebSocket，零依赖）。

### navigate_page

```bash
node scripts/cdp.js "$WS_URL" navigate "https://example.com"
```

### evaluate_script

所有元素交互通过 `Runtime.evaluate` + CSS 选择器完成。

```bash
# 获取页面标题
node scripts/cdp.js "$WS_URL" Runtime.evaluate '{"expression":"document.title","returnByValue":true}'

# 获取页面 URL
node scripts/cdp.js "$WS_URL" Runtime.evaluate '{"expression":"location.href","returnByValue":true}'

# 任意 JS 代码
node scripts/cdp.js "$WS_URL" Runtime.evaluate '{"expression":"1+2","returnByValue":true}'
```

### click

使用 CSS 选择器定位并点击（替代 MCP 的 uid 机制）：

```bash
SELECTOR="button.submit"
node scripts/cdp.js "$WS_URL" Runtime.evaluate "{\"returnByValue\":true,\"expression\":\"document.querySelector('$SELECTOR')?.click(); 'clicked'\"}"
```

### fill

```bash
SELECTOR="input[name='email']"
VALUE="test@example.com"
node scripts/cdp.js "$WS_URL" Runtime.evaluate "{\"returnByValue\":true,\"expression\":\"(function(){var el=document.querySelector('$SELECTOR');el.focus();el.value='$VALUE';el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}));return 'filled'})()\"}"
```

多字段批量填写（对应 fill_form）：

```bash
node scripts/cdp.js "$WS_URL" Runtime.evaluate "{\"returnByValue\":true,\"expression\":\"(function(){var f={};f['input[name=email]']='a@b.com';f['input[name=name]']='test';for(var s in f){var el=document.querySelector(s);el.focus();el.value=f[s];el.dispatchEvent(new Event('input',{bubbles:true}))};return 'done'})()\"}"
```

### type_text

向当前聚焦的输入框输入文字：

```bash
node scripts/cdp.js "$WS_URL" Input.insertText '{"text":"hello world"}'
```

### press_key

```bash
# Enter 键
node scripts/cdp.js "$WS_URL" Input.dispatchKeyEvent '{"type":"keyDown","key":"Enter","code":"Enter","windowsVirtualKeyCode":13}'
node scripts/cdp.js "$WS_URL" Input.dispatchKeyEvent '{"type":"keyUp","key":"Enter","code":"Enter","windowsVirtualKeyCode":13}'
```

常见键码：Enter(13)、Tab(9)、Escape(27)、Backspace(8)、ArrowDown(40)、ArrowUp(38)

组合键（如 Ctrl+A）：

```bash
node scripts/cdp.js "$WS_URL" Input.dispatchKeyEvent '{"type":"keyDown","key":"a","code":"KeyA","windowsVirtualKeyCode":65,"modifiers":2}'
node scripts/cdp.js "$WS_URL" Input.dispatchKeyEvent '{"type":"keyUp","key":"a","code":"KeyA","windowsVirtualKeyCode":65,"modifiers":2}'
# modifiers: 1=Alt, 2=Ctrl, 4=Meta, 8=Shift
```

### hover

```bash
SELECTOR="a.nav-link"
node scripts/cdp.js "$WS_URL" Runtime.evaluate "{\"returnByValue\":true,\"expression\":\"(function(){var el=document.querySelector('$SELECTOR');['mouseenter','mouseover','mousemove'].forEach(function(e){el.dispatchEvent(new MouseEvent(e,{bubbles:true}))});return 'hovered'})()\"}"
```

### take_screenshot

截图并保存为 PNG：

```bash
node scripts/cdp.js "$WS_URL" Page.captureScreenshot '{"format":"png"}' | python3 -c "
import sys, json, base64
r = json.load(sys.stdin)
data = r.get('result',{}).get('result',{}).get('value','')
if data:
    with open('screenshot.png','wb') as f: f.write(base64.b64decode(data))
    print('Saved: screenshot.png')
else:
    print('Screenshot failed:', json.dumps(r, indent=2))
"
```

全页面截图：`'{"format":"png","captureBeyondViewport":true}'`

截图指定元素：

```bash
SELECTOR="div.main-content"
node scripts/cdp.js "$WS_URL" Runtime.evaluate "{\"returnByValue\":true,\"expression\":\"JSON.stringify(document.querySelector('$SELECTOR').getBoundingClientRect())\"}"
# 用返回的坐标调用 Page.captureScreenshot 的 clip 参数
```

### take_snapshot（DOM 树快照）

生成简化的 DOM 树（替代 chrome-devtools 的 a11y 快照 + uid 机制，改用 CSS 选择器）：

```bash
node scripts/cdp.js "$WS_URL" Runtime.evaluate '{"returnByValue":true,"expression":"(function(){function walk(el,d){if(d>8)return[];var t=(el.tagName||\"\").toLowerCase();if(!t||[\"script\",\"style\",\"noscript\",\"svg\",\"path\"].includes(t))return[];var r={tag:t};var role=el.getAttribute(\"role\");if(role)r.role=role;var lbl=el.getAttribute(\"aria-label\");if(lbl)r.ariaLabel=lbl;var ph=el.getAttribute(\"placeholder\");if(ph)r.placeholder=ph;var tp=el.getAttribute(\"type\");if(tp)r.type=tp;var href=el.getAttribute(\"href\");if(href)r.href=href;if(!el.children||el.children.length===0){var txt=(el.textContent||\"\").trim().slice(0,80);if(txt)r.text=txt}if(el.id)r.id=el.id;if(el.className&&typeof el.className===\"string\")r.cls=el.className.split(\" \").filter(Boolean).slice(0,3).join(\".\");var ch=[];for(var i=0;i<(el.children||[]).length;i++)ch.push(...walk(el.children[i],d+1));if(ch.length)r.children=ch;return[r]}return JSON.stringify(walk(document.body,0))})()"}'
```

### wait_for

等待文本出现在页面中：

```bash
for i in $(seq 1 30); do
  found=$(node scripts/cdp.js "$WS_URL" Runtime.evaluate "{\"returnByValue\":true,\"expression\":\"document.body.innerText.includes('TARGET_TEXT')\"}" 2>/dev/null)
  if echo "$found" | grep -q '"value":true'; then echo "Found"; break; fi
  sleep 1
done
```

### handle_dialog

```bash
# Accept dialog
node scripts/cdp.js "$WS_URL" Page.handleJavaScriptDialog '{"action":"accept"}'
# Dismiss with prompt text
node scripts/cdp.js "$WS_URL" Page.handleJavaScriptDialog '{"action":"accept","promptText":"hello"}'
```

### upload_file

```bash
SELECTOR="input[type='file']"
FILEPATH="/path/to/file.txt"
node scripts/cdp.js "$WS_URL" Runtime.evaluate "{\"returnByValue\":true,\"expression\":\"(function(){var el=document.querySelector('$SELECTOR');return el?'found':'not found'})()\"}"
# 需通过 DOM.setFileInputFiles — 先获取 node backendNodeId
```

### resize_page

```bash
node scripts/cdp.js "$WS_URL" Emulation.setDeviceMetricsOverride '{"width":1280,"height":720,"deviceScaleFactor":1,"mobile":false}'
```

### emulate

```bash
# 移动设备模拟
node scripts/cdp.js "$WS_URL" Emulation.setDeviceMetricsOverride '{"width":375,"height":812,"deviceScaleFactor":3,"mobile":true}'
node scripts/cdp.js "$WS_URL" Network.setUserAgentOverride '{"userAgent":"Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) ..."}'
```

---

## 完整工具对照

| chrome-devtools MCP | 替代方式 |
|-------------------|---------|
| list_pages | `curl localhost:9222/json/list` |
| new_page | `curl localhost:9222/json/new?<url>` |
| close_page | `curl localhost:9222/json/close/<id>` |
| select_page | `curl localhost:9222/json/activate/<id>` |
| navigate_page | `cdp.js navigate <url>` |
| take_screenshot | `cdp.js Page.captureScreenshot` |
| take_snapshot | `cdp.js Runtime.evaluate` + DOM walk |
| click(uid) | `cdp.js Runtime.evaluate` + `querySelector.click()` |
| fill(uid, value) | `cdp.js Runtime.evaluate` + `querySelector.value=` |
| fill_form(elements) | `cdp.js Runtime.evaluate` + 批量 JS |
| evaluate_script(fn) | `cdp.js Runtime.evaluate` |
| type_text(text) | `cdp.js Input.insertText` |
| press_key(key) | `cdp.js Input.dispatchKeyEvent` |
| hover(uid) | `cdp.js Runtime.evaluate` + mouse events |
| wait_for(text) | 轮询 `cdp.js Runtime.evaluate` |
| handle_dialog | `cdp.js Page.handleJavaScriptDialog` |
| upload_file | `cdp.js DOM.setFileInputFiles` |
| resize_page | `cdp.js Emulation.setDeviceMetricsOverride` |
| emulate | `cdp.js Emulation.*` + `Network.setUserAgentOverride` |
| drag | `cdp.js Input.dispatchMouseEvent` 序列 |
| list_network_requests | `cdp.js Network.enable` + 事件监听脚本 |
| list_console_messages | `cdp.js Runtime.enable` + 事件监听脚本 |
| lighthouse_audit | `lighthouse <url> --output json` CLI |
| performance_* | `cdp.js Performance.*` + `cdp.js Profiler.*` |
| take_memory_snapshot | `cdp.js HeapProfiler.takeHeapSnapshot` |

## 注意事项

- chrome-devtools MCP 使用 uid（a11y tree 的唯一标识），本 skill 改用 CSS 选择器（`querySelector`），更通用
- CDP 命令参考：https://chromedevtools.github.io/devtools-protocol/
- `scripts/cdp.js` 路径：相对本 skill 目录下的 `scripts/cdp.js`
