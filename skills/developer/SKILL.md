---
name: developer
description: Orchestrates unattended PRD delivery — loops over a PRD's native sub-issues in dependency order, dispatching dispatcher (complexity triage), code-author (implement), and diff-reviewer (review) workers per sub-issue, with a review→fix cycle until CLEAN and auto-merge to main. Sequential by default; --parallel builds independent sub-issues concurrently in waves. Use when user says "/developer", "deliver this PRD", "deliver this sub-issue", or wants the build→review→fix pipeline.
---

# Developer (orchestrator)

Drives the triage → build → review → fix → merge pipeline across isolated
subagent workers, looping over every sub-issue of a PRD unattended. Each
worker gets a **clean context** — the only thing it knows is the arguments you
pass in its prompt. You (the orchestrator) hold the state between steps.

## Invoke

```
/developer <issue>              # PRD with sub-issues → deliver them all, in order
                                # plain issue → deliver just that one
/developer <prd> <subissue>     # deliver a single specific sub-issue
/developer <issue> --parallel   # PRD mode: build independent sub-issues
                                # concurrently, in waves (see Parallel mode)
```

If no issue number is given, ask for it and stop. Do not guess issue numbers.
`--parallel` only changes PRD mode; in single mode it is a no-op.

> **Namespacing.** Installed as a Claude Code plugin, skills and agents carry
> the plugin prefix: the skills appear as `developer-skills:<name>` and the
> subagents as `developer-skills:dispatcher` / `developer-skills:code-author` /
> `developer-skills:diff-reviewer`. Use the names exactly as they appear in
> your available-skills and available-agents lists; the short names below
> refer to whichever form is installed.

## Workers (subagents)

| Step    | Subagent        | Model                    | Isolation  | Skill it runs     |
|---------|-----------------|--------------------------|------------|-------------------|
| triage  | `dispatcher`     | sonnet (pinned)          | —          | (reads the issue) |
| build   | `code-author`   | chosen by triage         | `worktree` | `implement-issue` |
| review  | `diff-reviewer` | opus (pinned)            | `worktree` | `review-pr`       |
| fix     | `code-author`   | escalates per cycle      | `worktree` | `fix-pr`          |
| harvest | `code-author`   | sonnet (pinned)          | `worktree` | (reads PR bodies) |

Spawn each via the **Agent** tool with the matching `subagent_type`. Pass
`isolation: "worktree"` to every code-author and diff-reviewer spawn. Pass
`model` explicitly to code-author spawns (triage decides the tier). Never run
the skills yourself in the main context — the point is isolation.

## Context economy

The loop may cover many sub-issues; your context must survive all of them.

- **Never read issue or PR bodies yourself.** Workers read them in their own
  disposable contexts. You only run the cheap listing commands below.
- From each worker, keep only its final `RESULT` line.
- Track per sub-issue: number, task id, chosen model, PR number, verdict, fix
  cycles, wave (parallel mode), outcome (merged / escalated / blocked).

## Step 0 — Publish context docs before anything else

Workers branch from `origin/main`, so any domain-context file that is not
committed **and pushed** is invisible to them. Grilling/PRD sessions edit
these files but do not commit them. Before dispatching any worker:

```bash
git status --porcelain -- CONTEXT-MAP.md '**/CONTEXT.md' docs/adr docs/agents AGENTS.md CLAUDE.md
```

If anything shows up, stage **only those paths** (never the user's unrelated
work-in-progress), commit on the current branch (must be `main` — if not,
stop and tell the user), and push:

```bash
git add CONTEXT-MAP.md '**/CONTEXT.md' docs/adr docs/agents AGENTS.md CLAUDE.md
git commit -m "docs(domain): publish context map and ADR updates"
git push origin main
```

If the push is rejected, stop and report — do not rebase or force anything.
This is the flow's start, before going unattended; the user is still there to
resolve it.

## Mode detection

Query native GitHub sub-issues of the given issue (infer OWNER/REPO from
`git remote -v`):

```bash
gh api graphql -f query='
{
  repository(owner:"OWNER", name:"REPO") {
    issue(number: N) {
      subIssues(first: 50) { nodes { number title state } }
    }
  }
}' --jq '.data.repository.issue.subIssues.nodes'
```

- **Open sub-issues exist → PRD mode**: loop over all of them (below).
- **No sub-issues → single mode**: run the delivery pipeline once on the given
  issue, with the issue itself as spec (no separate PRD number).
- **Two arguments given**: run the delivery pipeline once on `<subissue>` with
  `<prd>` as the PRD. Skip the loop.

## Progress board (PRD mode — not optional)

The user follows the run through the harness task list. Keep it faithful at
every transition; a stale board defeats its purpose.

1. **Immediately after mode detection**, create one task per open sub-issue
   with **TaskCreate**, in sub-issue order: subject `#<N> <title>`,
   activeForm `Delivering #<N>`. The whole plan must be on the board before
   the first worker spawns.
2. When the delivery pipeline starts on a sub-issue → **TaskUpdate**
   `status: in_progress`. In parallel mode every wave member goes
   in_progress as its build spawns, so the board shows exactly what is
   running concurrently.
3. Terminal transitions, the moment they happen:
   - **merged** (sub-issue verified CLOSED) → `status: completed`.
   - **escalated** → back to `status: pending` and rename the subject to
     `#<N> <title> — escalated: <one-line reason>`. Never mark an escalated
     sub-issue completed — unchecked items at the end are the human's queue.
4. Sub-issues that never became deliverable (blocked by an escalated one)
   stay pending; rename them `#<N> <title> — blocked by #<M>` at wrap-up.

Single mode (no sub-issues) skips the board.

## PRD loop

Repeat while open sub-issues remain:

1. **Pick the next unblocked sub-issue**: for each open sub-issue (lowest
   number first), check its blockers without reading full bodies:

   ```bash
   gh issue view <N> --json body --jq '.body' | grep -A3 -i "blocked by"
   gh issue view <BLOCKER> --json state --jq '.state'   # must be CLOSED
   ```

   Take the first open sub-issue whose blockers are all closed. Skip
   sub-issues you already escalated this run (and, naturally, anything they
   block stays blocked).

2. Run the **delivery pipeline** on it.

3. On **merged** → next iteration. On **escalated/blocked** → record it,
   next iteration.

4. When no deliverable sub-issue remains (all closed, or the rest are blocked
   by escalated ones) → **wrap-up**.

## Parallel mode (`--parallel`)

Sequential is the default because each PR branches from a `main` that already
contains the previous one — no merge conflicts by construction. `--parallel`
trades that guarantee for throughput: independent sub-issues are built
concurrently, and conflicts between their PRs become expected work, resolved
by extra merge-fix jobs. Only offer/use it when the user asked for it.

Work in **waves**:

1. **Wave = every open sub-issue whose blockers are all closed** (same check
   as step 1 of the PRD loop), minus sub-issues already escalated this run.
2. Run the delivery pipeline on each wave member concurrently: spawn all
   `dispatcher`s in one batch, then the `code-author` BUILD jobs in parallel
   (each in its own worktree, `run_in_background: true`). As each build
   reports its PR, spawn its `diff-reviewer`; fix cycles run per PR exactly
   as in the sequential pipeline. Cap concurrent build/review/fix workers at
   **3**; queue the rest of the wave.
3. **Merges stay strictly serial** — never merge two PRs concurrently. Merge
   each PR as it reaches CLEAN. Every PR in the wave branched from the same
   `main`, so any PR merged after the first may conflict: on merge failure,
   run the merge-fix job from the Merge step, then retry once.
4. When every wave member is delivered (merged or escalated), recompute the
   unblocked set → next wave. None left → **wrap-up**.

Everything else — context economy, escalation, wrap-up, rules — is unchanged.

## Delivery pipeline (per sub-issue)

### 1. Triage

Spawn `dispatcher`:

> Triage issue #`<subissue>`. Score its implementation complexity per your
> rubric. End with the `RESULT complexity=… model=… reason=…` line.

Parse `model=<tier>`. On any malformed result, default to `opus`.

### 2. Build

Spawn `code-author` with `model: <tier>` and `isolation: "worktree"`:

> BUILD job. PRD issue #`<prd>`, sub-issue #`<subissue>`.
> Read the PRD for context, then run the implement-issue skill on the
> sub-issue. You are in an isolated worktree — branch from origin/main.
> End with the `RESULT pr=… url=…` line.

- `RESULT blocked …` → **escalate** (see below) and move to the next
  sub-issue.
- `RESULT pr=<PR> url=<URL>` → keep `<PR>`, continue.

### 3. Review

Spawn `diff-reviewer` with `isolation: "worktree"`:

> Review PR #`<PR>`. In your worktree get the PR head with
> `git fetch origin pull/<PR>/head && git checkout --detach FETCH_HEAD`
> (do not use `gh pr checkout` — the PR branch is checked out in the build
> worker's worktree and git will refuse). Run the review-pr skill on it.
> Posting the review (inline comments + summary) on the PR and marking it
> ready with `gh pr ready` are part of your delegated task — you are
> authorized to perform these GitHub writes. End with the
> `RESULT verdict=…` line.

- `verdict=CLEAN` → go to **Merge**.
- `verdict=NEEDS_FIXES` → enter the fix cycle.

### 4. Fix cycle (max 3)

For cycle `c` = 1, 2, 3:

1. Fixer model: cycle 1 uses the build tier, each later cycle escalates one
   tier (haiku → sonnet → opus; opus stays opus).
2. Spawn `code-author` with that model and `isolation: "worktree"`:

   > FIX job. PR #`<PR>`. Check it out with `gh pr checkout` in your worktree;
   > if that fails with "already used by worktree", run
   > `git fetch origin pull/<PR>/head:fix/pr-<PR> && git checkout fix/pr-<PR>`
   > and push with `git push origin HEAD:<pr-branch>`. Run the fix-pr skill
   > to address all review threads. Pushing the fixes and replying to the
   > review threads are part of your delegated task.
   > End with the `RESULT pr=… url=…` line.

   `RESULT blocked …` → **escalate**, next sub-issue.
3. Re-review: spawn `diff-reviewer` again (same prompt as step 3, mention it
   is a re-review after a fix pass).
   - `CLEAN` → **Merge**.
   - `NEEDS_FIXES` and `c < 3` → next cycle.
   - `NEEDS_FIXES` and `c = 3` → **escalate** (do NOT merge), next sub-issue.

### 5. Merge

Never touch local git state — your checkout may be in use by the user. Merge
remotely:

```bash
gh pr merge <PR> --merge
```

Do **not** pass `--delete-branch`: it also tries to delete the *local* branch,
which is always still checked out in the build worker's worktree, so it fails
noisily every time. The remote branch is deleted in Cleanup (step 6), after
the worktrees are gone.

`Closes #<subissue>` in the PR body closes the sub-issue on merge — verify:

```bash
gh issue view <subissue> --json state --jq '.state'   # expect CLOSED
```

If the merge fails (conflict with a previous merge), treat it as one extra fix
cycle — the **merge-fix job**: spawn a `code-author` with model `opus` and
`isolation: "worktree"`:

> MERGE-FIX job. PR #`<PR>` cannot be merged into main (conflict with a
> previously merged PR). In your worktree get the PR branch with
> `git fetch origin pull/<PR>/head:fix/pr-<PR> && git checkout fix/pr-<PR>`
> (do not use `gh pr checkout` or check out the branch by name — it is
> checked out in the build worker's worktree and git will refuse). Merge
> `origin/main` into it, resolve the conflicts — using the
> `resolving-merge-conflicts` skill if it appears in your available skills —
> run the project checks, and push with
> `git push origin HEAD:<pr-branch>`. End with the `RESULT pr=… url=…` line.

Then merge again. If it still fails, **escalate**. In parallel mode this job
is routine, not exceptional: budget one merge-fix per conflicting PR before
escalating.

### 6. Cleanup

The harness only auto-removes a worker's worktree when it is **unchanged** —
build and fix workers always leave a branch, commits, and `node_modules`
behind, so without this step every sub-issue leaks worktrees until the disk
fills. Run it whenever a sub-issue finishes, **merged or escalated** —
everything is pushed by then, so nothing local is worth keeping.

Identify what belongs to this sub-issue, then find its worktrees:

```bash
BRANCH=$(gh pr view <PR> --json headRefName --jq .headRefName)   # skip if no PR
HEAD_SHA=$(gh pr view <PR> --json headRefOid --jq .headRefOid)
git worktree list --porcelain
```

Remove every **linked** worktree (never the primary checkout) that is on
`$BRANCH`, `fix/pr-<PR>`, or `agent/issue-<subissue>-*` (a blocked build that
never opened a PR), or detached at `$HEAD_SHA` (the diff-reviewer's case).
Then drop the leftover local branches:

```bash
git worktree remove --force <path>            # once per matching worktree
git branch -D <branch>                        # each matching local branch
git worktree prune
```

If the sub-issue was **merged**, also delete the remote branch now (the merge
deliberately skipped `--delete-branch`):

```bash
git push origin --delete $BRANCH
```

Matching strictly on this sub-issue's branches/sha is what makes this safe in
`--parallel` mode — other wave members' worktrees never match. On an escalated
sub-issue the remote branch and open PR are untouched; only local state goes.

## Escalation

When a sub-issue is blocked, non-convergent after 3 fix cycles, or unmergeable:

```bash
gh issue edit <subissue> --add-label "ready-for-human"
gh issue comment <subissue> --body "Escalated by /developer: <reason>. PR: <url or none>."
gh issue comment <prd> --body "Sub-issue #<subissue> escalated: <one-line reason>."
```

Leave the PR open (never merge an unclean PR). Run the **Cleanup** step
(step 6) — the local worktrees go, the remote branch and PR stay — then
continue the loop with the next unblocked sub-issue.

## Wrap-up

1. **Reconcile the task board**: every task must be completed or renamed per
   the Progress board rules — nothing left silently in_progress.
2. **Harvest discoveries** — turn what the workers learned into docs before
   the knowledge is lost. Skip only when the run produced no PRs. Spawn one
   `code-author` with `model: sonnet` and `isolation: "worktree"`:

   > HARVEST job. This run delivered PRs #`<list every PR of the run,
   > merged or escalated>`. For each, read its body and comments
   > (`gh pr view <PR> --json body,comments`) and collect the `## Discoveries`
   > entries. Compare them against the repo's agent docs (`AGENTS.md` and
   > everything under `docs/agents/`). Promote only entries that repeat
   > across PRs, correct a doc the code has outgrown, or would clearly have
   > saved another worker real work; drop one-off trivia. If nothing
   > qualifies, change nothing. Otherwise branch from origin/main, fold the
   > entries into the right doc (update the existing recipe/pattern doc;
   > create a new `docs/agents/` doc only if none fits), commit as
   > `docs(agents): harvest discoveries from PRD #<prd> run`, and push with
   > `git push origin HEAD:main` — never check out main. If the push is
   > rejected, fetch and rebase once, then push again; if it still fails,
   > stop and report it. End with the `RESULT docs=<updated|none>` line.

   Then run the **Cleanup** worktree removal for its worktree if it pushed
   changes. This job is best-effort: if it reports blocked, note it in the
   summary and move on.
3. **Push notification** (PushNotification tool):
   `PRD #<prd>: <N> merged, <M> escalated, <K> still blocked.`
4. **Chat summary** — one table: sub-issue, model used, PR, fix cycles, wave
   (parallel mode), outcome. List escalated sub-issues with reasons so the
   user can pick them up. Note whether the harvest updated docs.
5. **Execution report** — how the run actually unfolded. In `--parallel`
   mode, one line per wave listing the jobs that ran concurrently and their
   outcomes, e.g. `Wave 2: #12 ∥ #14 ∥ #15 — 2 merged, 1 escalated, 1
   merge-fix on #14`. In sequential mode, the delivery order with any
   merge-fix jobs noted.

## Rules

- Strict sequential by default: one sub-issue fully delivered (merged or
  escalated) before the next starts — each PR must branch from a main that
  already contains the previous one. With `--parallel`, builds/reviews/fixes
  may overlap, but merges are always one at a time.
- Unattended: never stop to ask the user anything mid-loop. Escalate via
  labels/comments and keep going.
- Each worker is stateless: pass everything it needs in its prompt; never
  assume it can see prior steps.
- Never run `git checkout`, `git pull`, or any state-changing git command in
  the main context — the only exceptions are Step 0's scoped commit+push of
  context docs and the per-sub-issue worktree Cleanup (step 6), which only
  ever removes linked worker worktrees and their local branches, never the
  primary checkout.
- Only spawn the fix worker when the review said `NEEDS_FIXES`.
- If a worker reports that a permission was denied (posting the review,
  `gh pr ready`, merging, …), never re-run the denied command yourself —
  that is tunneling around the denial and will also be blocked. Treat the
  sub-issue as blocked: **escalate** it and continue the loop.
