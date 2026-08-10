#!/usr/bin/env bash
#
# PreToolUse (Agent) hook for the /developer pipeline.
#
# Refuses a foreground spawn of a /developer worker. A foreground spawn holds
# the orchestrator's turn open for the worker's entire run, so anything that
# interrupts that turn — a Ctrl-C, a dropped connection — takes the worker down
# with it: its context, its worktree and its commits are gone, unrecoverably.
# The same interruption leaves a background worker running and reachable with
# SendMessage. SKILL.md says this ("Every spawn is run_in_background: true");
# this hook is what makes it real.
#
# Deliberately narrow, because unlike hooks/approve-merge.sh this one *denies*,
# and a misfire blocks real work:
#   1. jq is available (the hook payload is JSON on stdin).
#   2. The spawn targets one of the three /developer worker types. Any other
#      agent — Explore, general-purpose, another plugin's — passes untouched.
#   3. run_in_background is *explicitly* false. The harness default is already
#      background, so an omitted field is correct and must not be denied;
#      denying a call that would have behaved properly is the false positive
#      this hook must never produce. (If that default ever flips, the absent
#      case stops being covered here — the SKILL.md rule is what covers it.)
#
# The denial reason is half the point: it has to be actionable enough that the
# model re-issues the same spawn correctly in the same turn instead of giving
# up on the sub-issue.

command -v jq >/dev/null 2>&1 || exit 0

payload="$(cat)"

# 2. Only the pipeline's own workers. The type arrives namespaced when the
#    plugin is installed ("developer-skills:code-author") and bare when the
#    agents are loaded from a checkout, so match on the part after the colon.
type="$(printf '%s' "$payload" | jq -r '.tool_input.subagent_type // ""' 2>/dev/null)" || exit 0
case "${type##*:}" in
  code-author | diff-reviewer | dispatcher) ;;
  *) exit 0 ;;
esac

# 3. Only an explicit opt-out of the background default.
bg="$(printf '%s' "$payload" | jq -r '.tool_input.run_in_background' 2>/dev/null)" || exit 0
[[ "$bg" == "false" ]] || exit 0

jq -nc --arg t "$type" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: ("Foreground spawn of \($t) refused. A /developer worker spawned with run_in_background: false holds the orchestrator turn open for its whole run, so an interruption destroys the worker context, worktree and commits with no way to recover them. Re-issue this identical call with run_in_background: true, then wait for its result before spawning the next worker.")
  }
}'
