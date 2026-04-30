#!/bin/bash
# 收集代码审查上下文：语言检测、diff 统计、lint 结果、文件分组建议
# Usage: review-context.sh [--against main] [--staged] [--path <dir>]
# Output: JSON 格式的结构化审查上下文
set -euo pipefail

AGAINST="main"
STAGED=false
TARGET_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --against) AGAINST="$2"; shift 2 ;;
        --staged)  STAGED=true; shift ;;
        --path)    TARGET_PATH="$2"; shift 2 ;;
        *)         echo "Unknown option: $1"; exit 1 ;;
    esac
done

# --- Diff 统计 ---
echo "{"

if $STAGED; then
    DIFF_STAT=$(git diff --cached --stat 2>/dev/null || echo "")
    DIFF_FILES=$(git diff --cached --name-only 2>/dev/null || echo "")
    TOTAL_FILES=$(git diff --cached --stat 2>/dev/null | tail -1 | grep -oE '[0-9]+ files? changed' | grep -oE '[0-9]+' || echo "0")
    TOTAL_INSERTIONS=$(git diff --cached --shortstat 2>/dev/null | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' || echo "0")
    TOTAL_DELETIONS=$(git diff --cached --shortstat 2>/dev/null | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+' || echo "0")
else
    DIFF_STAT=$(git diff "$AGAINST"...HEAD --stat -- ${TARGET_PATH:-.} 2>/dev/null || git diff --stat -- ${TARGET_PATH:-.} 2>/dev/null || echo "")
    DIFF_FILES=$(git diff "$AGAINST"...HEAD --name-only -- ${TARGET_PATH:-.} 2>/dev/null || git diff --name-only -- ${TARGET_PATH:-.} 2>/dev/null || echo "")
    TOTAL_FILES=$(echo "$DIFF_FILES" | grep -c . 2>/dev/null || echo "0")
    TOTAL_INSERTIONS=$(git diff "$AGAINST"...HEAD --shortstat -- ${TARGET_PATH:-.} 2>/dev/null | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' || echo "0")
    TOTAL_DELETIONS=$(git diff "$AGAINST"...HEAD --shortstat -- ${TARGET_PATH:-.} 2>/dev/null | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+' || echo "0")
fi

echo "  \"total_files\": $TOTAL_FILES,"
echo "  \"total_insertions\": $TOTAL_INSERTIONS,"
echo "  \"total_deletions\": $TOTAL_DELETIONS,"

# --- 语言检测 ---
echo "  \"languages\": ["

TS_FILES=""
RS_FILES=""
PY_FILES=""
OTHER_FILES=""

for f in $DIFF_FILES; do
    case "$f" in
        *.ts|*.tsx|*.vue) TS_FILES="${TS_FILES:+$TS_FILES }$f" ;;
        *.rs)              RS_FILES="${RS_FILES:+$RS_FILES }$f" ;;
        *.py)              PY_FILES="${PY_FILES:+$PY_FILES }$f" ;;
        *)                 OTHER_FILES="${OTHER_FILES:+$OTHER_FILES }$f" ;;
    esac
done

LANG_ENTRIES=""
add_lang_entry() {
    local lang="$1" agent="$2" count="$3" files="$4"
    if [[ -n "$files" ]]; then
        local entry="    {\"language\": \"$lang\", \"agent\": \"$agent\", \"file_count\": $count, \"files\": \"$files\"}"
        LANG_ENTRIES="${LANG_ENTRIES:+$LANG_ENTRIES,
}$entry"
    fi
}

add_lang_entry "TypeScript/Vue" "ts-taste-check" "$(echo $TS_FILES | wc -w | tr -d ' ')" "$TS_FILES"
add_lang_entry "Rust" "rust-taste-check" "$(echo $RS_FILES | wc -w | tr -d ' ')" "$RS_FILES"
add_lang_entry "Python" "code-reviewer" "$(echo $PY_FILES | wc -w | tr -d ' ')" "$PY_FILES"
add_lang_entry "Other" "code-reviewer" "$(echo $OTHER_FILES | wc -w | tr -d ' ')" "$OTHER_FILES"

echo "$LANG_ENTRIES"
echo "  ],"

# --- 工作量评估 ---
TOTAL_LINES=$((TOTAL_INSERTIONS + TOTAL_DELETIONS))
if [[ $TOTAL_FILES -lt 10 ]] && [[ $TOTAL_LINES -lt 500 ]]; then
    EFFORT="simple"
elif [[ $TOTAL_FILES -lt 30 ]] && [[ $TOTAL_LINES -lt 3000 ]]; then
    EFFORT="medium"
else
    EFFORT="complex"
fi
echo "  \"effort\": \"$EFFORT\","

# --- 文件分组建议 ---
echo "  \"suggested_groups\": ["
# 按目录分组，每组最多 5 个文件
if [[ -n "$DIFF_FILES" ]]; then
    GROUPS=""
    CURRENT_DIR=""
    CURRENT_FILES=""
    CURRENT_COUNT=0
    GROUP_IDX=0

    for f in $DIFF_FILES; do
        DIR=$(dirname "$f" | cut -d/ -f1-2)
        if [[ "$DIR" != "$CURRENT_DIR" ]] || [[ $CURRENT_COUNT -ge 5 ]]; then
            if [[ -n "$CURRENT_FILES" ]]; then
                GROUP_IDX=$((GROUP_IDX + 1))
                ENTRY="    {\"group\": $GROUP_IDX, \"directory\": \"$CURRENT_DIR\", \"files\": \"$CURRENT_FILES\", \"file_count\": $CURRENT_COUNT}"
                GROUPS="${GROUPS:+$GROUPS,
}$ENTRY"
            fi
            CURRENT_DIR="$DIR"
            CURRENT_FILES="$f"
            CURRENT_COUNT=1
        else
            CURRENT_FILES="$CURRENT_FILES $f"
            CURRENT_COUNT=$((CURRENT_COUNT + 1))
        fi
    done
    # 最后一组
    if [[ -n "$CURRENT_FILES" ]]; then
        GROUP_IDX=$((GROUP_IDX + 1))
        ENTRY="    {\"group\": $GROUP_IDX, \"directory\": \"$CURRENT_DIR\", \"files\": \"$CURRENT_FILES\", \"file_count\": $CURRENT_COUNT}"
        GROUPS="${GROUPS:+$GROUPS,
}$ENTRY"
    fi
    echo "$GROUPS"
fi
echo "  ],"

# --- Lint 结果 ---
echo "  \"lint\": {"
LINT_RESULT="not_configured"
if [[ -f "eslint.config.mjs" ]] || [[ -f "eslint.config.js" ]] || [[ -f ".eslintrc.js" ]]; then
    LINT_OUTPUT=$(npx eslint --max-warnings=0 ${TARGET_PATH:-.} 2>&1) && LINT_RESULT="passed" || LINT_RESULT="failed"
    echo "    \"tool\": \"eslint\","
    echo "    \"result\": \"$LINT_RESULT\","
    # 转义 lint 输出中的引号
    ESCAPED_OUTPUT=$(echo "$LINT_OUTPUT" | head -50 | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | awk '{printf "%s\\n", $0}')
    echo "    \"output\": \"$ESCAPED_OUTPUT\""
elif [[ -f "Cargo.toml" ]]; then
    LINT_OUTPUT=$(cargo clippy -- -W clippy::all 2>&1) && LINT_RESULT="passed" || LINT_RESULT="failed"
    echo "    \"tool\": \"clippy\","
    echo "    \"result\": \"$LINT_RESULT\","
    ESCAPED_OUTPUT=$(echo "$LINT_OUTPUT" | head -50 | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | awk '{printf "%s\\n", $0}')
    echo "    \"output\": \"$ESCAPED_OUTPUT\""
else
    echo "    \"tool\": \"none\","
    echo "    \"result\": \"$LINT_RESULT\","
    echo "    \"output\": \"\""
fi
echo "  }"

echo "}"
