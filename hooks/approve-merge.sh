#!/usr/bin/env bash
#
# PreToolUse (Bash) hook for the /developer pipeline.
#
# Auto-approves the pipeline's one sanctioned unattended merge — and ONLY that —
# so it is never handed to the auto-mode permission classifier. In `auto` mode
# the classifier re-evaluates "the orchestrator is merging a PR that only got a
# subagent COMMENT, with no human approval" as an adversarial pattern and denies
# it, even when `Bash(gh pr merge:*)` is on the allow-list (a wildcard allow rule
# does not exempt it). A PreToolUse `allow` decision runs before that classifier,
# so it is the only deterministic way to let the sanctioned merge through.
#
# Every guard below must hold; otherwise the hook stays silent (exit 0 → defer to
# the normal permission flow), so it can never widen anything unexpectedly:
#   1. jq is available (the hook payload is JSON on stdin).
#   2. The command is EXACTLY `gh pr merge <PR> --(merge|squash|rebase)` — fully
#      anchored: no shell chaining, no --admin, no extra flags.
#   3. The call comes from the primary checkout, where the orchestrator runs.
#      developer-defaults.md is committed, so guard 4 is equally true inside
#      every worker's linked worktree — a worker that merged on its own would
#      be auto-approved by guards 1, 2 and 4 alone. Merging is the
#      orchestrator's alone, and only it runs where git-dir == git-common-dir.
#   4. The repo opted into unattended merges: docs/agents/developer-defaults.md
#      carries a `merge: auto` line. Interactive `--auto-merge` overrides on a
#      `merge: manual` repo are deliberately NOT covered — a prompt there is fine.

command -v jq >/dev/null 2>&1 || exit 0

payload="$(cat)"
cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null)" || exit 0

# 2. Strict, fully-anchored match — the exact form the orchestrator issues.
re='^gh pr merge [0-9]+ --(merge|squash|rebase)$'
[[ "$cmd" =~ $re ]] || exit 0

cwd="$(printf '%s' "$payload" | jq -r '.cwd // ""' 2>/dev/null)" || exit 0
[[ -n "$cwd" ]] || cwd="$PWD"

# 3. Only from the primary checkout. In a linked worktree these two paths
#    differ; outside a repo both are empty, which must not read as a match.
#    --path-format=absolute is required: without it git prints whichever form
#    is shortest from cwd, so a subdirectory of the primary checkout yields
#    "/abs/.git" and "../.git" — unequal, and the merge would never be approved.
gitdir="$(git -C "$cwd" rev-parse --path-format=absolute --git-dir 2>/dev/null)" || exit 0
commondir="$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || exit 0
[[ -n "$gitdir" && "$gitdir" == "$commondir" ]] || exit 0

# 4. Only where the user pre-authorized unattended merges. The defaults file is
#    repo-relative, so resolve it from the top level — cwd is wherever the
#    orchestrator happens to stand, which is often a subdirectory.
root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || exit 0
[[ -n "$root" ]] || exit 0
grep -qE '^merge:[[:space:]]*auto[[:space:]]*$' "$root/docs/agents/developer-defaults.md" 2>/dev/null || exit 0

jq -nc '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "allow",
    permissionDecisionReason: "Sanctioned /developer merge:auto merge (gh pr merge <PR>) — pre-authorized in docs/agents/developer-defaults.md, kept out of the auto-mode classifier by design."
  }
}'
