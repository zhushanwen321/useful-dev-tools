---
name: web-fetch
description: "替代 fetch MCP 的纯 Bash/Python Web 抓取工具。当需要获取网页内容（HTML/Markdown/纯文本/JSON）、提取网页正文、抓取 YouTube 字幕时使用此 skill。用 curl + python3 stdlib 实现所有 mcp-fetch-server 功能，无需启动额外进程。触发词：fetch url、获取网页、抓取页面、下载内容、网页转 markdown、YouTube 字幕。"
---

# Web Fetch

用 `curl` + `python3`（仅 stdlib）替代 `mcp-fetch-server`。

## 参数映射

| MCP 参数 | curl 等价 |
|---------|----------|
| `url` | curl 位置参数 |
| `headers` | `-H "Key: Value"`，可多个 `-H` |
| `max_length` | `head -c <N>` |
| `start_index` | `tail -c +<N+1> \| head -c <max_length>` |
| `proxy` | `--proxy "http://host:port"` |

公共 flag：`-s`（静默）`-L`（跟随重定向）。

---

## fetch_html → curl

```bash
curl -sL "<url>" | head -c 50000
```

带 header 和代理：

```bash
curl -sL -H "Authorization: Bearer TOKEN" --proxy "http://proxy:8080" "<url>" | head -c 50000
```

## fetch_markdown → curl + python3

```bash
curl -sL "<url>" | python3 << 'PYEOF'
import sys, re
h = sys.stdin.read()
h = re.sub(r'<(script|style)[^>]*>.*?</\1>', '', h, flags=re.S)
for i in range(1, 7):
    h = re.sub(f'<h{i}[^>]*>(.*?)</h{i}>', '#' * i + r' \1', h, flags=re.S)
h = re.sub(r'<a[^>]*href=["\x27]([^"\x27]*)["\x27][^>]*>(.*?)</a>', r'[\2](\1)', h, flags=re.S)
h = re.sub(r'<img[^>]*src=["\x27]([^"\x27]*)["\x27][^>]*alt=["\x27]([^"\x27]*)["\x27][^>]*/?\s*>', r'![\2](\1)', h, flags=re.S)
h = re.sub(r'<strong>(.*?)</strong>', r'**\1**', h, flags=re.S)
h = re.sub(r'<em>(.*?)</em>', r'*\1*', h, flags=re.S)
h = re.sub(r'<code>(.*?)</code>', r'`\1`', h, flags=re.S)
h = re.sub(r'<p[^>]*>(.*?)</p>', r'\n\1\n', h, flags=re.S)
h = re.sub(r'<li[^>]*>(.*?)</li>', r'- \1', h, flags=re.S)
h = re.sub(r'<br\s*/?>', '\n', h, flags=re.S)
h = re.sub(r'<[^>]+>', '', h)
print(re.sub(r'\n{3,}', '\n\n', h).strip())
PYEOF
```

若已安装 pandoc（效果更好）：`curl -sL "<url>" | pandoc -f html -t markdown --wrap=none`

## fetch_readable → curl + python3

提取正文，去除导航/广告/页脚：

```bash
curl -sL "<url>" | python3 << 'PYEOF'
import sys, re
html = sys.stdin.read()
for tag in ['article', 'main']:
    m = re.search(rf'<{tag}[^>]*>(.*?)</{tag}>', html, re.S)
    if m:
        html = m.group(1)
        break
else:
    for t in ['nav','header','footer','aside','script','style','form','noscript']:
        html = re.sub(rf'<{t}[^>]*>.*?</{t}>', '', html, flags=re.S)
html = re.sub(r'<br\s*/?>|</p>', '\n', html, flags=re.S)
html = re.sub(r'<[^>]+>', '', html)
print(re.sub(r'\n\s*\n+', '\n\n', html).strip())
PYEOF
```

安装 readability-lxml 可提升质量：`pip3 install readability-lxml html2text`

## fetch_txt → curl + python3

```bash
curl -sL "<url>" | python3 << 'PYEOF'
import sys, re
h = sys.stdin.read()
for t in ['script','style','noscript']:
    h = re.sub(rf'<{t}[^>]*>.*?</{t}>', '', h, flags=re.S)
h = re.sub(r'<br\s*/?>|</p>', '\n', h, flags=re.S)
h = re.sub(r'<[^>]+>', '', h)
print(re.sub(r'\n\s*\n+', '\n\n', h).strip())
PYEOF
```

## fetch_json → curl

```bash
curl -sL "<url>" | python3 -m json.tool | head -c 50000
```

## fetch_youtube_transcript → yt-dlp

需先安装：`brew install yt-dlp`

```bash
# 自动生成字幕
yt-dlp --write-auto-sub --sub-lang en --skip-download -o "/tmp/yt_%(id)s" "<youtube_url>"
cat /tmp/yt_*.vtt | head -c 50000

# 手动字幕
yt-dlp --write-sub --sub-lang zh --skip-download -o "/tmp/yt_%(id)s" "<youtube_url>"

# 列出可用字幕
yt-dlp --list-subs "<youtube_url>"
```
