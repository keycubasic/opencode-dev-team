#!/usr/bin/env sh
# Runtime permission check for Linux and macOS.
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

if ! command -v opencode >/dev/null 2>&1; then
    echo 'FAIL  opencode CLI not found in PATH'
    exit 1
fi

tmp=$(mktemp -d "${TMPDIR:-/tmp}/opencode-team-runtime.XXXXXX")
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT INT TERM

mkdir -p "$tmp/.opencode"
cp -R "$ROOT"/. "$tmp/.opencode"/
cat > "$tmp/opencode.jsonc" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "default_agent": "teamlead"
}
EOF

if ! (cd "$tmp" && opencode debug agents > "$tmp/agents.json" 2>/dev/null); then
    echo 'FAIL  opencode debug agents failed'
    exit 1
fi

PYTHON=${PYTHON:-}
if [ -n "$PYTHON" ] && "$PYTHON" -c 'import json' >/dev/null 2>&1; then
    :
elif command -v python3 >/dev/null 2>&1 && python3 -c 'import json' >/dev/null 2>&1; then
    PYTHON=python3
elif command -v python >/dev/null 2>&1 && python -c 'import json' >/dev/null 2>&1; then
    PYTHON=python
fi

if [ -n "$PYTHON" ]; then
    "$PYTHON" - "$tmp/agents.json" "$ROOT" <<'PY'
import json
import os
import re
import sys

agents = json.load(open(sys.argv[1], encoding="utf-8"))
root = sys.argv[2]
by_id = {agent.get("id"): agent for agent in agents}
passes = 0
fails = 0


def ok(message):
    global passes
    passes += 1
    print("PASS  " + message)


def bad(message):
    global fails
    fails += 1
    print("FAIL  " + message)


def has(agent, action, resource, effect):
    for permission in agent.get("permissions", []):
        if (permission.get("action") == action and
                permission.get("resource") == resource and
                permission.get("effect") == effect):
            return True
    return False


def expected_steps(agent_id):
    path = os.path.join(root, "agents", agent_id + ".md")
    text = open(path, encoding="utf-8").read()
    match = re.search(r"(?m)^steps:\s*(\d+)", text)
    return int(match.group(1)) if match else None


for agent_id, mode in (
    ("teamlead", "primary"),
    ("analyst", "subagent"),
    ("developer", "subagent"),
    ("tester", "subagent"),
):
    agent = by_id.get(agent_id)
    if not agent:
        bad("agent not loaded: " + agent_id)
        continue
    if agent.get("mode") == mode:
        ok("agent mode: " + agent_id)
    else:
        bad("agent mode mismatch: %s is %s" % (agent_id, agent.get("mode")))
    steps = expected_steps(agent_id)
    if steps is None:
        bad("steps not found in agents/%s.md" % agent_id)
    elif agent.get("steps") == steps:
        ok("agent steps: " + agent_id)
    else:
        bad("agent steps mismatch: %s is %s, expected %s" % (agent_id, agent.get("steps"), steps))

teamlead = by_id.get("teamlead")
if teamlead:
    for zone in ("artifacts/requirements/**", "artifacts/qa/**"):
        if has(teamlead, "edit", zone, "deny"):
            ok("runtime teamlead deny: " + zone)
        else:
            bad("runtime teamlead deny missing: " + zone)
    if has(teamlead, "edit", "artifacts/actions.md", "allow"):
        ok("runtime teamlead allow: artifacts/actions.md")
    else:
        bad("runtime teamlead allow missing: artifacts/actions.md")
    if has(teamlead, "edit", ".opencode/config.yml", "allow"):
        ok("runtime teamlead allow: .opencode/config.yml")
    else:
        bad("runtime teamlead allow missing: .opencode/config.yml")
    if has(teamlead, "question", "*", "allow"):
        ok("runtime teamlead question: allow")
    else:
        bad("runtime teamlead question must be allow")

for agent_id in ("teamlead", "analyst", "developer", "tester"):
    agent = by_id.get(agent_id)
    if not agent:
        continue
    for pattern in ("git rm *", "git branch -D *", "git stash clear *", "ri *"):
        if has(agent, "shell", pattern, "deny"):
            ok("runtime deny %s : %s" % (agent_id, pattern))
        else:
            bad("runtime deny missing %s : %s" % (agent_id, pattern))

for agent_id in ("analyst", "developer", "tester"):
    agent = by_id.get(agent_id)
    if not agent:
        continue
    if has(agent, "subagent", "*", "deny"):
        ok("runtime subagent deny: " + agent_id)
    else:
        bad("runtime subagent deny missing: " + agent_id)
    if has(agent, "question", "*", "deny"):
        ok("runtime question deny: " + agent_id)
    else:
        bad("runtime question deny missing: " + agent_id)

print("\nPASS: %d  FAIL: %d" % (passes, fails))
sys.exit(1 if fails else 0)
PY
    exit $?
fi

# Fallback without python3: check the resolved JSON by exact fragments.
passes=0
fails=0
pass() { passes=$((passes + 1)); printf 'PASS  %s\n' "$1"; }
fail() { fails=$((fails + 1)); printf 'FAIL  %s\n' "$1"; }

for expected in '"id": "teamlead"' '"id": "analyst"' '"id": "developer"' '"id": "tester"'; do
    if grep -Fq "$expected" "$tmp/agents.json"; then pass "agent loaded: $expected"; else fail "agent missing: $expected"; fi
done
for agent in teamlead analyst developer tester; do
    expected=$(sed -n 's/^steps:[[:space:]]*//p' "$ROOT/agents/$agent.md" | head -n 1)
    if [ -n "$expected" ] && grep -Fq "\"steps\": $expected" "$tmp/agents.json"; then
        pass "steps found for $agent: $expected"
    else
        fail "steps missing for $agent: ${expected:-not found in agents/$agent.md}"
    fi
done
for pattern in 'artifacts/requirements/**' 'artifacts/qa/**'; do
    if grep -A1 -F "\"resource\": \"$pattern\"" "$tmp/agents.json" | grep -Fq '"effect": "deny"'; then
        pass "teamlead deny: $pattern"
    else
        fail "teamlead deny missing: $pattern"
    fi
done
if grep -A1 -F '"resource": "artifacts/actions.md"' "$tmp/agents.json" | grep -Fq '"effect": "allow"'; then
    pass 'teamlead allow: artifacts/actions.md'
else
    fail 'teamlead allow missing: artifacts/actions.md'
fi
if grep -A1 -F '"resource": ".opencode/config.yml"' "$tmp/agents.json" | grep -Fq '"effect": "allow"'; then
    pass 'teamlead allow: .opencode/config.yml'
else
    fail 'teamlead allow missing: .opencode/config.yml'
fi
for pattern in 'git rm *' 'git branch -D *' 'git stash clear *' 'ri *'; do
    if grep -Fq "\"resource\": \"$pattern\"" "$tmp/agents.json"; then
        pass "deny found: $pattern"
    else
        fail "deny missing: $pattern"
    fi
done

printf '\nPASS: %s  FAIL: %s\n' "$passes" "$fails"
[ "$fails" -eq 0 ] || exit 1
