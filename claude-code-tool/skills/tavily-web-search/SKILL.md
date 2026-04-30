---
name: tavily-web-search
description: Web search, content extraction, and website crawling via Tavily API with multi-key round-robin pool. Use whenever the user needs real-time web search, current information, fact-checking, URL content extraction, or site crawling — even if they don't say "web search" explicitly (e.g. "what's the latest", "look up", "find information about", "check this URL", "research", "联网搜索", "查一下", "搜索", "查找资料", "搜索网页", "提取网页", "爬取网站"). Also trigger on "tavily", "search the web", or any request for live/current data. This is the primary web search tool.
---

# Tavily Web Search

Real-time web search and content extraction via [Tavily API](https://tavily.com). Uses a multi-key round-robin pool with automatic exhaustion recovery (keys reset monthly).

## 如何调用

`tavily` 已安装在 `~/.local/bin/tavily`，PATH 已包含该目录。这是一个 Python wrapper，会自动从 `~/.shell/tavily.sh` 读取 `TAVILY_API_KEYS`，因此在**任意 shell 环境**（交互/非交互、bash/zsh）中都可以直接使用。

### ✅ 正确写法

```bash
# 直接用 tavily 命令，一步到位
tavily search "your query"

# 如果 tavily 不在 PATH 中（极端情况），用绝对路径
python3 ~/.local/bin/tavily search "your query"
```

### ❌ 错误写法

```bash
# ❌ 用 python 而非 python3（非交互式 bash 没有 alias，python 命令不存在）
python scripts/tavily.py search "query"

# ❌ 用相对路径（AI 执行时 cwd 不一定是 skill 目录）
python3 scripts/tavily.py search "query"

# ❌ 先 source 再运行（多余，wrapper 已自动处理）
source ~/.shell/tavily.sh && python3 ~/.agents/skills/tavily-web-search/scripts/tavily.py search "query"
```

## Commands

### `search` — Web Search

```bash
tavily search <query> [options]
```

| Option | Default | Description |
|--------|---------|-------------|
| `--depth basic\|advanced` | `basic` | `advanced` = more comprehensive results |
| `--topic general\|news` | `general` | `news` = recent news sources only |
| `--max-results N` | `10` | Number of results (1-20) |
| `--time-range day\|week\|month\|year` | — | Filter by recency |
| `--include-images` | off | Include relevant images (costs extra credits) |
| `--include-raw` | off | Include full page raw content (costs many credits) |
| `--include-domains a,b` | — | Only these domains (comma-separated) |
| `--exclude-domains a,b` | — | Exclude these domains |

**When to choose depth:**
- `basic` — quick facts, definitions, API docs, code examples
- `advanced` — in-depth research, competitive analysis, academic papers

**Examples:**
```bash
tavily search "latest AI research 2026"
tavily search "Python 3.13 release" --topic news --time-range month
tavily search "LLM safety" --depth advanced --max-results 15
tavily search "React hooks" --include-domains "react.dev" --max-results 5
```

### `extract` — URL Content Extraction

Extract clean, readable content from web pages. Removes ads, navigation, clutter.

```bash
tavily extract <url1> [url2...] [--depth basic|advanced]
```

**Examples:**
```bash
tavily extract "https://example.com/article"
tavily extract "https://url1.com" "https://url2.com" --depth advanced
```

### `crawl` — Website Crawling

Crawl a website starting from a URL, following links recursively.

```bash
tavily crawl <url> [options]
```

| Option | Default | Description |
|--------|---------|-------------|
| `--max-depth N` | `1` | How deep to follow links |
| `--max-breadth N` | `20` | Max links per level |
| `--limit N` | `50` | Total pages to crawl |
| `--instructions TEXT` | — | Custom instructions for the crawler |

**Example:**
```bash
tavily crawl "https://docs.python.org" --max-depth 2 --limit 30
```

### `map` — Site Structure

Map a website's structure (URLs only, no content).

```bash
tavily map <url> [--max-depth N] [--max-breadth N] [--limit N]
```

### `status` — Key Pool Health

```bash
tavily status
```

Shows total/available keys, per-key usage stats, and exhaustion state.

## Credit Management

- `basic` search: 1 credit ; `advanced` search: 2 credits
- `include-raw` and `include-images` consume extra credits
- Free plan: 1000 credits/month per key
- Exhausted keys auto-recover at month boundaries

**Save credits by:**
- Using `basic` depth for simple lookups
- Keeping `max-results` as low as needed (3-5 for quick answers)
- Avoiding `include-raw` unless you need full page content

## Output Format

All commands output JSON. Key fields:

**Search:**
```json
{
  "query": "...",
  "answer": "AI-generated answer (if available)",
  "results": [
    {
      "title": "...",
      "url": "...",
      "content": "...",
      "score": 0.95,
      "published_date": "2026-04-28"
    }
  ],
  "images": ["url1", "url2"],
  "response_time": 1.23
}
```

**Extract:**
```json
{
  "results": [
    {
      "url": "https://...",
      "raw_content": "Extracted markdown content..."
    }
  ]
}
```

**Crawl/Map:**
```json
{
  "results": [
    {
      "url": "https://...",
      "title": "...",
      "raw_content": "..."
    }
  ]
}
```

## MCP Server (Alternative)

The skill also includes an MCP server at `/Users/zhushanwen/Code/useful-dev-tools/mcp-tool/tavily/router.py` with the same key pool logic, providing `tavily_search`, `tavily_extract`, `tavily_crawl`, `tavily_map`, and `tavily_key_status` tools. Configure it in Claude Code's `claude.json` under `mcpServers` if you prefer native MCP tool integration.
