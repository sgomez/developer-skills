#!/usr/bin/env bash
#
# PreToolUse (Bash) hook for the /developer pipeline.
#
# Keeps raw CI job output out of the orchestrator's context. `gh run view
# --log-failed` and friends dump whole job logs into the one context the whole
# design protects — in a field run, six such calls diagnosing a single flaky
# suite are what compacted it. The Merge step's `gh run view --json
# conclusion,jobs` classification is the entire diagnosis the orchestrator is
# meant to make; past that the answer is the one allowed retry, then a fixer,
# which reads the logs in its own disposable context and already receives the
# failing job's URL. SKILL.md says this; this hook is what makes it real.
#
# Every guard must hold, otherwise the hook stays silent (exit 0 → defer to the
# normal permission flow):
#   1. jq is available (the hook payload is JSON on stdin).
#   2. The command reads a run's logs. Matched as substrings, not anchored, on
#      purpose: `gh run view 123 --log-failed | grep -i error` is precisely the
#      shape to catch, and anchoring would miss every pipe.
#   3. The call comes from the primary checkout. Session hooks fire inside
#      subagents too (see hooks/approve-merge.sh, guard 3), and a worker is
#      exactly who *should* be reading these logs — in a linked worktree
#      git-dir and git-common-dir differ, so workers fall through untouched.
#   4. A /developer run is actually in flight, evidenced by its run log. This
#      hook has no business in an ordinary session where a human is debugging
#      their own CI from the primary checkout.
#
# Limitation of guard 4: the wrap-up archives the run log, so between that
# archive and the next spawn row there is a window where the hook stays silent.
# The run is effectively over there, and a stale log at worst leaves the guard
# armed for one session too long — both preferable to blocking a human.

command -v jq >/dev/null 2>&1 || exit 0

payload="$(cat)"
cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null)" || exit 0

# 2. Log reads only. The --json classification the Merge step prescribes has no
#    --log flag and is never matched here.
[[ "$cmd" == *"gh run view"* && "$cmd" == *"--log"* ]] || exit 0

cwd="$(printf '%s' "$payload" | jq -r '.cwd // ""' 2>/dev/null)" || exit 0
[[ -n "$cwd" ]] || cwd="$PWD"

root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || exit 0
[[ -n "$root" ]] || exit 0

# 3. Primary checkout only. --path-format=absolute is required: without it git
#    prints whichever form is shortest from cwd, so a subdirectory of the
#    primary checkout yields "/abs/.git" and "../.git" — unequal, and the hook
#    would never fire. Outside a repo both are empty, which must not match.
gitdir="$(git -C "$cwd" rev-parse --path-format=absolute --git-dir 2>/dev/null)" || exit 0
commondir="$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || exit 0
[[ -n "$gitdir" && "$gitdir" == "$commondir" ]] || exit 0

# 4. Only while a run is in flight.
shopt -s nullglob
logs=("$root"/.scratch/developer-run-*.log)
(( ${#logs[@]} )) || exit 0

jq -nc '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: "Raw CI logs must not enter the orchestrator context during a /developer run. Classify the red with the Merge step gh run view --json conclusion,jobs query instead. If that is not enough to decide, take the one allowed rerun, and if it comes back red hand the failing job URL to a fixer — it reads the logs in its own context, which is what keeps this one small."
  }
}'
