#!/bin/bash
# Inject local directory override rules into superpowers SKILL.md files.
# Called by .git/hooks/post-merge after each git pull.
# Can also be run manually for initial setup.
#
# Usage: ./inject-superpowers-override.sh [repo_root]
#   repo_root defaults to /Users/zhushanwen/GitApp/superpowers

set -euo pipefail

REPO_ROOT="${1:-/Users/zhushanwen/GitApp/superpowers}"
MARKER_START="<!-- LOCAL-OVERRIDE:START -->"
MARKER_END="<!-- LOCAL-OVERRIDE:END -->"

# Use a heredoc with a unique delimiter to avoid variable expansion issues
read -r -d '' OVERRIDE_BLOCK << 'OVERRIDE_EOF' || true
<!-- LOCAL-OVERRIDE:START -->
## 本地目录覆盖规则

**以下规则覆盖本文档中所有关于输出目录的路径指定**（如 `docs/superpowers/specs/`、`docs/superpowers/plans/` 等）：

- **主目录：** `.superpowers/`（项目根目录下）
- **子目录命名：** `${yyyy-MM-dd}-${主题简短标题}`（例：`2026-04-14-core-proxy`）
- **路径映射：**
  - `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md` → `.superpowers/${主题}/spec.md`
  - `docs/superpowers/plans/YYYY-MM-DD-<feature>.md` → `.superpowers/${主题}/plan.md`
  - 其他文档按需拆分到 `.superpowers/${主题}/` 下
- **不同主题使用不同子目录，禁止混放**

**文档精简：** 单次写入超过 1000 字时优先拆分子文档，主文档保留概述和索引。使用 agent 并行编写各模块文档（并发度 ≤ 2），最后合成精简主文档。
<!-- LOCAL-OVERRIDE:END -->
OVERRIDE_EOF

cd "$REPO_ROOT"

injected=0
skipped=0

for skill_dir in skills/*/; do
  [ -d "$skill_dir" ] || continue
  skill_md="$skill_dir/SKILL.md"
  [ -f "$skill_md" ] || continue

  # Remove existing override block (marker to end of file)
  if grep -qF "$MARKER_START" "$skill_md" 2>/dev/null; then
    # Find marker line number, truncate from there
    marker_line=$(grep -nF "$MARKER_START" "$skill_md" | head -1 | cut -d: -f1)
    if [ -n "$marker_line" ]; then
      # Remove blank lines immediately before the marker too
      head -n "$((marker_line - 1))" "$skill_md" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' > "${skill_md}.tmp"
      mv "${skill_md}.tmp" "$skill_md"
    fi
  fi

  # Append override block
  printf '\n%s\n' "$OVERRIDE_BLOCK" >> "$skill_md"

  # Tell git to ignore local modifications
  git update-index --skip-worktree "$skill_md" 2>/dev/null || true

  injected=$((injected + 1))
  echo "  [injected] $(basename "$skill_dir")"
done

echo "Done: $injected skills injected, $skipped skipped."
echo ""
echo "NOTE: git update-index --skip-worktree is set for all modified files."
echo "Run 'git update-index --no-skip-worktree <file>' to undo."
