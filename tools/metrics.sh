#!/usr/bin/env sh
# Budget report for Linux and macOS.
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ISSUES="$ROOT/artifacts/issues"

if [ ! -d "$ISSUES" ]; then
    echo "No artifacts/issues directory: $ISSUES"
    exit 0
fi

field() {
    sed -n "s/^$1:[[:space:]]*//p" "$2" | head -n 1 | sed 's/^"//;s/"$//'
}

count=0
over=""
task_list=$(mktemp "${TMPDIR:-/tmp}/opencode-team-metrics.XXXXXX")
trap 'rm -f "$task_list"' EXIT INT TERM
find "$ISSUES" -type f -name '*-task.md' 2>/dev/null | sort > "$task_list"

if [ ! -s "$task_list" ]; then
    echo 'No task files found under artifacts/issues.'
    exit 0
fi

printf '%-42s %-10s %-6s %-18s %-18s %-12s\n' 'TASK' 'STATE' 'ROUND' 'STEPS' 'TOKENS' 'UPDATED'
printf '%-42s %-10s %-6s %-18s %-18s %-12s\n' '----' '-----' '-----' '-----' '------' '-------'

while IFS= read -r file; do
    [ -n "$file" ] || continue
    count=$((count + 1))
    state=$(field state "$file")
    round=$(field round "$file")
    steps_used=$(field steps_used "$file")
    steps_budget=$(field steps_budget "$file")
    tokens_used=$(field tokens_estimate "$file")
    tokens_budget=$(field tokens_budget "$file")
    updated=$(field updated "$file")

    steps="$steps_used"
    steps_percent=""
    if [ "$steps_budget" != "null" ] && [ "$steps_budget" != "" ] && [ "$steps_used" != "null" ] && [ "$steps_used" != "" ]; then
        steps_percent=$(awk -v u="$steps_used" -v b="$steps_budget" 'BEGIN { if (b > 0) printf "%.0f", 100 * u / b }')
        steps="$steps_used/$steps_budget (${steps_percent}%)"
    fi

    tokens="$tokens_used"
    tokens_percent=""
    if [ "$tokens_budget" != "null" ] && [ "$tokens_budget" != "" ] && [ "$tokens_used" != "null" ] && [ "$tokens_used" != "" ]; then
        tokens_percent=$(awk -v u="$tokens_used" -v b="$tokens_budget" 'BEGIN { if (b > 0) printf "%.0f", 100 * u / b }')
        tokens="$tokens_used/$tokens_budget (${tokens_percent}%)"
    fi

    if { [ -n "$steps_percent" ] && [ "$steps_percent" -ge 100 ]; } || { [ -n "$tokens_percent" ] && [ "$tokens_percent" -ge 100 ]; }; then
        over="${over}
  ${file#$ROOT/}"
    fi

    printf '%-42s %-10s %-6s %-18s %-18s %-12s\n' \
        "${file#$ROOT/}" "$state" "$round" "$steps" "$tokens" "$updated"
done < "$task_list"

if [ "$count" -eq 0 ]; then
    echo 'No task files found under artifacts/issues.'
    exit 0
fi

if [ -n "$over" ]; then
    printf '\nOver budget:\n%s\n' "$over"
else
    printf '\nNo task is over budget.\n'
fi
