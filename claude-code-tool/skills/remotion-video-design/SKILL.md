---
name: remotion-video-design
description: Use when starting a new Remotion video project, adding scenes to an existing video, or converting a script into a video. Handles asset readiness, pronunciation pre-check, segment-based voiceover generation, subtitle-based timeline calculation, and produces a complete design spec. Required before remotion-video-development. Also handles voiceover generation and timeline alignment via remotion-tools scripts.
---

# Remotion Video Design

## Overview

Before writing a single line of Remotion code, lock down the three biggest sources of rework: **assets, layout, and timing**. This skill guides a structured dialogue to produce a complete design spec (design-system + timeline.md + layout spec) that the execution skill can implement in one pass.

**Core principle:** 80% of video project rework comes from three "unknowns" — copy unknown, assets unknown, layout unknown. Resolve all three before coding.

## When to Use

- Starting a new Remotion video project
- Adding new scenes to an existing video
- Receiving a script/text document and asked to "make a video from this"

**Do NOT use for:**
- Minor tweaks to existing scenes (use remotion-video-review instead)
- Technical Remotion questions (use remotion-best-practices instead)

**Pipeline position:** First step in video creation. Output feeds into remotion-video-development.

## Process Flow

```dot
digraph design {
    rankdir=TB;
    "Check assets readiness" [shape=box];
    "Assets ready?" [shape=diamond];
    "Block: list missing assets" [shape=box];
    "Define design system" [shape=box];
    "Confirm with 1-frame render" [shape=box];
    "User approves style?" [shape=diamond];
    "Scene structure + layout spec" [shape=box];
    "Calculate timeline (subtitle timestamps)" [shape=box];
    "User reviews timeline?" [shape=diamond];
    "Write design doc" [shape=doublecircle];

    "Check assets readiness" -> "Assets ready?";
    "Assets ready?" -> "Block: list missing assets" [label="no"];
    "Block: list missing assets" -> "Check assets readiness" [label="user provides"];
    "Assets ready?" -> "Define design system" [label="yes"];
    "Define design system" -> "Confirm with 1-frame render";
    "Confirm with 1-frame render" -> "User approves style?";
    "User approves style?" -> "Define design system" [label="no"];
    "User approves style?" -> "Scene structure + layout spec" [label="yes"];
    "Scene structure + layout spec" -> "Calculate timeline (char-ratio)";
    "Calculate timeline (char-ratio)" -> "User reviews timeline?";
    "User reviews timeline?" -> "Scene structure + layout spec" [label="adjust"];
    "User reviews timeline?" -> "Write design doc" [label="approved"];
}
```

## Step 1: Assets Readiness Gate

Check all three asset types exist and are production-ready:

```
ASSETS CHECKLIST:
[ ] Final copy/script text (text.md or equivalent)
[ ] Voiceover audio files (public/voiceover/) — sentence-level generation
    - Use `python ~/.claude/skills/remotion-tools/generate-voiceover.py`
    - Requires `voiceover-text.json` in project root
    - **Segment-based output:** one MP3 per sentence:
      - `scene{N}_seg{K}.mp3` — audio for sentence K
      - `scene{N}_seg{K}_subtitle.json` — timestamps from Minimax
      - `scene{N}_segments.json` — metadata: cumulative frames, durations, offsets
    - **CLI flags:**
      - `--scene scene3` — only generate a specific scene
      - `--segment 1` — only regenerate one sentence (requires --scene)
      - `--force` — regenerate even if file exists (archives old as _v1, _v2)
    - **Incremental:** skips existing segments unless `--force`
    - **Version archiving:** old files renamed to `_v1`, `_v2` etc., never deleted
    - Primary TTS: Minimax speech-2.8-hd, voice Chinese (Mandarin)_Gentleman
    - Fallback: edge-tts zh-CN-YunxiNeural rate=+10%
    - Key lookup: env var MINIMAX_API_KEY → .env file → llm-simple-router/minimax-key
    - **Pronunciation rules:** Auto-loaded from `~/.claude/voice-replace-text/minimax-tts.json`
[ ] Screenshot/image assets (public/images/)
    - All filenames MUST be ASCII (staticFile requirement)
    - Each image must have a stated purpose (which scene, which point)
[ ] Font choice confirmed (default: NotoSansSC)
```

**If any asset missing:** List exactly what's needed and STOP. Do not proceed until user provides.

### Step 1a: Create voiceover-text.json

After voiceover text is finalized, create `voiceover-text.json` in project root:

```json
{
  "scenes": {
    "scene1": "完整配音文本...",
    "scene2": "完整配音文本..."
  }
}
```

This file is the single source of truth for both `generate-voiceover.py` and `prepare-minimax-text.py`.

### Step 1b: Pronunciation Pre-check

**Before generating voiceover**, scan the voiceover text for TTS-prone words. This is a proactive check — catch pronunciation problems before paying for TTS generation.

**Read existing rules:** `~/.claude/voice-replace-text/minimax-tts.json`

**Scan for these high-risk patterns:**

| Pattern | Examples | Why TTS fails |
|---------|----------|---------------|
| English brand/product names | Kimi, GLM, DeepSeek, doubao | Read letter-by-letter or wrong phonetics |
| English + number combos | K2.5, K2.6, V4, GPT-4 | Number part mangled or skipped |
| Hyphenated compounds | llm-simple-router, cross-platform | Read as separate words with wrong pauses |
| All-caps abbreviations | API, TTS, LLM, DS | Spelled out instead of pronounced |
| Mixed zh/en phrases | "一个月200块" | Number unit confusion |
| Chinese tech terms | 豆包, 火山方舟 | May need context for correct reading |

**Pre-check process:**

1. Read `~/.claude/voice-replace-text/minimax-tts.json` to see existing rules
2. Scan voiceover text for words matching the high-risk patterns above that are NOT already in the rules
3. If new risky words found, present to user:
   ```
   以下词语可能被 TTS 读错，建议添加发音替换规则：
   - "DeepSeek" → 建议 "deep seek" （可能逐字母读）
   - "GPT-4" → 建议 "G P T 四" （数字部分可能读错）
   是否添加到 ~/.claude/voice-replace-text/minimax-tts.json？
   ```
4. User confirms → add to JSON, user declines → skip
5. Only proceed to voiceover generation after pre-check is clear

## Step 2: Design System

Produce `src/styles/theme.ts` with:

| Category | Must Define | Default |
|----------|-------------|---------|
| Colors | bg, primary, secondary, text, error, success | Warm cream + deep red-orange |
| Font sizes | xs through hero (6 levels) | 14px-80px |
| Spacing | xs through xl (4 levels) | 6px-36px, compact bias |
| Scene durations | Per-scene frame counts | From voiceover duration |
| Image map | ASCII filename constants | All images used |

**One-frame verification:** Render a single frame of Scene 1 with `npx remotion still`. Show to user. Get "this feels right" before proceeding.

## Step 3: Scene Structure + Layout Spec

For each scene, produce a structured layout description. **Use this format, not natural language:**

```yaml
sceneN:
  voiceover: "exact text from voiceover"
  layout:
    type: vertical | horizontal | grid
    regions:
      - name: "title area"
        type: flex-column
        content: [title_text, divider]
      - name: "main area"
        type: horizontal-split
        left: [element_list]
        right: [element_list]
        alignment: flex-start | flex-end | center | stretch
  elements:
    - id: elem1
      type: text | card | image | bar-chart | block
      content: "..."
      style: { fontSize, color, fontWeight }
      timing: { enter: frameN, animation: fadeIn | bounce | typewriter }
  image_rules:
    - MUST use objectFit: contain (never cover for screenshots)
    - MUST have macOS title bar for screenshot windows
    - MUST have caption below
```

**Layout principles (apply to ALL scenes):**
- Prefer flex flow over absolute positioning for ordered elements
- Use absolute positioning ONLY for overlay elements
- Use `alignItems: "flex-end"` for bottom alignment, not hardcoded heights
- Use `margin: "0 auto"` + fixed width for centered sections
- Content width: 80% or fixed (e.g., 1344px), never percentage for precise layouts

## Step 4: Timeline Calculation (Minimax Subtitle Timestamps)

**Primary method:** Use Minimax TTS `subtitle_enable` feature which returns sentence-level timestamps.

### Workflow

1. **Generate voiceover** with `~/.claude/skills/remotion-tools/generate-voiceover.py` — outputs per-segment `scene{N}_seg{K}_subtitle.json` + `scene{N}_segments.json`
2. **Run alignment script** to extract precise frame numbers:
   ```bash
   python ~/.claude/skills/remotion-tools/align-timeline.py
   ```
   Reads `*_segments.json` to auto-discover scenes, accumulates segment offsets, produces `docs/timeline-auto.md`
3. **Map segments to animations:** For each animation trigger point, find which subtitle segment it belongs to:
   - If animation aligns with a segment **start** → use `seg_begin_frame` directly
   - If animation is **within** a segment → use character-ratio inside that segment only:
     ```
     seg_start = subtitle_seg.begin_frame
     seg_duration = subtitle_seg.end_frame - subtitle_seg.begin_frame
     offset_frames = (chars_before / seg_total_chars) * seg_duration
     animation_frame = seg_start + offset_frames
     ```

### Output format (`docs/timeline.md`)

```markdown
## SceneN (X frames, ~Ys)

### Subtitle segments (from Minimax)
| Seg | Begin Frame | End Frame | Duration | Text |
|-----|-------------|-----------|----------|------|
| 0   | 15          | 443       | 428f     | 昨晚买的... |
| 1   | 448         | 846       | 398f     | 右侧上面... |

### Animation timeline
| Frame | Animation | Matches voiceover | Source |
|-------|-----------|-------------------|--------|
| 15    | Title     | seg0 start        | subtitle |
| 210   | Left img  | "左侧是实际..."   | seg0 char-ratio |
| 448   | Right top | seg1 start        | subtitle |
```

**Key advantage:** Subtitle timestamps provide paragraph-level anchors (±1 frame accuracy). Character-ratio is only used for intra-paragraph positioning, eliminating cumulative error.

**Fallback:** If subtitle files are missing (edge-tts fallback, API error), use pure character-ratio method as documented in remotion-best-practices.

## Step 5: Write Design Doc

Save to `docs/video-design.md`:
- Design system summary (colors, fonts, spacing)
- Per-scene layout spec (structured YAML)
- Timeline reference (link to timeline.md)
- Asset list with filenames

**Design review (two layers):**

1. **Self-review checklist** — fix inline, no subagent needed:
   - [ ] Every voiceover segment has a corresponding animation
   - [ ] Every image asset is referenced by ASCII filename
   - [ ] Layout uses flex flow (not absolute) for ordered content
   - [ ] No `objectFit: cover` for screenshots
   - [ ] Voiceover text and page text are semantically consistent
   - [ ] TTS pronunciation fixes noted (e.g., "doubao" → "豆包" in voiceover)

2. **Independent reviewer** — dispatch subagent using `design-reviewer-prompt.md` in this skill directory. Checks completeness, layout consistency, asset alignment, timeline accuracy, YAGNI. Only flags issues that would cause rework during implementation.

**Transition:** After design review passes and user approves, invoke remotion-video-development skill.

## Red Flags

- User says "just start coding, we'll figure it out" → Resist. List what's unknown.
- No voiceover audio yet → Generate first, frame counts depend on duration.
- User describes layout as "move X a bit to the left" → Ask for structured description.
- Images have Chinese filenames → Rename to ASCII before proceeding.
