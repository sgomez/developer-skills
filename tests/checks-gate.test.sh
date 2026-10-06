#!/usr/bin/env bash
# Regression tests for skills/developer/scripts/checks-gate.sh.
#
# Self-contained: puts a fake `gh` on PATH that answers from per-scenario
# fixture files, so no network and no real PR. Each probe of the same kind
# reads the next numbered fixture (<kind>.1, <kind>.2, …) and repeats the last
# one once they run out — enough to script "pending, then green". Run directly:
#
#   bash tests/checks-gate.test.sh
#
# Exits 0 with a PASS summary, or 1 listing every failed assertion.
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/skills/developer/scripts/checks-gate.sh"

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed" >&2; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

T="" checks=0 fails=0
pass() { checks=$((checks + 1)); }
fail() { checks=$((checks + 1)); fails=$((fails + 1)); echo "FAIL [$T] $*" >&2; }
assert_out() { [[ "$OUT" == "$1" ]] && pass || fail "expected '$1', got '$OUT'"; }
assert_rc()  { [[ "$RC" -eq "$1" ]] && pass || fail "expected exit $1, got $RC"; }

# The fake gh. Kinds: state (mergeStateStatus), rollup (statusCheckRollup),
# runstatus (gh run view --json status), run (gh run view --json conclusion,jobs).
mkdir -p "$TMP/bin"
cat >"$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
args="$*"
case "$args" in
  *"--json mergeStateStatus"*) kind=state ;;
  *"--json statusCheckRollup"*) kind=rollup ;;
  "run view"*"--json status"*) kind=runstatus ;;
  "run view"*"--json conclusion,jobs"*) kind=run ;;
  *) echo "fake gh: unexpected: $args" >&2; exit 9 ;;
esac
echo "$args" >>"$FIX/calls"
# Run probes read <kind>-<run-id>.N when such fixtures exist, else <kind>.N.
if [[ "$kind" == run* ]]; then
  id="$3"; ls "$FIX/$kind-$id".* >/dev/null 2>&1 && kind="$kind-$id"
fi
[[ -f "$FIX/fail-$kind" ]] && exit 1
n=$(( $(cat "$FIX/n-$kind" 2>/dev/null || echo 0) + 1 ))
echo "$n" >"$FIX/n-$kind"
f="$FIX/$kind.$n"
[[ -f "$f" ]] || f="$(ls "$FIX/$kind".* 2>/dev/null | sort -t. -k2 -n | tail -1)"
jqexpr=""; prev=""
for a in "$@"; do [[ "$prev" == "--jq" ]] && jqexpr="$a"; prev="$a"; done
jq -r "$jqexpr" "$f"
EOF
chmod +x "$TMP/bin/gh"

# scenario <name> — fresh fixture dir; sets $FIX.
scenario() { T="$1"; FIX="$TMP/$1"; mkdir -p "$FIX"; }
state()  { echo "{\"mergeStateStatus\":\"$2\"}" >"$FIX/state.$1"; }
rollup() { echo "{\"statusCheckRollup\":$2}" >"$FIX/rollup.$1"; }
run_gate() {
  RC=0
  OUT="$(PATH="$TMP/bin:$PATH" FIX="$FIX" CHECKS_GATE_POLL=0 CHECKS_GATE_STATE_TRIES=3 \
    CHECKS_GATE_BEHIND_TRIES=3 CHECKS_GATE_REGISTER_TRIES=3 CHECKS_GATE_QUEUE_WAIT=5 \
    CHECKS_GATE_MAX_WAIT=5 bash "$SCRIPT" "${1:-42}" 2>/dev/null)" || RC=$?
}

ok='{"__typename":"CheckRun","name":"test","status":"COMPLETED","conclusion":"SUCCESS","detailsUrl":"https://github.com/o/r/actions/runs/7/job/1"}'
running='{"__typename":"CheckRun","name":"test","status":"IN_PROGRESS","conclusion":null,"detailsUrl":"https://github.com/o/r/actions/runs/7/job/1"}'
red='{"__typename":"CheckRun","name":"test","status":"COMPLETED","conclusion":"FAILURE","detailsUrl":"https://github.com/o/r/actions/runs/7/job/1"}'
skipped='{"__typename":"CheckRun","name":"lint","status":"COMPLETED","conclusion":"SKIPPED","detailsUrl":""}'
status_ok='{"__typename":"StatusContext","context":"ext","state":"SUCCESS","targetUrl":"https://ci.example/1"}'
status_red='{"__typename":"StatusContext","context":"ext","state":"FAILURE","targetUrl":"https://ci.example/9"}'

scenario usage
run_gate abc; assert_rc 2

scenario dirty
state 1 DIRTY
run_gate; assert_out "DIRTY"; assert_rc 0
grep -q statusCheckRollup "$FIX/calls" && fail "a DIRTY PR must not wait for checks" || pass

scenario behind
state 1 BEHIND
run_gate; assert_out "BEHIND"
[[ "$(cat "$FIX/n-state")" -ge 3 ]] && pass || fail "BEHIND should be re-probed before it is reported"

scenario behind-settles-after-update
state 1 BEHIND; state 2 CLEAN; rollup 1 "[$ok]"
run_gate; assert_out "GREEN"

scenario unknown-then-clean
state 1 UNKNOWN; state 2 CLEAN; rollup 1 "[$ok]"
run_gate; assert_out "GREEN"

scenario green-with-skipped-and-status
state 1 CLEAN; rollup 1 "[$ok,$skipped,$status_ok]"
run_gate; assert_out "GREEN"

scenario no-checks
state 1 CLEAN; rollup 1 "[]"
run_gate; assert_out "NO_CHECKS"

scenario registers-late
state 1 BLOCKED; rollup 1 "[]"; rollup 2 "[$running]"; rollup 3 "[$ok]"
run_gate; assert_out "GREEN"

scenario still-pending
state 1 CLEAN; rollup 1 "[$running]"
OUT=""; RC=0
OUT="$(PATH="$TMP/bin:$PATH" FIX="$FIX" CHECKS_GATE_POLL=1 CHECKS_GATE_STATE_TRIES=1 \
  CHECKS_GATE_REGISTER_TRIES=1 CHECKS_GATE_MAX_WAIT=1 bash "$SCRIPT" 42)" || RC=$?
assert_out "PENDING"

scenario red-code
state 1 UNSTABLE; rollup 1 "[$red,$ok]"
echo '{"status":"completed"}' >"$FIX/runstatus.1"
echo '{"conclusion":"failure","jobs":[{"name":"build","conclusion":"success","steps":[1],"url":"u0"},{"name":"test","conclusion":"failure","steps":[1,2,3],"url":"https://github.com/o/r/actions/runs/7/job/1"}]}' >"$FIX/run.1"
run_gate; assert_out "RED code run=7 url=https://github.com/o/r/actions/runs/7/job/1"

scenario red-waits-for-run
state 1 UNSTABLE; rollup 1 "[$red]"
echo '{"status":"in_progress"}' >"$FIX/runstatus.1"; echo '{"status":"completed"}' >"$FIX/runstatus.2"
echo '{"conclusion":"failure","jobs":[{"name":"test","conclusion":"failure","steps":[1],"url":"j"}]}' >"$FIX/run.1"
run_gate; assert_out "RED code run=7 url=j"
[[ "$(cat "$FIX/n-runstatus")" -ge 2 ]] && pass || fail "should poll the run until completed"

scenario red-infra-no-steps
state 1 UNSTABLE; rollup 1 "[$red]"
echo '{"status":"completed"}' >"$FIX/runstatus.1"
echo '{"conclusion":"failure","jobs":[{"name":"test","conclusion":"failure","steps":[],"url":"j"}]}' >"$FIX/run.1"
run_gate; assert_out "RED infra run=7 reason=no-steps-executed"

scenario red-infra-startup
state 1 UNSTABLE; rollup 1 "[$red]"
echo '{"status":"completed"}' >"$FIX/runstatus.1"
echo '{"conclusion":"startup_failure","jobs":[]}' >"$FIX/run.1"
run_gate; assert_out "RED infra run=7 reason=startup_failure"

scenario queued-never-picked-up
queued='{"__typename":"CheckRun","name":"test","status":"QUEUED","conclusion":null,"detailsUrl":"https://github.com/o/r/actions/runs/7/job/1"}'
state 1 CLEAN; rollup 1 "[$ok,$queued]"
OUT=""; RC=0
OUT="$(PATH="$TMP/bin:$PATH" FIX="$FIX" CHECKS_GATE_POLL=1 CHECKS_GATE_STATE_TRIES=1 \
  CHECKS_GATE_REGISTER_TRIES=1 CHECKS_GATE_QUEUE_WAIT=1 CHECKS_GATE_MAX_WAIT=60 bash "$SCRIPT" 42 2>/dev/null)" || RC=$?
assert_out "RED infra reason=never-picked-up"

scenario queued-while-another-runs
state 1 CLEAN; rollup 1 "[$running,$queued]"; rollup 2 "[$ok,$ok]"
run_gate; assert_out "GREEN"

scenario red-but-rerun-went-green
state 1 UNSTABLE; rollup 1 "[$red]"; rollup 2 "[$ok]"
echo '{"status":"completed"}' >"$FIX/runstatus.1"
echo '{"conclusion":"success","jobs":[{"name":"test","conclusion":"success","steps":[1],"url":"j"}]}' >"$FIX/run.1"
run_gate; assert_out "GREEN"

scenario code-red-wins-over-infra
red8='{"__typename":"CheckRun","name":"e2e","status":"COMPLETED","conclusion":"FAILURE","detailsUrl":"https://github.com/o/r/actions/runs/8/job/2"}'
state 1 UNSTABLE; rollup 1 "[$red,$red8]"
echo '{"status":"completed"}' >"$FIX/runstatus.1"
echo '{"conclusion":"startup_failure","jobs":[]}' >"$FIX/run-7.1"
echo '{"conclusion":"failure","jobs":[{"name":"e2e","conclusion":"failure","steps":[1],"url":"j8"}]}' >"$FIX/run-8.1"
run_gate; assert_out "RED code run=8 url=j8"

scenario red-external-status
state 1 UNSTABLE; rollup 1 "[$status_red,$ok]"
run_gate; assert_out "RED code url=https://ci.example/9"

scenario gh-fails
state 1 CLEAN; touch "$FIX/fail-state"
run_gate; assert_rc 1
case "$OUT" in ERROR*) pass ;; *) fail "expected an ERROR line, got '$OUT'" ;; esac

if [[ "$fails" -eq 0 ]]; then
  echo "PASS: $checks checks"
else
  echo "$fails of $checks checks failed" >&2
  exit 1
fi
