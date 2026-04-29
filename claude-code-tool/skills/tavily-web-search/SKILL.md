---
name: tavily-web-search
description: Web search, content extraction, and website crawling via Tavily API with multi-key round-robin pool. Use whenever the user needs real-time web search, current information, fact-checking, URL content extraction, or site crawling — even if they don't say "web search" explicitly (e.g. "what's the latest", "look up", "find information about", "check this URL", "research", "联网搜索", "查一下", "搜索", "查找资料", "搜索网页", "提取网页", "爬取网站"). Also trigger on "tavily", "search the web", or any request for live/current data. This is the primary web search tool.
---

# Tavily Web Search

Real-time web search and content extraction via [Tavily API](https://tavily.com). Uses a multi-key round-robin pool with automatic exhaustion recovery (keys reset monthly).

## Quick Start

All commands live in `scripts/tavily.py`. The script reads `TAVILY_API_KEYS` from your environment (already configured globally).

```bash
# Web search
python scripts/tavily.py search "your query"

# URL content extraction
python scripts/tavily.py extract "https://example.com"

# Website crawling
python scripts/tavily.py crawl "https://docs.example.com"

# Key pool status
python scripts/tavily.py status
```

## Commands

### `search` — Web Search

Search the web for information. This is the most-used command.

```bash
python scripts/tavily.py search <query> [options]
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
python scripts/tavily.py search "latest AI research 2026"
python scripts/tavily.py search "Python 3.13 release" --topic news --time-range month
python scripts/tavily.py search "LLM safety" --depth advanced --max-results 15
python scripts/tavily.py search "React hooks" --include-domains "react.dev" --max-results 5
```

### `extract` — URL Content Extraction

Extract clean, readable content from web pages. Removes ads, navigation, clutter.

```bash
python scripts/tavily.py extract <url1> [url2...] [--depth basic|advanced]
```

**Examples:**
```bash
python scripts/tavily.py extract "https://example.com/article"
python scripts/tavily.py extract "https://url1.com" "https://url2.com" --depth advanced
```

### `crawl` — Website Crawling

Crawl a website starting from a URL, following links recursively.

```bash
python scripts/tavily.py crawl <url> [options]
```

| Option | Default | Description |
|--------|---------|-------------|
| `--max-depth N` | `1` | How deep to follow links |
| `--max-breadth N` | `20` | Max links per level |
| `--limit N` | `50` | Total pages to crawl |
| `--instructions TEXT` | — | Custom instructions for the crawler |

**Example:**
```bash
python scripts/tavily.py crawl "https://docs.python.org" --max-depth 2 --limit 30
```

### `map` — Site Structure

Map a website's structure (URLs only, no content).

```bash
python scripts/tavily.py map <url> [--max-depth N] [--max-breadth N] [--limit N]
```

### `status` — Key Pool Health

```bash
python scripts/tavily.py status
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
