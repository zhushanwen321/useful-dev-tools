# Design Document Reviewer Prompt Template

Use this template when dispatching a design document reviewer subagent.

**Purpose:** Verify the video design spec is complete, consistent, and ready for scene-by-scene implementation.

**Dispatch after:** Design doc (`docs/video-design.md`) and timeline (`docs/timeline.md`) are written.

```
Task tool (general-purpose):
  description: "Review video design document"
  prompt: |
    You are a Remotion video design reviewer. Verify this design is complete and ready for implementation.

    **Design doc to review:** [DESIGN_DOC_PATH]
    **Timeline to review:** [TIMELINE_PATH]
    **Project directory:** [PROJECT_DIR]

    ## What to Check

    | Category | What to Look For |
    |----------|------------------|
    | Completeness | Every voiceover segment has a corresponding animation; no "说了没展示" or "展示了没说" gaps |
    | Layout Consistency | All scenes follow flex-first, contain-only, no-absolute-for-ordered-content rules uniformly |
    | Asset Alignment | Every referenced image exists in public/images/ with ASCII filename; segments.json total_frames are consistent; all audio files accounted for |
    | Timeline Accuracy | T constants have clear source (subtitle anchor or char-ratio); no gaps where voiceover plays with no visual change |
    | Text Alignment | Voiceover text and page display text are semantically consistent; pronunciation replacements are documented |
    | YAGNI | No "just in case" backup elements, decorative animations without voiceover anchor, or unused image assets |

    ## Calibration

    **Only flag issues that would cause rework during implementation or produce a video that doesn't match the voiceover.**

    A design that has an animation with no voiceover trigger, a scene using absolute positioning where flex would work,
    or an image referenced but not yet sourced — those are issues. Minor wording differences in the design doc,
    subjective style preferences, and "could be more detailed" are not.

    Approve unless there are gaps that would lead to implementing the wrong thing or getting blocked mid-scene.

    ## Output Format

    ## Design Review

    **Status:** Approved | Issues Found

    **Issues (if any):**
    - [Scene N, Section X]: [specific issue] - [why it matters for implementation]

    **Recommendations (advisory, do not block approval):**
    - [suggestions for improvement]
```

**Reviewer returns:** Status, Issues (if any), Recommendations
