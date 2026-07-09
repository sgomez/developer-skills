---
name: developer
description: Orchestrates unattended spec delivery — loops over a spec's child issues in dependency order, dispatching dispatcher (complexity triage), code-author (implement), and diff-reviewer (review) workers per sub-issue, with a review→fix cycle until CLEAN, then merging per the repo's merge policy. Tracker- and host-agnostic — issues and changes live wherever docs/agents/issue-tracker.md and docs/agents/code-host.md say (GitHub via gh is the factory default). Factory defaults are parallel execution and manual merge; repo defaults live in docs/agents/developer-defaults.md and per-run flags (--parallel/--sequential, --auto-merge/--no-auto-merge) override them. Use when user says "/developer", "deliver this spec" (or "deliver this PRD"), "deliver this sub-issue", or wants the build→review→fix pipeline.
---

# Developer (orchestrator)

Drives the triage → build → review → fix → merge pipeline across isolated
subagent workers, looping over every sub-issue of a spec unattended. Each
worker gets a **clean context** — the only thing it knows is the arguments you
pass in its prompt. You (the orchestrator) hold the state between steps.

## Invoke

```
/developer <issue>              # spec with sub-issues → deliver them all
                                # plain issue → deliver just that one
/developer <spec> <subissue>    # deliver a single specific sub-issue

Flags (override the repo defaults — see Run configuration):
  --parallel | --sequential     # spec mode: waves vs one-at-a-time
  --auto-merge | --no-auto-merge  # merge CLEAN PRs vs leave them ready
```

If no issue number is given, ask for it and stop. Do not guess issue numbers.
The execution flags only change spec mode; in single mode they are a no-op.
Accept the bare words `parallel` / `sequential` as synonyms for the flags.

> **Namespacing.** Installed as a Claude Code plugin, skills and agents carry
> the plugin prefix: the skills appear as `developer-skills:<name>` and the
> subagents as `developer-skills:dispatcher` / `developer-skills:code-author` /
> `developer-skills:diff-reviewer`. Use the names exactly as they appear in
> your available-skills and available-agents lists; the short names below
> refer to whichever form is installed.

## Contract docs (tracker + code host)

The pipeline is agnostic about where issues and changes live. Two committed
docs define the mechanics for this repo, and every worker reads them in its
own context:

- **`docs/agents/issue-tracker.md`** — issue operations (read an issue,
  enumerate children of a parent, check a blocker, comment, label, close)
  in its `## Delivery operations` section.
- **`docs/agents/code-host.md`** — change operations (publish, check out in
  a worktree, review, mark ready, reply, merge, auto-close semantics).

Read both once at the start (they are short — an allowed exception to
"never read bodies yourself"). **Every command block below shows the GitHub
factory default (`gh`); when a contract doc defines a different mechanic
for the same operation, the doc wins.** If a doc is missing, the GitHub
defaults apply as-is — suggest `/setup-developer-skills` if that looks
wrong.

Note two capability flags from `docs/agents/code-host.md`:

- **Unattended merge supported?** A local code host never merges
  unattended — if the resolved config says `merge: auto` there, override to
  `manual` and say so in the run-config line.
- **Issue auto-close on merge?** If not (e.g. issues on a tracker the code
  host can't close), the orchestrator closes the delivered issue itself
  per the tracker ops right after verifying the merge.

With a **local** tracker or code host, two extra standing adjustments:
Step 0 also publishes `.scratch/` (the tracker/change files live there),
and tracker writes (comments, `Status:` changes) are yours to make in the
primary checkout, scoped to `.scratch/` paths, committed as
`chore(tracker): …` — an extension of Step 0's exception. A local code
host also moves Cleanup earlier: run it (with `--keep-branches`) after
**every** worker reports, so the change branch is free for the next worker.

## Run configuration

Two knobs govern a run. Resolve each one **before mode detection**, in this
precedence order: CLI flag > repo default > factory default.

| Knob        | Values                    | Factory default |
|-------------|---------------------------|-----------------|
| `execution` | `parallel` / `sequential` | `parallel`      |
| `merge`     | `auto` / `manual`         | `manual`        |

Repo defaults live in `docs/agents/developer-defaults.md`, written by
`/setup-developer-skills`. Read it once at the start (it is short — this is
an allowed exception to "never read bodies yourself"); if it is missing or a
knob is absent, fall back to the factory default. State the resolved
configuration in one line before starting, e.g.
`Run config: execution=parallel, merge=manual (repo defaults)`.

What `merge` means:

- **`auto`** — a CLEAN verdict triggers the code host's merge operation
  (Merge step; `gh pr merge` on GitHub). The
  committed `merge: auto` line in `docs/agents/developer-defaults.md` is the
  user's standing authorization for these merges.
- **`manual`** — the pipeline stops at CLEAN: the PR is already marked ready
  by the reviewer, so record the sub-issue as **ready-to-merge** and leave
  the merge to the human. Because sub-issues only close on merge
  (`Closes #N`), anything `Blocked by` a ready-to-merge sub-issue stays
  blocked for the rest of the run — expected, not an error; it lands in the
  wrap-up as the human's queue.

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
  cycles, wave (parallel mode), outcome (merged / ready-to-merge / escalated /
  blocked). Also keep the dispatcher's `touches`/`hints` just long enough to
  forward `hints` into that sub-issue's Build step — discard both once the
  build is spawned, they have no use after that.

## Step 0 — Publish context docs before anything else

Workers branch from `origin/main`, so any domain-context file that is not
committed **and pushed** is invisible to them. Grilling/spec sessions edit
these files but do not commit them. Before dispatching any worker (add
`.scratch` to the paths when the tracker or code host is local):

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

(No remote — local code host — means no push: the commit alone publishes,
since linked worktrees share the repo.)

If the push is rejected, stop and report — do not rebase or force anything.
This is the flow's start, before going unattended; the user is still there to
resolve it.

## Mode detection

Enumerate the children of the given issue per the tracker's Delivery
operations. GitHub default — native sub-issues (infer OWNER/REPO from
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

(Throughout this skill, `#<N>` stands for the issue ref in the tracker's
own format — a number on GitHub/GitLab, a file path on a local tracker —
and `#<PR>` for the change ref in the code host's format.)

- **Open sub-issues exist → spec mode**: loop over all of them (below).
- **No sub-issues → single mode**: run the delivery pipeline once on the given
  issue, with the issue itself as spec (no separate parent spec).
- **Two arguments given**: run the delivery pipeline once on `<subissue>` with
  `<spec>` as the spec. Skip the loop.

## Progress board (spec mode — not optional)

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
   - **ready-to-merge** (`merge: manual`, verdict CLEAN) → back to
     `status: pending` and rename the subject to
     `#<N> <title> — ready to merge: PR #<PR>`. Not completed — the human
     still has to merge it.
   - **escalated** → back to `status: pending` and rename the subject to
     `#<N> <title> — escalated: <one-line reason>`. Never mark an escalated
     sub-issue completed — unchecked items at the end are the human's queue.
4. Sub-issues that never became deliverable (blocked by an escalated one, or
   by a ready-to-merge one the human hasn't merged yet) stay pending; rename
   them `#<N> <title> — blocked by #<M>` at wrap-up.

Single mode (no sub-issues) skips the board.

## Spec loop

Repeat while open sub-issues remain:

1. **Pick the next unblocked sub-issue**: for each open sub-issue (lowest
   number first), check its blockers without reading full bodies — the
   "check a blocker's state" operation from the tracker doc. Blockers may
   be wired as the tracker's **native dependency links**, as a
   `Blocked by` body section, or both (`/to-tickets` prefers native edges
   where the tracker has them) — check both. GitHub default:

   ```bash
   # native dependencies: count of OPEN blockers (0 or absent = clear)
   gh api repos/{owner}/{repo}/issues/<N> --jq '.issue_dependencies_summary.blocked_by // 0'
   # body fallback: every listed blocker must be CLOSED
   gh issue view <N> --json body --jq '.body' | grep -A3 -i "blocked by"
   gh issue view <BLOCKER> --json state --jq '.state'
   ```

   Take the first open sub-issue whose blockers are all closed. Skip
   sub-issues you already escalated this run (and, naturally, anything they
   block stays blocked). With `merge: manual`, sub-issues you already
   delivered as ready-to-merge count as done for *your* loop but their
   dependents stay blocked — skip both.

2. Run the **delivery pipeline** on it.

3. On **merged** or **ready-to-merge** → next iteration. On
   **escalated/blocked** → record it, next iteration.

4. When no deliverable sub-issue remains (all closed or ready-to-merge, or
   the rest are blocked by escalated/unmerged ones) → **wrap-up**.

## Parallel mode (`execution: parallel`)

Parallel is the factory default (see Run configuration). The trade-off:
sequential with `merge: auto` delivers one sub-issue fully before the next
starts, so each PR branches from a `main` that already contains the previous
one — no merge conflicts by construction. Parallel trades that guarantee for
throughput: independent sub-issues are built concurrently, and conflicts
between their PRs become expected work, resolved by extra merge-fix jobs.
Note that with `merge: manual` sibling PRs all branch from the same `main`
regardless of execution mode — sequential buys no conflict guarantee there,
so parallel costs nothing extra.

Work in **waves**:

1. **Wave = every open sub-issue whose blockers are all closed** (same check
   as step 1 of the spec loop), minus sub-issues already escalated this run.
2. Run the delivery pipeline on each wave member concurrently: spawn all
   `dispatcher`s in one batch, then the `code-author` BUILD jobs in parallel
   (each in its own worktree, `run_in_background: true`). As each build
   reports its PR, spawn its `diff-reviewer`; fix cycles run per PR exactly
   as in the sequential pipeline. Cap concurrent build/review/fix workers at
   **3**; queue the rest of the wave.
3. **Merges stay strictly serial** — never merge two PRs concurrently. With
   `merge: auto`, merge each PR as it reaches CLEAN. Every PR in the wave
   branched from the same `main`, so any PR merged after the first may
   conflict: on merge failure, run the merge-fix job from the Merge step,
   then retry once. With `merge: manual` there is nothing to serialize —
   each CLEAN PR just becomes ready-to-merge.
4. When every wave member is delivered (merged, ready-to-merge, or
   escalated), recompute the unblocked set → next wave. None left →
   **wrap-up**.

Everything else — context economy, escalation, wrap-up, rules — is unchanged.

## Delivery pipeline (per sub-issue)

**Local code host — branch discipline (structural, not optional).** On a
local host every worker checks out the change branch itself, and git allows
a branch in only **one** worktree — but a worker's worktree outlives it
whenever it holds changes, which a build or fix worktree always does. So run
**Cleanup** (step 6, always `--keep-branches`) after **every** worker
reports and before spawning the next one: build → cleanup → review →
cleanup → fix → cleanup → re-review. Skipping one makes the next worker
report blocked on "branch already used by worktree". (Remote hosts are
immune: reviewers fetch the PR head from the remote instead.)

### 1. Triage

Spawn `dispatcher`:

> Triage issue #`<subissue>`. Score its implementation complexity per your
> rubric. End with the
> `RESULT complexity=… model=… touches=… hints=… reason=…` line.

Parse `model=<tier>`. On any malformed result, default to `opus`. Parse
`touches=` and `hints=` too, defaulting each to `none` if the line predates
this field or omits it — never block the pipeline on a missing hint.

### 2. Build

Spawn `code-author` with `model: <tier>` and `isolation: "worktree"`:

> BUILD job. Spec issue #`<spec>`, sub-issue #`<subissue>`.
> Read the spec for context, then run the implement-issue skill on the
> sub-issue. Triage found: `<dispatcher's hints, verbatim, or omit this line
> entirely when hints=none>`.
> End with the `RESULT pr=… url=…` line.

- `RESULT blocked …` → **escalate** (see below) and move to the next
  sub-issue.
- `RESULT pr=<PR> url=<URL>` → keep `<PR>`, continue.

### 3. Review

Spawn `diff-reviewer` with `isolation: "worktree"`:

> Review PR #`<PR>` by running the review-pr skill on it — its step 1 plus
> the repo's `docs/agents/code-host.md` give the exact checkout procedure
> for your worktree; follow them, not memory. Posting the review (inline
> comments + summary) on the PR and marking it ready are part of your
> delegated task — you are authorized to perform these code-host writes.
> End with the `RESULT verdict=…` line.

- `verdict=CLEAN` → go to **Merge**.
- `verdict=NEEDS_FIXES` → enter the fix cycle.
- `RESULT blocked` because the change branch is held by another worktree
  (the worker quotes git's "already used by worktree" error) → a previous
  worker's worktree wasn't cleaned: run **Cleanup** (step 6) and re-spawn
  the reviewer, **once per sub-issue** — if it blocks again, escalate.
- Any other `RESULT blocked` or malformed result → **escalate**, next
  sub-issue.

### 4. Fix cycle (max 3)

For cycle `c` = 1, 2, 3:

1. Fixer model: cycle 1 uses the build tier, each later cycle escalates one
   tier (haiku → sonnet → opus; opus stays opus).
2. Spawn `code-author` with that model and `isolation: "worktree"`:

   > FIX job. PR #`<PR>`. Run the fix-pr skill to address all review
   > threads — its step 1 plus the repo's `docs/agents/code-host.md` give
   > the exact checkout procedure for your worktree; follow them, not
   > memory. Pushing the fixes and replying to the review threads are part
   > of your delegated task. End with the `RESULT pr=… url=…` line.

   `RESULT blocked …` → **escalate**, next sub-issue (a branch-held-by-
   worktree blocked gets the same one-shot Cleanup + re-spawn as in step 3).
3. Re-review: spawn `diff-reviewer` again (same prompt as step 3, mention it
   is a re-review after a fix pass).
   - `CLEAN` → **Merge**.
   - `NEEDS_FIXES` and `c < 3` → next cycle.
   - `NEEDS_FIXES` and `c = 3` → **escalate** (do NOT merge), next sub-issue.

### 5. Merge

**With `merge: manual`** (the factory default) there is nothing to merge:
the reviewer already marked the PR ready, so record the sub-issue as
**ready-to-merge**, update its board task (`— ready to merge: PR #<PR>`),
run **Cleanup** (step 6), and move on. The sub-issue stays open until the
human merges, so its dependents remain blocked this run.

Say **how** to merge the moment a sub-issue becomes ready-to-merge — a bare
"ready to merge" leaves the user asking what to do, especially off GitHub.
State the code-host doc's merge operation concretely; local default:

```bash
git merge --no-ff <branch>
git branch -d <branch>
# then close the issue per the tracker ops (no auto-close on a local host)
```

**With `merge: auto`**: this merge is pre-authorized — the user opted into
`merge: auto` in `docs/agents/developer-defaults.md` (or passed
`--auto-merge` this run), which is standing authorization to merge PRs whose
review verdict is CLEAN. If the permission system still asks, say exactly
that; if it *denies*, follow the denial rule under Rules (escalate, never
retry).

Never touch local git state — your checkout may be in use by the user. Merge
remotely, per the code-host doc's merge operation. GitHub default:

```bash
gh pr merge <PR> --merge
```

Do **not** pass `--delete-branch`: it also tries to delete the *local* branch,
which is always still checked out in the build worker's worktree, so it fails
noisily every time. The remote branch is deleted in Cleanup (step 6), after
the worktrees are gone.

Then make sure the sub-issue is closed. If the code host auto-closes linked
issues (see `docs/agents/code-host.md`), just verify — GitHub default:

```bash
gh issue view <subissue> --json state --jq '.state'   # expect CLOSED
```

If there is **no auto-close** (issues on a different tracker than the code
host, or a local tracker), close the sub-issue yourself per the tracker
ops, with a comment naming the merged change.

If the merge fails (conflict with a previous merge), treat it as one extra fix
cycle — the **merge-fix job**: spawn a `code-author` with model `opus` and
`isolation: "worktree"`:

> MERGE-FIX job. PR #`<PR>` cannot be merged into main (conflict with a
> previously merged PR). In your worktree get the PR branch per the
> fix-that-pushes checkout in `docs/agents/code-host.md` (GitHub default:
> `git fetch origin pull/<PR>/head:fix/pr-<PR> && git checkout fix/pr-<PR>`
> — do not use `gh pr checkout` or check out the branch by name, it is
> checked out in the build worker's worktree and git will refuse). Merge
> `origin/main` into it, resolve the conflicts — using the
> `resolving-merge-conflicts` skill if it appears in your available skills —
> run the project checks, and push with
> `git push origin HEAD:<pr-branch>`. End with the `RESULT pr=… url=…` line.

Then merge again. If it still fails, **escalate**. In parallel mode this job
is routine, not exceptional: budget one merge-fix per conflicting PR before
escalating.

The merge-fix job also serves **`merge: manual`**: when the human's own
merge hits a conflict (mid-run or after wrap-up) and they bring it to you,
never resolve it in the main context — that fills the context this pipeline
exists to protect. Have them abort the half-merge (`git merge --abort`),
dispatch this same job on the conflicting PR (on a local host the worker
merges local `main` into the branch in its worktree — committing is
publishing, nothing to push), run Cleanup when it reports, and tell them to
retry the merge, which is now conflict-free.

### 6. Cleanup

The harness only auto-removes a worker's worktree when it is **unchanged** —
build and fix workers always leave a branch, commits, and `node_modules`
behind, so without this step every sub-issue leaks worktrees until the disk
fills. Run it whenever a sub-issue finishes — **merged, ready-to-merge, or
escalated** — everything is pushed by then, so nothing local is worth
keeping.

All removal mechanics live in the bundled script
`scripts/cleanup-worktrees.sh` (next to this SKILL.md — under the plugin
root when installed as a plugin). **Never improvise `git worktree remove`,
`git branch -D`, or any other repair yourself** — the script is the only
sanctioned way to touch local git state here. It removes only the linked
worktrees and local branches matching what you pass, refuses by construction
to touch the primary checkout, and if it finds the primary in detached HEAD
it prints a `WARN` line and leaves it alone (that is the fingerprint of a
worker having escaped its worktree — carry the WARN into your wrap-up
summary, do not "fix" the checkout).

```bash
BRANCH=$(gh pr view <PR> --json headRefName --jq .headRefName)   # skip if no PR
HEAD_SHA=$(gh pr view <PR> --json headRefOid --jq .headRefOid)
bash <skill-dir>/scripts/cleanup-worktrees.sh \
  --branch "$BRANCH" --branch "fix/pr-<PR>" \
  --branch "agent/issue-<subissue>-*" --sha "$HEAD_SHA"
```

(The two `gh pr view` lines are the GitHub default for the change-metadata
operation — on another host get branch and head sha per
`docs/agents/code-host.md`; on a local host the change ref *is* the branch
and `git rev-parse <branch>` gives the sha. With a local code host always
add `--keep-branches`: the local branch is the only copy of unmerged work,
so only the worktrees go.)

(A blocked build that never opened a PR has no `$BRANCH`/`$HEAD_SHA` — drop
those flags; the `agent/issue-<subissue>-*` pattern still catches its
worktree.)

If the sub-issue was **merged**, also delete the remote branch now (the merge
deliberately skipped `--delete-branch`; skip this on a local host — there is
no remote branch):

```bash
git push origin --delete $BRANCH
```

Matching strictly on this sub-issue's branches/sha is what makes this safe in
parallel mode — other wave members' worktrees never match. On an escalated or
ready-to-merge sub-issue the remote branch and open PR are untouched; only
local state goes.

## Escalation

When a sub-issue is blocked, non-convergent after 3 fix cycles, or
unmergeable, apply the `ready-for-human` triage label to the sub-issue and
comment on both the sub-issue and the spec, per the tracker ops. GitHub
default:

```bash
gh issue edit <subissue> --add-label "ready-for-human"
gh issue comment <subissue> --body "Escalated by /developer: <reason>. PR: <url or none>."
gh issue comment <spec> --body "Sub-issue #<subissue> escalated: <one-line reason>."
```

Leave the PR open (never merge an unclean PR). Run the **Cleanup** step
(step 6) — the local worktrees go, the remote branch and PR stay — then
continue the loop with the next unblocked sub-issue.

## Wrap-up

1. **Reconcile the task board**: every task must be completed or renamed per
   the Progress board rules — nothing left silently in_progress.
2. **Harvest discoveries and record the run** — turn what the workers learned
   into docs, and persist this run's outcome so the dispatcher can calibrate
   to this repo. Skip only when the run produced no PRs. The harvest worker
   does both in one branch/commit; pass it the per-sub-issue facts you already
   hold (the same rows as the chat-summary table) as the **ledger rows**, one
   per delivered sub-issue:

   `<today> spec=#<spec> sub=#<N> model=<tier> pr=#<PR> verdict=<CLEAN|—> cycles=<n> wave=<w|—> outcome=<merged|ready-to-merge|escalated>`

   (`verdict=—`/`wave=—` where it doesn't apply — e.g. an escalated sub-issue
   with no CLEAN, or sequential mode.)
   Spawn one `code-author` with `model: sonnet` and `isolation: "worktree"`:

   > HARVEST job. This run delivered PRs #`<list every PR of the run —
   > merged, ready-to-merge, or escalated>`. Create branch
   > `agent/harvest-<spec>` from origin/main, then do two things on it:
   >
   > **(a) Record the run in the ledger.** Append these rows verbatim to the
   > `## Run log` section of `docs/agents/delivery-ledger.md`, creating the
   > file if it does not exist (with a one-line title, an empty
   > `## Local calibration` section, and a `## Run log` section):
   >
   > ```
   > <the ledger rows, one per delivered sub-issue>
   > ```
   >
   > Then read the **recent** `## Run log` — the last ~50 rows are plenty
   > (older rows already left their mark in the calibration; the log is a
   > rolling window of evidence, not an archive) — and update
   > `## Local calibration`: add or refine a short bullet **only** when the log
   > shows a class of issue was consistently mis-tiered — e.g. issues touching
   > a given area scored `standard` but needed 2+ fix cycles or escalated at
   > that tier. Each bullet names the signal and the corrected tier (the
   > dispatcher reads them on top of its generic rubric). Change nothing there
   > if no pattern is evident yet; never invent a rule from a single row.
   >
   > **(b) Harvest discoveries.** For each PR read its body and comments per the
   > repo's `docs/agents/code-host.md` (GitHub default:
   > `gh pr view <PR> --json body,comments`) and collect the `## Discoveries`
   > entries. Compare them against the repo's agent docs (`AGENTS.md` and
   > everything under `docs/agents/`). Promote only entries that repeat across
   > PRs, correct a doc the code has outgrown, or would clearly have saved
   > another worker real work; drop one-off trivia. Fold the survivors into the
   > right doc (update the existing recipe/pattern doc; create a new
   > `docs/agents/` doc only if none fits). If nothing qualifies, leave the
   > docs untouched — the ledger append from (a) still stands.
   >
   > Commit as `docs(agents): record spec #<spec> run and harvest discoveries`
   > and push with `git push origin HEAD:main` — never check out main. If the
   > push is rejected, fetch and rebase once, then push again; if it still
   > fails, stop and report it. End with the
   > `RESULT docs=<updated|none> ledger=<appended|failed>` line.

   With a **local code host** there is no remote to push through and `main`
   may never be moved unattended: instruct the harvest worker to leave its
   commit on the `agent/harvest-<spec>` branch instead, and list that branch
   in the wrap-up as one more item in the human's merge queue.

   This job is best-effort: if it reports blocked, note it in the summary
   and move on.
3. **Final sweep** — one last pass of the cleanup script, catching the
   harvest worktree and anything a half-failed pipeline left behind:

   ```bash
   bash <skill-dir>/scripts/cleanup-worktrees.sh --sweep
   ```

   (With a local code host: `--sweep --keep-branches` — unmerged local
   branches are the only copy of the work.)

   If it prints a `WARN` line (primary checkout in detached HEAD), include
   it verbatim in the chat summary — never repair the primary checkout
   yourself.

   If the permission system **denies the sweep** (its pattern-matched
   removal can trip the auto-mode classifier), do not retry it: check
   `git worktree list`, and if leftovers remain run targeted
   `--branch`/`--sha` passes for the sub-issues this run delivered —
   the same shape already used in step 6. Nothing left → just note the
   denial and move on.
4. **Push notification** (PushNotification tool):
   `Spec #<spec>: <N> merged, <M> escalated, <K> still blocked.` — with
   `merge: manual`, use
   `Spec #<spec>: <N> ready to merge, <M> escalated, <K> still blocked.`
5. **Chat summary** — one table: sub-issue, model used, PR, fix cycles, wave
   (parallel mode), outcome. List escalated sub-issues with reasons so the
   user can pick them up. With `merge: manual`, list the ready-to-merge PRs
   **in dependency order** — that is the human's merge queue, and merging in
   that order minimizes conflicts — and give the **exact commands** per the
   code-host doc's merge operation (local default: `git merge --no-ff
   <branch> && git branch -d <branch>`, then close each issue per the
   tracker ops). Sibling PRs branched from the same `main` may conflict on
   merge — say so, and point at the escape hatch: abort the half-merge and
   ask you to run the **merge-fix job** on that PR (a worker resolves it in
   its own worktree; never in the main context). Note whether the harvest
   updated docs.
6. **Execution report** — how the run actually unfolded. In parallel
   mode, one line per wave listing the jobs that ran concurrently and their
   outcomes, e.g. `Wave 2: #12 ∥ #14 ∥ #15 — 2 merged, 1 escalated, 1
   merge-fix on #14`. In sequential mode, the delivery order with any
   merge-fix jobs noted.

## Rules

- Resolve the run configuration (execution + merge) once, before mode
  detection, and stick to it for the whole run — flags > repo defaults >
  factory defaults (parallel, manual).
- In sequential mode, one sub-issue is fully delivered (merged,
  ready-to-merge, or escalated) before the next starts. In parallel mode,
  builds/reviews/fixes may overlap, but merges are always one at a time.
- Never run the merge operation (`gh pr merge`, `glab mr merge`, …) when
  the resolved config says `merge: manual` — ready + CLEAN is the terminal
  state there, even if merging seems convenient.
- Unattended: never stop to ask the user anything mid-loop. Escalate via
  labels/comments and keep going.
- Each worker is stateless: pass everything it needs in its prompt; never
  assume it can see prior steps.
- Never run `git checkout`, `git pull`, or any state-changing git command in
  the main context — the only exceptions are Step 0's scoped commit+push of
  context docs, the `cleanup-worktrees.sh` script (steps 6 and wrap-up),
  the merged-branch `git push origin --delete`, and — local tracker only —
  the scoped `.scratch/` tracker-write commits from Contract docs. If the
  script warns that the primary checkout is detached, report it — never
  repair it.
- Only spawn the fix worker when the review said `NEEDS_FIXES`.
- Never resolve merge conflicts in the main context — not even when the
  user hands you one interactively. That is always the merge-fix job's
  work, in its own worktree.
- If a worker reports that a permission was denied (posting the review,
  marking the PR ready, merging, …), never re-run the denied command yourself —
  that is tunneling around the denial and will also be blocked. Treat the
  sub-issue as blocked: **escalate** it and continue the loop.
