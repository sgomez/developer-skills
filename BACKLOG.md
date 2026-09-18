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

**Field evidence (spec #308).** The `implement-issue` shape fired exactly as
predicted: the haiku build for #387 `cd`'d to the primary checkout and ran
`git checkout -b agent/issue-387-… origin/main` there, then installed,
tested and committed in it, leaving the user's checkout on a worker branch
for the rest of the run (the haiku fixer for its PR escaped too). The sweep
now WARNs on that fingerprint, but nothing yet prevents it.

**Direction.** Same treatment as `review-pr`: gate each destructive checkout
on `[ "$(git rev-parse --git-dir)" != "$(git rev-parse --git-common-dir)" ]`
**in the same command**, so a wrong cwd yields a `blocked` report instead of a
mutated primary. A stronger, model-independent variant: a PreToolUse Bash
hook in the `approve-merge.sh` mold (silent unless every guard holds) that
**denies** state-changing git (`checkout`/`switch`/`commit`/`branch`) whose
effective target is the primary checkout root while the payload's `cwd` lies
under `.claude/worktrees/` — the cwd is what distinguishes a worker from the
orchestrator, and a deny there turns the prose rule into a mechanism.

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

## Tier→model map in developer-defaults (report D8)

**Problem.** The `sonnet` / `opus` strings are hard-coded in four
places (the `## Complexity` rules in the issue-authoring templates, the
orchestrator's worker table, its Model tier step, the fix cycle's escalation
ladder). Retuning a repo's
tiers means editing skills that ship with the plugin, and a repo cannot say
"here, standard needs opus" at all.

**Direction.** Move the map into `docs/agents/developer-defaults.md` (and its
template in `skills/setup-developer-skills/`):

```
models:
  standard: sonnet
  complex:  opus
  reviewer: opus
```

The ticket then carries only its complexity (semantics) and the orchestrator
resolves the model against the map (mechanics), falling back to the factory
values when the file or a key is absent.

**What blocks it.** No repo has asked for a different map yet — it adds a
config knob for a need nobody has shown.

## Re-reviews with a declared focus (report C7)

**Problem.** On fix cycles 2 and 3 the diff-reviewer re-reads the whole change
from scratch. It already has a rule against inventing new nitpicks on untouched
code, but nothing tells it *where* the new work is, so it pays for the full
diff every cycle.

**Direction.** Have the orchestrator narrow the re-review prompt: the threads
that were outstanding, and `the commits since <sha>` — it knows the previous
review's head sha without reading any bodies, so this costs it nothing.

**What blocks it.** Nothing structural; it was cut from the 0.17.0 context
pass for scope. The care needed is in the wording: a reviewer told to look only
at new commits can miss a fix that broke something outside them, so the prompt
has to narrow attention without narrowing responsibility for the verdict.

## Cheaper worktree bootstrap (report D9)

**Problem.** Every build, fix and review worktree installs dependencies from
scratch; nothing tells workers which install command this project prefers.

**Direction.** Record the recommended bootstrap command in the code-host
templates (e.g. `pnpm install --prefer-offline --reporter=silent`) so workers
copy it rather than guessing.

**What blocks it.** Mostly that the payoff shrank: the review path stopped
installing at all when CI is green (0.17.0), and the quiet-install rules
already removed the log cost. What is left is wall-clock time on build and fix
worktrees — real, but no longer a context problem, so it needs a different
justification than the one it was parked with.

## Plan-then-build for the complex tier (report O3)

**Problem.** A `complex` sub-issue sends its builder straight into
implementation with only its ticket for orientation.
The expensive thinking (seams, ordering, which pattern to imitate) happens
inside the same context that then has to hold the whole implementation.

**Direction.** For `complexity=complex` only, have a plan step leave the plan
as a comment on the issue, and start the builder from it. Standard and trivial
tickets would only pay overhead.

**What blocks it.** It overlaps with the cut itself: `/to-tickets` already
answers "this ticket is too much for one pass" by splitting it, and a plan
step splits the *work* on a ticket instead. Deciding which applies where is
the design question, and no run has yet shown a `complex` ticket the cut
should not have split.

## Red CI is invisible in the `merge: manual` queue

**Problem.** The Merge step's checks gate (0.17.0) only guards the merge the
orchestrator performs, so it sits on the `merge: auto` branch. Under
`merge: manual` the step returns early — the sub-issue is recorded
ready-to-merge and handed to the human — and nothing looks at the checks after
that point.

The reviewer already treats red checks as NEEDS_FIXES, so the gap is narrow but
real: a build that goes red **after** a CLEAN verdict (a flaky job, a
dependency change, a sibling PR merged in between) reaches the human's merge
queue marked ready, with no signal. They find out by merging it.

**Direction.** Read the checks when the wrap-up builds the merge queue and flag
the red ones there. That is where the human actually reads the list, it costs
one call per queued change, and it leaves the meaning of `merge: manual`
untouched.

**What blocks it.** Nothing technical — it was cut from 0.17.0 for scope. The
alternative considered and rejected was moving the gate above the
manual/auto split: cleaner on paper, but it would make `manual` spend fix
cycles, which is precisely what that policy says it does not do. Anyone
picking this up should not quietly re-open that decision.

## Verify that a fix cycle actually pushed

**Problem.** The Build step now confirms the PR a `code-author` reports really
exists, because one reported a number that did not. The fix cycle has exactly
the same exposure and no check at all: a fixer can report its work pushed
without having pushed anything, and the checks gate that follows will watch the
*previous* head sha's checks go green and merge code the review said was wrong.
The run that produced the fabricated `pr=` had its next fix cycle told to verify
against the remote — by hand, in the prompt, because the skill does not ask.

**Field evidence (spec #994).** A fixer ended its turn twice without a
`RESULT`, its fixes unpushed, and the orchestrator improvised exactly the
check proposed below — `headRefOid` plus the unresolved-thread count — to
establish that nothing had landed. Ending a turn mid-work is now ruled out in
the worker definitions, but the verification is still improvised each time.

**Direction.** Read `gh pr view <PR> --json headRefOid` before spawning the
fixer, and confirm the sha moved once its `RESULT` lands. One cheap read either
side, the same shape as the PR-exists check, and it also closes the gate's
stale-sha hole.

**What blocks it.** Telling a missing push apart from a fix that legitimately
changed no files — the review's finding was wrong and the fixer answered in the
thread instead, which is behaviour the skill explicitly allows. That case leaves
the sha unmoved and would trip the check. No field run has produced one yet, so
there is nothing to calibrate the rule against.
