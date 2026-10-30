#!/usr/bin/env bash
# Regression tests for hooks/hc-agent-terminals.sh, the herdr-core worker
# terminals hook. A fake hc on PATH logs every call. Run directly:
#
#   bash tests/hc-agent-terminals.test.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ROOT/hooks/hc-agent-terminals.sh"
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed" >&2; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

T="" checks=0 fails=0
pass() { checks=$((checks + 1)); }
fail() { checks=$((checks + 1)); fails=$((fails + 1)); echo "FAIL [$T] $*" >&2; }

# Workflow journal: a1 "build #387", a3 "review #412", a4 no label, a5 "cleanup #387".
W="$TMP/s/subagents/workflows/wf_1"
mkdir -p "$W" "$TMP/bin"
printf '%s\n' '{"type":"launched"}' \
  '{"type":"started","agentId":"a1","label":"build #387","phase":"Spec"}' \
  '{"type":"started","agentId":"a3","label":"review #412","phase":"Spec"}' \
  '{"type":"started","agentId":"a4"}' \
  '{"type":"started","agentId":"a5","label":"cleanup #387"}' \
  >"$W/journal.jsonl"

# Fake hc: logs its argv; `run --name taken…` fails like a name already in use;
# `ls` lists t9 as a1's terminal.
cat >"$TMP/bin/hc" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"$HC_LOG"
[[ $1 == run && $* == *"--name taken "* ]] && exit 1
[[ $1 == ls ]] && echo '{"terminals":[{"address":"t9","labels":{"claude.agent":"a1"}},{"address":"t8","labels":{}}]}'
exit 0
EOF
chmod +x "$TMP/bin/hc"

# fire <event> <agent_type> <agent_id> — sets $OUT (the hc calls, one per line)
fire() {
  : >"$TMP/log"
  local rc=0
  jq -nc --arg e "$1" --arg t "$2" --arg i "$3" --arg p "$TMP/s.jsonl" \
    '{hook_event_name:$e, agent_type:$t, agent_id:$i, transcript_path:$p}' >"$TMP/payload"
  HC_TERMINAL_ID=${TERM_ID-t7} HC_LOG="$TMP/log" PATH="$TMP/bin:$PATH" \
    bash "$HOOK" <"$TMP/payload" >"$TMP/stdout" 2>&1 || rc=$?
  OUT="$(cat "$TMP/log")"
  [[ $rc -eq 0 && ! -s $TMP/stdout ]] && pass || fail "expected exit 0 and no output, got $rc: $(cat "$TMP/stdout")"
}
expect() { [[ "$OUT" == "$1" ]] && pass || fail "expected $(printf %q "$1"), got $(printf %q "$OUT")"; }
run_call() { echo "run --bg --no-notify --rm --name $1 --label claude.agent=$2 $ROOT/hooks/hc-agent-view.sh $3 $W/agent-$2.jsonl $W/journal.jsonl $2"; }

T="start/builder-gets-a-named-terminal"
fire SubagentStart developer-skills:code-author a1
expect "$(run_call build-387 a1 'build #387')"

T="start/reviewer-bare-type-gets-a-terminal"
fire SubagentStart diff-reviewer a3
expect "$(run_call review-412 a3 'review #412')"

T="start/no-label-named-agent"
fire SubagentStart developer-skills:code-author a4
expect "$(run_call agent a4 agent)"

T="start/name-in-use-falls-back-to-id-suffix"
printf '%s\n' '{"type":"started","agentId":"a6","label":"Taken"}' >>"$W/journal.jsonl"
fire SubagentStart developer-skills:code-author a6
expect "$(run_call taken a6 Taken)
$(run_call taken-a6 a6 Taken)"

T="stop/tells-the-agents-terminal-only"
fire SubagentStop developer-skills:code-author a1
expect "ls --json
send t9 stop"

T="mechanical-agent-ignored"
fire SubagentStart workflow-subagent a5
expect ""

T="agent-outside-any-workflow-ignored"
fire SubagentStart developer-skills:code-author a2
expect ""

T="unsafe-agent-id-ignored"
fire SubagentStart developer-skills:code-author 'a:1'
expect ""

T="outside-herdr-core-silent"
TERM_ID="" fire SubagentStart developer-skills:code-author a1
expect ""

if ((fails)); then
  echo "FAILED: $fails of $checks checks" >&2
  exit 1
fi
echo "PASS: $checks checks"
