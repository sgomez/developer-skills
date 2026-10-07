#!/usr/bin/env bash
#
# PreToolUse (Bash) hook for the /developer pipeline.
#
# Auto-approves a fix or merge-fix worker's push of its commits onto the PR it
# was sent to fix — and ONLY that — so it is never handed to the auto-mode
# permission classifier. On lab-05 the classifier denied the spec PR's fixer
# `git push origin HEAD:agent/developer/spec-1` as "Modify Shared Resources"
# (the integration branch is the head of a PR into main), after letting the
# very same push through on lab-04: the spec escalated with its fix committed
# locally and never published. A PreToolUse `allow` runs before that
# classifier, so it is the only deterministic way to let the push through.
#
# Every guard below must hold; otherwise the hook stays silent (exit 0 → defer
# to the normal permission flow), so it can never widen anything unexpectedly:
#   1. jq is available (the hook payload is JSON on stdin).
#   2. The command is EXACTLY `git push origin HEAD:agent/developer/<spec|issue>-<N>`
#      — fully anchored: no force, no flags, no refspec but HEAD, no chaining.
#      Without a force flag the remote refuses anything but a fast-forward,
#      so the push can only add commits on top of the PR branch.
#   3. The call comes from a linked worktree — where workers run — never the
#      primary checkout.
#   4. That worktree is on a fix branch the workflow names:
#      `agent/developer/fix-pr-<PR>`, or a variant of it (`-r2`, `-merge`…).
#   5. PR <PR> exists and its head branch is the push's target: a worker sent
#      to fix PR 16 may push onto PR 16's branch, and onto nothing else.

command -v jq >/dev/null 2>&1 || exit 0

payload="$(cat)"
cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null)" || exit 0

# 2. Strict, fully-anchored match — the exact form the fix prompts issue.
re='^git push origin HEAD:(agent/developer/(spec|issue)-[0-9]+)$'
[[ "$cmd" =~ $re ]] || exit 0
target="${BASH_REMATCH[1]}"

cwd="$(printf '%s' "$payload" | jq -r '.cwd // ""' 2>/dev/null)" || exit 0
[[ -n "$cwd" ]] || cwd="$PWD"

# 3. Only from a linked worktree: there git-dir and git-common-dir differ.
#    Outside a repo both are empty, which must not read as a worktree.
gitdir="$(git -C "$cwd" rev-parse --path-format=absolute --git-dir 2>/dev/null)" || exit 0
commondir="$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || exit 0
[[ -n "$gitdir" && -n "$commondir" && "$gitdir" != "$commondir" ]] || exit 0

# 4. On a fix branch, which names the PR it fixes.
branch="$(git -C "$cwd" symbolic-ref --short -q HEAD 2>/dev/null)" || exit 0
bre='^agent/developer/fix-pr-([0-9]+)(-[a-z0-9]+)?$'
[[ "$branch" =~ $bre ]] || exit 0
pr="${BASH_REMATCH[1]}"

# 5. The push lands on that PR's own head branch.
head="$(cd "$cwd" && gh pr view "$pr" --json headRefName --jq .headRefName 2>/dev/null)" || exit 0
[[ "$head" == "$target" ]] || exit 0

jq -nc '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "allow",
    permissionDecisionReason: "Sanctioned /developer fix push: a fix worker publishing its commits onto the head of the PR it fixes, fast-forward only — kept out of the auto-mode classifier by design."
  }
}'
