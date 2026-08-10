#!/usr/bin/env bash
# Regression tests for the two /developer PreToolUse guards:
#
#   hooks/require-background-workers.sh    — no foreground worker spawns
#   hooks/no-ci-logs-in-orchestrator.sh    — no raw CI logs in the main context
#
# Both are silent-by-default hooks: they print a JSON `deny` decision only when
# every guard holds, and exit 0 with no output otherwise. These tests pin both
# halves — above all the silences, since a hook that denies too much blocks
# real work. Self-contained: builds throwaway git fixtures under a temp dir.
# Run directly:
#
#   bash tests/developer-hooks.test.sh
#
# Exits 0 with a PASS summary, or 1 listing every failed assertion.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BG_HOOK="$ROOT/hooks/require-background-workers.sh"
CI_HOOK="$ROOT/hooks/no-ci-logs-in-orchestrator.sh"

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed" >&2; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

T="" checks=0 fails=0
pass() { checks=$((checks + 1)); }
fail() { checks=$((checks + 1)); fails=$((fails + 1)); echo "FAIL [$T] $*" >&2; }

assert_deny() {
  local d
  d="$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null)" || d=""
  [[ "$d" == "deny" ]] && pass || { fail "expected a deny decision"; echo "--- output was: ${OUT:-<empty>}"; }
}
assert_silent() {
  [[ -z "$OUT" ]] && pass || { fail "expected silence (defer)"; echo "--- output was: $OUT"; }
}
assert_rc0() { [[ "$RC" -eq 0 ]] && pass || fail "expected exit 0, got $RC"; }

# run <hook> <payload-json> — sets $OUT and $RC
run() {
  RC=0
  OUT="$(printf '%s' "$2" | bash "$1" 2>/dev/null)" || RC=$?
}

# spawn <subagent_type> [background-literal] — an Agent tool payload. Omit the
# second argument to leave run_in_background out entirely.
spawn() {
  if [[ $# -eq 2 ]]; then
    jq -nc --arg t "$1" --argjson b "$2" \
      '{tool_name:"Agent", tool_input:{subagent_type:$t, run_in_background:$b}}'
  else
    jq -nc --arg t "$1" '{tool_name:"Agent", tool_input:{subagent_type:$t}}'
  fi
}

# bash_call <command> <cwd> — a Bash tool payload.
bash_call() {
  jq -nc --arg c "$1" --arg d "$2" '{tool_name:"Bash", tool_input:{command:$c}, cwd:$d}'
}

# ---------------------------------------------------------------------------
# require-background-workers.sh
# ---------------------------------------------------------------------------

T="bg/foreground-code-author-denied"
run "$BG_HOOK" "$(spawn code-author false)"
assert_rc0; assert_deny

T="bg/foreground-namespaced-type-denied"
run "$BG_HOOK" "$(spawn developer-skills:diff-reviewer false)"
assert_rc0; assert_deny

T="bg/foreground-dispatcher-denied"
run "$BG_HOOK" "$(spawn dispatcher false)"
assert_deny

T="bg/background-spawn-allowed"
run "$BG_HOOK" "$(spawn code-author true)"
assert_rc0; assert_silent

# The harness default is already background, so an omitted flag is correct.
# Denying it would be a false positive on a call that behaves properly.
T="bg/omitted-flag-allowed"
run "$BG_HOOK" "$(spawn code-author)"
assert_silent

T="bg/other-agents-untouched"
run "$BG_HOOK" "$(spawn general-purpose false)"
assert_silent
run "$BG_HOOK" "$(spawn Explore false)"
assert_silent

T="bg/no-subagent-type-untouched"
run "$BG_HOOK" '{"tool_name":"Agent","tool_input":{"run_in_background":false}}'
assert_rc0; assert_silent

# ---------------------------------------------------------------------------
# no-ci-logs-in-orchestrator.sh
# ---------------------------------------------------------------------------

# Fixture: a repo with a linked worktree, standing in for a worker.
REPO="$TMP/repo"
git init -q "$REPO"
git -C "$REPO" config user.email test@example.com
git -C "$REPO" config user.name test
git -C "$REPO" commit -q --allow-empty -m init
git -C "$REPO" branch -q -M main
git -C "$REPO" worktree add -q "$TMP/worker" -b agent/issue-1 >/dev/null 2>&1
mkdir -p "$REPO/sub" "$REPO/.scratch"

LOG="$REPO/.scratch/developer-run-744.log"
: > "$LOG"

T="ci/log-read-from-primary-denied"
run "$CI_HOOK" "$(bash_call 'gh run view 123 --log-failed' "$REPO")"
assert_rc0; assert_deny

T="ci/piped-log-read-denied"
run "$CI_HOOK" "$(bash_call 'gh run view 123 --log-failed | grep -i error' "$REPO")"
assert_deny

T="ci/subdirectory-of-primary-denied"
run "$CI_HOOK" "$(bash_call 'gh run view 123 --log' "$REPO/sub")"
assert_deny

# A worker is exactly who should be reading these logs.
T="ci/worker-worktree-allowed"
run "$CI_HOOK" "$(bash_call 'gh run view 123 --log-failed' "$TMP/worker")"
assert_rc0; assert_silent

# The classification the Merge step prescribes carries no --log flag.
T="ci/json-classification-allowed"
run "$CI_HOOK" "$(bash_call 'gh run view 123 --json conclusion,jobs --jq .conclusion' "$REPO")"
assert_silent

T="ci/unrelated-command-allowed"
run "$CI_HOOK" "$(bash_call 'gh pr checks 123 --watch --fail-fast' "$REPO")"
assert_silent

T="ci/outside-a-repo-allowed"
run "$CI_HOOK" "$(bash_call 'gh run view 123 --log-failed' "$TMP")"
assert_rc0; assert_silent

# No run in flight → not this hook's business, even in the primary checkout.
T="ci/no-run-log-allowed"
rm -f "$LOG"
run "$CI_HOOK" "$(bash_call 'gh run view 123 --log-failed' "$REPO")"
assert_silent

T="ci/archived-log-does-not-arm-the-guard"
mkdir -p "$REPO/.scratch/archive"
: > "$REPO/.scratch/archive/developer-run-744-20260810T120000.log"
run "$CI_HOOK" "$(bash_call 'gh run view 123 --log-failed' "$REPO")"
assert_silent

# ---------------------------------------------------------------------------

if [[ "$fails" -gt 0 ]]; then
  echo "FAILED: $fails of $checks assertions" >&2
  exit 1
fi
echo "PASS: all $checks assertions"
