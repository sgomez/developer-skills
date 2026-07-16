# Backlog

Ideas worth doing that are not scheduled. Each entry says what the problem is,
what blocks the obvious fix, and the direction that looked right when it was
parked. Delete an entry when it ships (the CHANGELOG becomes its record) or
when it stops being a good idea.

## Deterministic authorization for the cleanup step

**Problem.** The auto-mode classifier denies `cleanup-worktrees.sh`
intermittently. It justifies the denial by pointing back at the unattended
merge that preceded it ("no human or approving reviewer ever approved"), so
the denial has nothing to do with the cleanup itself and cannot be argued away
on the cleanup's merits.

An `autoMode.allow` entry does **not** help: a checked-in, shared
`.claude/settings.json` is a scope the classifier ignores — confirmed in the
field, with the entry present and the cleanup denied anyway.

**What blocks the obvious fix.** The orchestrator invokes the script as a
multi-line command with a variable:

```sh
SKILL_DIR="/…/plugins/cache/…/skills/developer"
bash "$SKILL_DIR/scripts/cleanup-worktrees.sh" --sweep
```

Permission rules and hooks match the command **text**, not its runtime values,
so the unexpanded `$SKILL_DIR` defeats both an allow rule (nothing to match a
literal path against) and a hook (a hook that approved
`bash <anything>/cleanup-worktrees.sh` would be approving a script at an
arbitrary path — the exact hole `approve-merge.sh` refuses to open).

**Direction.** Two halves, in order:

1. Have the orchestrator emit the cleanup as **one bare command with a literal
   absolute path** — no variable, no preceding assignment.
2. Extend the hook to resolve its own plugin root (`CLAUDE_PLUGIN_ROOT`),
   build the canonical
   `<plugin-root>/skills/developer/scripts/cleanup-worktrees.sh`, and approve
   only that exact literal path with a whitelist of flags (`--sweep`,
   `--branch`, `--sha`, `--keep-branches`). Refuse any path containing `$`.

**Priority: low.** It self-heals — a denied targeted cleanup is swept up by
the wrap-up's `--sweep`, and runs have been ending with zero leaked worktrees.
The cost today is a stray denial message.

## Guard the remaining worker checkouts

**Problem.** 0.15.0 folded the linked-worktree check into `review-pr`'s
checkout, because a reviewer whose cwd had drifted to the primary checkout
detached it with `git checkout --detach FETCH_HEAD`. The same shape exists in
the other workers' checkouts and is still an advisory the model can skip:

- `fix-pr` — `git fetch origin pull/<PR>/head:fix/pr-<PR> && git checkout fix/pr-<PR>`
- `implement-issue` — `git checkout -b <branch> origin/main`

A drifted cwd there would not detach the primary, but it would switch it to
another branch or create one on it — the same hijack of the user's working
state, with a different fingerprint.

**Direction.** Same treatment as `review-pr`: gate each destructive checkout
on `[ "$(git rev-parse --git-dir)" != "$(git rev-parse --git-common-dir)" ]`
**in the same command**, so a wrong cwd yields a `blocked` report instead of a
mutated primary.

## Independent review identity (bot / GitHub App)

**Problem.** The classifier's objection to the unattended merge is factually
correct: with a single identity, the same principal opens the PR, "reviews" it,
and merges it. The review is a COMMENT and never an approval because GitHub
forbids approving your own PR — so there is no independent review at all.

`approve-merge.sh` makes that policy execute without friction. It does not add
oversight, and it was never meant to: `merge: auto` already means "merge to
main unattended, with the diff-reviewer as the only gate".

**Direction.** A second GitHub identity — a bot account or GitHub App
installation token — opening the PR or posting the review would make the
approval real. That would satisfy branch protection with required reviews,
give the merge a genuine independent gate, and remove the adversarial pattern
at its root instead of routing around it.

**Cost.** Real infrastructure: App registration, a token in the environment,
and deciding which side of the exchange the bot sits on. Worth it only if the
independent approval is wanted for its own sake, not merely to satisfy the
classifier — the hook already handles that.
