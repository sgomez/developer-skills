#!/usr/bin/env bash
# Regression tests for hooks/hc-agent-view.sh: the OSC 7501 statuses it reports
# for a worker's steps and result. No hc needed. Run directly:
#
#   bash tests/hc-agent-view.test.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VIEW="$ROOT/hooks/hc-agent-view.sh"
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed" >&2; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

T="" checks=0 fails=0
pass() { checks=$((checks + 1)); }
fail() { checks=$((checks + 1)); fails=$((fails + 1)); echo "FAIL [$T] $*" >&2; }

tool='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"npm test\n  --ci"}}]}}'

# view <result JSON or ""> [stdin] — sets $OUT: the statuses reported, one "state msg" per line
view() {
  printf '%s\n' '{"type":"started","agentId":"a1","label":"build #387"}' >"$TMP/journal.jsonl"
  [[ -n $1 ]] && jq -nc --argjson r "$1" '{type:"result", agentId:"a2", result:"other"}, {type:"result", agentId:"a1", result:$r}' >>"$TMP/journal.jsonl"
  printf '%s\n' "$tool" >"$TMP/agent.jsonl"
  printf %s "${2-}" | HC_AGENT_LINGER=0 bash "$VIEW" "build #387" "$TMP/agent.jsonl" "$TMP/journal.jsonl" a1 >"$TMP/out" 2>&1
  OUT="$(grep -ao $'\e]7501;[^\e]*' "$TMP/out" | while read -r o; do
    s=${o#*state=}
    echo "${s%%:*} $(printf %s "${o##*msg=}" | base64 -d)"
  done)"
}
expect() { [[ "$OUT" == "$1" ]] && pass || fail "expected $(printf %q "$1"), got $(printf %q "$OUT")"; }

T="build-pr-is-done-with-its-number"
view '{"status":"pr","pr":412,"url":"https://x/pull/412"}'
expect "working build #387
working Bash npm test --ci
done PR #412"

T="pushed-branch-without-pr-shows-url"
view '{"status":"pr","url":"https://x/pull/new/b"}'
expect "working build #387
working Bash npm test --ci
done https://x/pull/new/b"

T="review-verdict-with-fixes"
view '{"verdict":"CLEAN","fixes":2}'
expect "working build #387
working Bash npm test --ci
done CLEAN (2 fixes)"

T="blocked-is-an-error-with-its-reason"
view '{"verdict":"blocked","reason":"gh auth\nfailed"}'
expect "working build #387
working Bash npm test --ci
error gh auth failed"

T="stop-without-result-is-an-error"
view "" $'stop\n'
expect "working build #387
working Bash npm test --ci
error stopped without a result"

if ((fails)); then
  echo "FAILED: $fails of $checks checks" >&2
  exit 1
fi
echo "PASS: $checks checks"
