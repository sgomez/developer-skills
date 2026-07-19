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

Note one capability flag from `docs/agents/code-host.md`: **issue auto-close
on merge?** If not (e.g. issues on a tracker the code host can't close), the
orchestrator closes the delivered issue itself per the tracker ops right
after verifying the merge.

**If either doc says the tracker or the code host is `local` (files in the
repo, no remote), read `LOCAL-HOST.md` now, before anything else.** It holds
every standing adjustment a local host or tracker needs — capability
overrides, tracker writes, branch discipline, cleanup and wrap-up. A run on a
remote host never loads it.

Two more files are read **on demand**, never at the start: `MERGE-FIX.md` at
the first merge conflict, and `WRAP-UP.md` when the loop ends.

(All three live **next to this SKILL.md**, in the skill's own directory —
under the plugin root when installed as a plugin, the same place
`scripts/cleanup-worktrees.sh` comes from. They are part of this skill: a
step that says to read one is not optional, it is that step's other half.)

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
- **`manual`** — the pipeline stops at CLEAN: you already marked the PR
  ready after the review, so record the sub-issue as **ready-to-merge**
  and leave
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
- A worker's whole final message **is** its `RESULT` line — the agents require
  it and every spawn prompt below restates it. A worker that reports prose
  before its line is spending your context, not its own; nothing it says there
  survives the run, so anything worth keeping belongs on the PR or the issue.
- Track per sub-issue: number, task id, chosen model, PR number, verdict, fix
  cycles, wave (parallel mode), outcome (merged / ready-to-merge / escalated /
  blocked) — and write the row to the run log the moment the sub-issue goes
  terminal (delivery pipeline step 7), so the wrap-up reads facts instead of
  recalling them. Also keep the dispatcher's `touches`/`hints` just long enough
  to forward `hints` into that sub-issue's Build step — discard both once the
  build is spawned, they have no use after that.

## Step 0 — Publish context docs before anything else

Workers branch from `origin/main`, so any domain-context file that is not
committed **and pushed** is invisible to them. Grilling/spec sessions edit
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

Enumerate the children of the given issue per the tracker's Delivery
operations. GitHub default — native sub-issues (infer OWNER/REPO from
`git remote -v`):

```bash
gh api graphql -f query='
{
  repository(owner:"OWNER", name:"REPO") {
    issue(number: N) {
      subIssues(first: 50) {
        pageInfo { hasNextPage }
        nodes { number title state labels(first: 10) { nodes { name } } }
      }
    }
  }
}' --jq '.data.repository.issue.subIssues'
```

If `hasNextPage` is `true`, **stop and report**: a spec with more than 50
sub-issues is not sized for this pipeline — tell the user to split it and end
the run. Never proceed on the first page alone: delivering 50 of 60 while
reporting the spec complete is a silent failure, the one outcome worse than
stopping.

Keep each sub-issue's labels from this query — the pick reads them (spec loop
step 1). Where a tracker's enumeration carries no labels, get them per its
read-labels operation instead.

(Throughout this skill, `#<N>` stands for the issue ref in the tracker's
own format — a number on GitHub/GitLab, a file path on a local tracker —
and `#<PR>` for the change ref in the code host's format.)

- **Open sub-issues exist → spec mode**: loop over all of them (below).
- **No sub-issues → single mode**: run the delivery pipeline once on the given
  issue, with the issue itself as spec (no separate parent spec).
- **Two arguments given**: run the delivery pipeline once on `<subissue>` with
  `<spec>` as the spec. Skip the loop. If the sub-issue ends **merged**
  (verified CLOSED), read `WRAP-UP.md` and run its **Close the spec** step
  (step 4) afterwards — it may have been the spec's last open sub-issue. That
  one step is all this mode needs from the wrap-up.

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
   # body fallback: every blocker listed in the section must be CLOSED
   gh issue view <N> --json body --jq '.body' \
     | awk '/^##[#]* *[Bb]locked by/{f=1;next} /^#/{f=0} f'
   gh issue view <BLOCKER> --json state --jq '.state'
   ```

   Extract the `Blocked by` **section**, never a fixed window around the
   heading: a `grep -A<n>` reads the wrong number of lines by construction —
   it drops the fifth blocker of a list of six and swallows the first lines
   of whatever section follows a list of two.

   Take the first open sub-issue whose blockers are all closed, and:

   - **Skip any sub-issue carrying the `ready-for-human` triage label** (the
     repo's own string for that role if `docs/agents/triage-labels.md` maps it
     differently) — from the labels the enumeration returned, plus the ones
     you applied yourself while escalating this run. That label is the
     escalation gate: someone already gave up on this sub-issue, and picking it
     up again buys three more fix cycles against the same wall. The gate is
     symmetric and it is the whole mechanism: **removing the label re-queues
     the sub-issue**, there is no other state to reset.
   - Whatever a gated sub-issue blocks stays blocked, as with any open one.
   - With `merge: manual`, sub-issues you already delivered as ready-to-merge
     count as done for *your* loop but their dependents stay blocked — skip
     both.

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
   as step 1 of the spec loop), minus the ones that step's gate excludes —
   `ready-for-human` above all, whether this run applied it or an earlier one
   did.
2. Run the delivery pipeline on each wave member concurrently, entry points
   first: the pipeline's **step 0** resolves where each member starts, and only
   the ones with no open change get a `dispatcher` and a build. Spawn those
   `dispatcher`s in one batch, then their `code-author` BUILD jobs in parallel
   (each in its own worktree, `run_in_background: true`) — **minus any member
   its dispatcher scored `oversized`**, which is escalated instead of built
   and simply leaves the wave. A resumed member goes
   straight into the review or fix stage alongside them. As each build
   reports its PR, spawn its `diff-reviewer`; as each reviewer reports,
   mark that PR ready (step 3 of the pipeline); fix cycles run per PR
   exactly as in the sequential pipeline. Cap concurrent build/review/fix
   workers at **3**; queue the rest of the wave.
3. **Merges stay strictly serial** — never merge two PRs concurrently. With
   `merge: auto`, merge each PR as it reaches CLEAN. Every PR in the wave
   branched from the same `main`, so any PR merged after the first may
   conflict: on merge failure **after** the Merge step's checks gate passed,
   run the merge-fix job (`MERGE-FIX.md`) and retry once. With `merge: manual`
   there is nothing to serialize — each CLEAN PR just becomes ready-to-merge.
4. When every wave member is delivered (merged, ready-to-merge, or
   escalated), recompute the unblocked set → next wave. None left →
   **wrap-up**.

Everything else — context economy, escalation, wrap-up, rules — is unchanged.

## Delivery pipeline (per sub-issue)

### 0. Entry point — resume, never rebuild

(Pipeline step 0, not the top-level Step 0 that publishes the context docs.)

A run can die at any point — a dead session, a compaction, a Ctrl-C — and the
sub-issues it half-delivered are still open, so re-running `/developer <spec>`
picks them right back up. What the tracker forgets is how far each one got:
build from scratch again and you get a second PR for the same sub-issue and a
second review paying for it. So before triaging, ask the code host whether a
change already exists for this sub-issue, per its "open change for this issue"
operation. GitHub default:

```bash
gh pr list --state open --search '"Closes #<subissue>" in:body' --json number,isDraft
```

- **No open PR** → nothing to resume: step 1 (Triage).
- **One open PR, no unresolved review threads** → the build landed but the
  review did not: keep its `<PR>`, skip Triage and Build, start at step 3
  (Review).
- **One open PR with unresolved review threads** → a review landed and its
  fixes did not: start at step 4 (Fix cycle), counting from cycle 1 with the
  fixer at `opus` (the build tier died with the session that chose it).
- **More than one open PR matches** → **escalate**: two open changes for one
  sub-issue is a human's call, never a pick.

GitHub default for the unresolved-thread count:

```bash
gh api graphql -f query='
{
  repository(owner:"OWNER", name:"REPO") {
    pullRequest(number: <PR>) {
      reviewThreads(first: 50) { nodes { isResolved } }
    }
  }
}' --jq '[.data.repository.pullRequest.reviewThreads.nodes[]
          | select(.isResolved == false)] | length'
```

The fix-cycle budget starts fresh on a resume: a PR that already burned cycles
in the dead run gets three more here. That is deliberate — the alternative is
reconstructing a counter nothing ever recorded — and the `ready-for-human` gate
is what stops a sub-issue looping forever across runs.

### 1. Triage

Spawn `dispatcher`:

> Triage issue #`<subissue>`. Score its implementation complexity per your
> rubric. Your entire final message must be the
> `RESULT complexity=… model=… touches=… hints=… reason=…` line — nothing
> before it, nothing after it.

Parse `complexity=` first:

- **`complexity=oversized`** → the sub-issue does not fit in a single fresh
  context window. **Do not build it.** No model tier rescues a ticket that
  does not fit: the builder runs out of room, the review finds half a
  feature, and three fix cycles burn against the same wall. Go straight to
  **Escalation**, quoting the dispatcher's `hints=` — they carry the
  proposed split — and move to the next sub-issue. No BUILD, no review, no
  fix cycles are spent on it.
- Anything else → parse `model=<tier>` and continue to Build.

On any malformed result, default to `opus` and build — a line you cannot
parse is not an `oversized` verdict. Parse `touches=` and `hints=` too,
defaulting each to `none` if the line predates these fields or omits them —
never block the pipeline on a missing hint.

### 2. Build

Spawn `code-author` with `model: <tier>` and `isolation: "worktree"`:

> BUILD job. Spec issue #`<spec>`, sub-issue #`<subissue>`.
> Run the implement-issue skill on the sub-issue. The sub-issue's
> `## Spec extract` section carries the spec decisions that apply to it —
> read the full spec issue only if that section is missing.
> Triage found: `<dispatcher's hints, verbatim, or omit this line
> entirely when hints=none>`.
> Your entire final message must be the `RESULT pr=… url=…` line — no summary
> before it, nothing after it. Whatever deserves a record goes in the PR body,
> not in your reply.

- `RESULT blocked …` → **escalate** (see below) and move to the next
  sub-issue.
- `RESULT pr=<PR> url=<URL>` → keep `<PR>`, continue.

### 3. Review

Spawn `diff-reviewer` with `isolation: "worktree"`:

> Review PR #`<PR>` by running the review-pr skill on it — its step 1 plus
> the repo's `docs/agents/code-host.md` give the exact checkout procedure
> for your worktree; follow them, not memory. Post the review (inline
> comments + summary) as a single COMMENT submission — never an approval
> event — and do not mark the PR ready or merge; those are orchestrator
> steps. Your entire final message must be the `RESULT verdict=…` line — the
> review itself is your output, your reply is not.

Then **mark the PR ready yourself**, whatever the verdict — per the
code-host doc's mark-ready operation. GitHub default:

```bash
gh pr ready <PR>
```

Skip it whenever the PR is already ready — a re-review, or a resumed run
whose step 0 found `isDraft: false`.

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
   tier (haiku → sonnet → opus; opus stays opus). A sub-issue resumed straight
   into this step has no build tier — step 0 already set it to `opus`.
2. Spawn `code-author` with that model and `isolation: "worktree"`:

   > FIX job. PR #`<PR>`. Run the fix-pr skill to address all review
   > threads — its step 1 plus the repo's `docs/agents/code-host.md` give
   > the exact checkout procedure for your worktree; follow them, not
   > memory. Pushing the fixes and replying to the review threads are part
   > of your delegated task. Your entire final message must be the
   > `RESULT pr=… url=…` line — what you fixed belongs in the thread replies,
   > not in your reply to me.

   When this cycle was triggered by the **checks gate** (Merge step) rather
   than by a review verdict, append one line to that prompt naming the
   failure — `The PR's CI is red: <failing job URL>. Fix the failing checks
   too; there may be no review threads at all.` — so the fixer does not go
   looking for threads that do not exist.

   `RESULT blocked …` → **escalate**, next sub-issue (a branch-held-by-
   worktree blocked gets the same one-shot Cleanup + re-spawn as in step 3).
3. Re-review: spawn `diff-reviewer` again (same prompt as step 3, mention it
   is a re-review after a fix pass).
   - `CLEAN` → **Merge**.
   - `NEEDS_FIXES` and `c < 3` → next cycle.
   - `NEEDS_FIXES` and `c = 3` → **escalate** (do NOT merge), next sub-issue.

### 5. Merge

**With `merge: manual`** (the factory default) there is nothing to merge:
you already marked the PR ready after the review, so record the sub-issue
as **ready-to-merge**, update its board task (`— ready to merge: PR #<PR>`),
run **Cleanup** (step 6), record its row (step 7), and move on. The sub-issue
stays open until the human merges, so its dependents remain blocked this run.

Say **how** to merge the moment a sub-issue becomes ready-to-merge — a bare
"ready to merge" leaves the user asking what to do, especially off GitHub.
State the code-host doc's merge operation concretely.

**With `merge: auto`**: this merge is pre-authorized — the user opted into
`merge: auto` in `docs/agents/developer-defaults.md` (or passed
`--auto-merge` this run), which is standing authorization to merge PRs whose
review verdict is CLEAN. If the permission system still asks, say exactly
that; if it *denies*, follow the denial rule under Rules (escalate, never
retry).

**Checks gate — never merge on red CI.** If `docs/agents/code-host.md`
declares a CI system, wait for the PR's checks and read their result before
merging, per its "check the change's CI status" operation. GitHub default:

```bash
gh pr checks <PR> --watch --fail-fast    # exits non-zero if any check fails
```

- **Green** (or the code-host doc declares no CI) → merge.
- **Red** → this is **not** a conflict: treat it as one more **fix cycle**
  (step 4), spawning the fixer with the failing job's URL appended to its
  prompt. The same three-cycle budget applies; exhausted → **escalate**.
  Merging a red PR is the one failure this gate exists to prevent, so never
  fall through to the merge command on red — not even when the failing check
  looks unrelated.

Without this gate a repo with no branch protection merges its own red build,
and a repo *with* required checks fails the merge for a reason that is not a
conflict — which is exactly what makes the merge-fix job (`MERGE-FIX.md`, and
the failure branch further down this step) the wrong answer to it.

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

If the merge fails **after** the checks gate passed, it is a conflict with a
previously merged change: read `MERGE-FIX.md` and dispatch the job it
describes, then merge again. That file also covers the conflict a human hits
on their own merge under `merge: manual` — the answer is the same job, never
the main context.

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
  --branch "$BRANCH" --branch "fix/pr-<PR>*" \
  --branch "agent/issue-<subissue>-*" --sha "$HEAD_SHA"
```

(The two `gh pr view` lines are the GitHub default for the change-metadata
operation — on another host get branch and head sha per
`docs/agents/code-host.md`.)

(A blocked build that never opened a PR has no `$BRANCH`/`$HEAD_SHA` — drop
those flags; the `agent/issue-<subissue>-*` pattern still catches its
worktree.)

If the sub-issue was **merged**, also delete the remote branch now (the merge
deliberately skipped `--delete-branch`):

```bash
git push origin --delete $BRANCH
```

Matching strictly on this sub-issue's branches/sha is what makes this safe in
parallel mode — other wave members' worktrees never match. On an escalated or
ready-to-merge sub-issue the remote branch and open PR are untouched; only
local state goes.

A review that ran before a fix cycle left its worktree detached at a sha the
fixes have since superseded, so it never matches `--sha` here. That is
expected: the wrap-up sweep removes those — do not chase them now, and do not
improvise extra flags for them.

### 7. Record the row

The moment a sub-issue reaches its terminal state — **merged**,
**ready-to-merge**, or **escalated** — append its ledger row to this run's log,
before touching the next sub-issue:

```bash
mkdir -p .scratch
echo "$(date +%F) spec=#<spec> sub=#<N> model=<tier> pr=#<PR> verdict=<CLEAN|—> cycles=<n> wave=<w|—> outcome=<merged|ready-to-merge|escalated>" \
  >> .scratch/developer-run-<spec>.log
```

(`verdict=—` / `wave=—` where the field does not apply — an escalated
sub-issue that never got a CLEAN, sequential mode. `pr=none` for a build that
never opened one, and `model=none pr=none cycles=0` for a sub-issue escalated
as `oversized`, which never reached a builder at all — that row is what lets
the harvest notice a spec whose tickets are systematically too big.)

Write it here and the wrap-up reads facts instead of recalling them: a run that
survives ten sub-issues, a context compaction, and a resume (step 0) still
reports the exact tier, PR and cycle count of the first one. The row is the
same one the wrap-up hands the harvest and the same one the chat summary
tabulates — write it once, correctly, now.

The log is a run artifact, not tracked work: **never stage it**. The
context-docs publish (the top-level Step 0) and the local-tracker
`chore(tracker):` commits both name their own paths, so neither picks it up.

## Escalation

When a sub-issue is blocked, triaged **oversized**, non-convergent after 3
fix cycles, or unmergeable, apply the `ready-for-human` triage label to the
sub-issue and comment on both the sub-issue and the spec, per the tracker
ops. GitHub default:

```bash
gh issue edit <subissue> --add-label "ready-for-human"
gh issue comment <subissue> --body "Escalated by /developer: <reason>. PR: <url or none>."
gh issue comment <spec> --body "Sub-issue #<subissue> escalated: <one-line reason>."
```

**Escalating an `oversized` sub-issue**, the comment must carry the
**proposed partition**, not just the verdict: the dispatcher already saw
where the work splits and said so in `hints=`. Pass those hints through
verbatim, so the human gets an actionable "split this into A, B, C" instead
of a bare "too big". Say `PR: none` — nothing was built. GitHub default:

```bash
gh issue comment <subissue> --body "Escalated by /developer: oversized — does not fit in a single fresh context window. <reason, from the dispatcher>.

Proposed split: <the dispatcher's hints, verbatim>

Split this into separate sub-issues, then remove the \`ready-for-human\` label to put them back in play. PR: none."
```

Leave the PR open (never merge an unclean PR). Run the **Cleanup** step
(step 6) — the local worktrees go, the remote branch and PR stay — record the
row (step 7), then continue the loop with the next unblocked sub-issue. An
`oversized` sub-issue has no PR and no worktree: record its row with
`pr=none` and skip Cleanup.

The label is what makes the escalation outlive this session: the pick (spec
loop step 1) skips a `ready-for-human` sub-issue on every future run, until a
human removes it.

## Wrap-up

When no deliverable sub-issue remains — all closed or ready-to-merge, or the
rest blocked by escalated/unmerged ones — **read `WRAP-UP.md` and follow it**.
It holds the seven closing steps (reconcile the board, harvest + ledger, final
sweep, close the spec, push notification, chat summary, execution report). It
is read once, here, at the end of the run.

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
  the scoped `.scratch/` tracker-write commits from `LOCAL-HOST.md`. If the
  script warns that the primary checkout is detached, report it — never
  repair it.
- Only spawn the fix worker when the review said `NEEDS_FIXES` or the
  checks gate found the change's CI red.
- Never spawn a build for a sub-issue triaged `oversized` — escalate it
  with the proposed split instead. Buying it a stronger model is the one
  thing that does not work.
- Never merge a change whose CI checks are red, whatever the merge policy
  and however unrelated the failing check looks.
- Never resolve merge conflicts in the main context — not even when the
  user hands you one interactively. That is always the merge-fix job's
  work, in its own worktree.
- Marking ready and merging are yours, never a worker's; posting the review
  is the reviewer's, never yours. Never author, edit, or amend review
  content in the main context.
- If a permission is denied — a worker reports one (posting the review,
  pushing, commenting), or your own code-host write is denied (marking
  ready, merging, …) — never re-run the denied action yourself or re-shape
  it into a different command: that is tunneling around the denial and will
  also be blocked. Treat the sub-issue as blocked: **escalate** it and
  continue the loop.
