#!/usr/bin/env sh
# Static team integrity check for POSIX systems, including Git Bash/MSYS2 on Windows.
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
passes=0
fails=0

pass() {
    passes=$((passes + 1))
    printf 'PASS  %s\n' "$1"
}

fail() {
    fails=$((fails + 1))
    printf 'FAIL  %s\n' "$1"
}

echo "Team integrity check: $ROOT"

for file in README.md config.yml agents/teamlead.md agents/analyst.md agents/developer.md agents/tester.md \
    tools/check-team.sh tools/check-runtime.sh tools/metrics.sh \
    assets/opencode/opencode-dev-team-light.svg assets/opencode/opencode-dev-team-dark.svg; do
    if [ -f "$ROOT/$file" ]; then
        pass "required file: $file"
    else
        fail "missing required file: $file"
    fi
done

for dir in artifacts/issues artifacts/requirements artifacts/qa/reports artifacts/retrospectives artifacts/preconditions; do
    if [ -d "$ROOT/$dir" ]; then
        pass "template directory: $dir"
    else
        fail "missing template directory: $dir"
    fi
done

extra=$(find "$ROOT/artifacts" -type f ! -name '.gitkeep' -print 2>/dev/null)
if [ -n "$extra" ]; then
    fail "team artifacts template contains real files: $extra"
else
    pass 'team artifacts template contains only .gitkeep'
fi

for script in "$ROOT"/tools/*.sh; do
    [ -e "$script" ] || continue
    name=$(basename "$script")
    if grep -q "$(printf '\r')" "$script"; then
        fail "CRLF line endings in POSIX script: $name"
    else
        pass "LF line endings: $name"
    fi
done

for agent in "$ROOT"/agents/*.md; do
    [ -e "$agent" ] || continue
    name=$(basename "$agent")
    if grep -q '^---$' "$agent" && grep -q '^steps: [0-9]' "$agent"; then
        pass "agent frontmatter: $name"
    else
        fail "agent frontmatter or steps missing: $name"
    fi
done

for pattern in 'git rm *' 'git branch -D *' 'git tag -d *' 'git stash drop *' 'git stash clear *' \
    'git reflog expire *' 'git gc --prune=*' 'Clear-Content *' 'ri *' 'erase *'; do
    for agent in "$ROOT"/agents/*.md; do
        [ -e "$agent" ] || continue
        name=$(basename "$agent")
        if grep -Fq "resource: \"$pattern\"" "$agent"; then
            pass "deny present in $name: $pattern"
        else
            fail "missing deny in $name: $pattern"
        fi
    done
done

for agent in "$ROOT"/agents/*.md; do
    [ -e "$agent" ] || continue
    name=$(basename "$agent")
    if grep -Fq 'resource: "* publish*"' "$agent"; then
        pass "narrow publish deny in $name"
    else
        fail "narrow publish deny missing in $name"
    fi
    if grep -Fq 'resource: "*publish*"' "$agent"; then
        fail "broad publish deny still present in $name"
    fi
done

teamlead="$ROOT/agents/teamlead.md"
for zone in 'artifacts/requirements/**' 'artifacts/qa/**'; do
    if grep -A1 -F "resource: \"$zone\"" "$teamlead" | grep -Fq 'effect: deny'; then
        pass "teamlead deny: $zone"
    else
        fail "teamlead must deny write: $zone"
    fi
done
if grep -A1 -F 'resource: "artifacts/actions.md"' "$teamlead" | grep -Fq 'effect: allow'; then
    pass 'teamlead can write artifacts/actions.md'
else
    fail 'teamlead actions register permission missing'
fi
if grep -A1 -F 'resource: ".opencode/config.yml"' "$teamlead" | grep -Fq 'effect: allow'; then
    pass 'teamlead can edit .opencode/config.yml'
else
    fail 'teamlead config.yml permission missing'
fi
for field in steps_budget tokens_budget steps_used tokens_estimate; do
    if grep -Fq "$field" "$teamlead"; then
        pass "teamlead budget field: $field"
    else
        fail "teamlead budget field missing: $field"
    fi
done
for key in 'budget:' 'task_steps:' 'task_tokens:'; do
    if grep -Fq "$key" "$ROOT/config.yml"; then
        pass "config budget key: $key"
    else
        fail "config budget key missing: $key"
    fi
done

for command in "$ROOT"/commands/*.md; do
    [ -e "$command" ] || continue
    name=$(basename "$command" .md)
    if grep -q '^description:' "$command"; then
        pass "command description: $name"
    else
        fail "command description missing: $name"
    fi
    if [ "$name" != "architect" ]; then
        if grep -q '^agent: teamlead' "$command"; then
            pass "command agent: $name"
        else
            fail "command agent must be teamlead: $name"
        fi
        if grep -Fq 'teamlead' "$command"; then
            pass "root guard reference: $name"
        else
            fail "root guard reference missing: $name"
        fi
    fi
    if grep -Fq "\`/$name\`" "$ROOT/README.md"; then
        pass "README lists command: $name"
    else
        fail "README does not list command: $name"
    fi
done

for file in "$ROOT"/agents/*.md "$ROOT"/commands/*.md "$ROOT/README.md" "$ROOT/config.yml"; do
    [ -e "$file" ] || continue
    if grep -Eq 'qa/reports/<[^>]+>-YYYY-MM-DD\.md' "$file"; then
        fail "old date-based QA report path in $file"
    fi
    if grep -Fq 'git status --short' "$file"; then
        fail "hardcoded git status in $file"
    fi
    if grep -Fq 'git diff --stat' "$file"; then
        fail "hardcoded git diff in $file"
    fi
    if grep -Fq 'D:\' "$file" || grep -Fq 'C:\' "$file"; then
        fail "local Windows path in $file"
    fi
    if grep -Fq '/Users/' "$file" || grep -Fq '/home/' "$file"; then
        fail "local POSIX path in $file"
    fi
done
pass 'forbidden pattern scan completed'

empty_names=$(grep -c '^[[:space:]]*name: ""[[:space:]]*$' "$ROOT/config.yml" || true)
if [ "$empty_names" -eq 4 ]; then
    pass 'config.yml contains no personal names'
else
    fail "config.yml must contain four empty name fields, found $empty_names"
fi

printf '\nPASS: %s  FAIL: %s\n' "$passes" "$fails"
[ "$fails" -eq 0 ] || exit 1
