---
name: developer
description: Orchestrates unattended spec delivery — loops over a spec's child issues in dependency order, dispatching code-author (implement) and diff-reviewer (review) workers per sub-issue — each build's model comes from the sub-issue's own ## Complexity section, with a review→fix cycle until CLEAN, then merging per the repo's merge policy. Tracker- and host-agnostic — issues and changes live wherever docs/agents/issue-tracker.md and docs/agents/code-host.md say (GitHub via gh is the factory default). Factory defaults are parallel execution and manual merge; repo defaults live in docs/agents/developer-defaults.md and per-run flags (--parallel/--sequential, --auto-merge/--no-auto-merge) override them. Use when user says "/developer", "deliver this spec" (or "deliver this PRD"), "deliver this sub-issue", or wants the build→review→fix pipeline.
---

# Developer (orchestrator)

Drives the build → review → fix → merge pipeline across isolated subagent
workers, looping over every sub-issue of a spec unattended. Each worker gets a
**clean context** — it knows only what you pass in its prompt. You hold the
state between steps.

## Invoke

```
/developer <issue>              # spec with sub-issues → deliver them all
                                # plain issue → deliver just that one
/developer <spec> <subissue>    # deliver a single specific sub-issue

Flags (override the repo defaults — see Run configuration):
  --parallel | --sequential       # spec mode: waves vs one-at-a-time
  --auto-merge | --no-auto-merge  # merge CLEAN PRs vs leave them ready
```

If no issue number is given, ask for it and stop; never guess one. The
execution flags only change spec mode. Accept the bare words `parallel` /
`sequential` as synonyms.

> **Namespacing.** Installed as a plugin, skills and agents carry the plugin
> prefix (`developer-skills:<name>`, `developer-skills:code-author`,
> `developer-skills:diff-reviewer`). Use the names exactly as your
> available-skills and available-agents lists show them.

## Contract docs (tracker + code host)

Two committed docs define this repo's mechanics, and every worker reads them
in its own context:

- **`docs/agents/issue-tracker.md`** — issue operations, in its
  `## Delivery operations` section.
- **`docs/agents/code-host.md`** — change operations (publish, check out,
  review, mark ready, reply, merge, auto-close semantics).

Read both once at the start, together with `docs/agents/developer-defaults.md`
(Run configuration), in **one** call. Every command block below shows the
GitHub factory default (`gh`); **when a contract doc defines a different
mechanic for the same operation, the doc wins.** Missing docs → GitHub
defaults as-is (suggest `/setup-developer-skills` if that looks wrong).

Note three things from `code-host.md`: whether the host is **GitHub** (it
decides how the checks gate runs, step 5), whether it **declares CI** on
changes (its `CI` line; `none` means there is no gate at all), and whether it
**auto-closes issues on merge** (if not, you close each delivered issue
yourself per the tracker ops right after verifying the merge).

**Their annexes are deferred.** `code-host-ci.md` belongs to the checks gate
and, on GitHub, the bundled gate script replaces it for you (step 5) — leave
it to the workers. `issue-authoring.md` is for whatever *creates* issues; this
pipeline never opens it.

**If either doc says the tracker or the code host is `local`, read
`LOCAL-HOST.md` now**, before anything else: it holds every standing
adjustment a local host needs. Three more files next to this SKILL.md are read
**on demand**, never at the start: `RESUME.md` on a resume, `MERGE-FIX.md` at
the first merge conflict, `WRAP-UP.md` when the loop ends. Like
`scripts/cleanup-worktrees.sh` and `scripts/checks-gate.sh`, they live in this
skill's own directory; a step that says to read one is not optional.

## Run configuration

Two knobs, resolved once before mode detection and kept for the whole run —
CLI flag > repo default (`docs/agents/developer-defaults.md`) > factory
default. Ignore any other key in that file.

| Knob        | Values                    | Factory default |
|-------------|---------------------------|-----------------|
| `execution` | `parallel` / `sequential` | `parallel`      |
| `merge`     | `auto` / `manual`         | `manual`        |

State it in one line before starting, e.g.
`Run config: execution=parallel, merge=manual (repo defaults)`.

- **`merge: auto`** — a CLEAN verdict leads to the merge (step 5). The
  committed `merge: auto` line is the user's standing authorization.
- **`merge: manual`** — the pipeline stops at CLEAN: the PR is already marked
  ready, so record the sub-issue as **ready-to-merge** and leave the merge to
  the human. Sub-issues close only on merge, so anything blocked by a
  ready-to-merge sub-issue stays blocked this run — expected, not an error.

## Workers (subagents)

| Step    | Subagent        | Model                           | Isolation  | Skill it runs     |
|---------|-----------------|---------------------------------|------------|-------------------|
| build   | `code-author`   | from the sub-issue's complexity | `worktree` | `implement-issue` |
| review  | `diff-reviewer` | opus first, sonnet on re-review | `worktree` | `review-pr`       |
| fix     | `code-author`   | escalates per cycle             | `worktree` | `fix-pr`          |
| harvest | `code-author`   | sonnet (pinned)                 | `worktree` | (reads PR bodies) |

Spawn each via the **Agent** tool with the matching `subagent_type` and
`isolation: "worktree"`. Pass `model` explicitly to code-author spawns and to
re-review spawns (`model: "sonnet"`); the first review stays on the agent's
pinned opus. Never run these skills in the main context — isolation is the
point.

**Every spawn is `run_in_background: true`**, in both execution modes. A
foreground spawn dies with your turn — a Ctrl-C or a dropped connection takes
its context, worktree and commits with it. Sequential mode means *wait for
this worker's result before spawning the next*, not *spawn in the
foreground*.

At every spawn:

- Give it a `description` naming the job and the sub-issue — `Build #<N>`,
  `Review PR #<PR>`, `Fix #<N> cycle 2`.
- **Keep the `agentId`** until its `RESULT` arrives: it is the handle that
  resumes the worker instead of rebuilding.
- On a **BUILD, FIX or HARVEST** spawn, append a spawn row to the run log as
  soon as you have the `agentId` (batch the rows of one turn into one call):

  ```bash
  mkdir -p .scratch
  echo "$(date +%F) spec=#<spec> sub=#<N> event=spawned job=<build|fix|harvest> agent=<agentId> model=<tier>" \
    >> .scratch/developer-run-<spec>.log
  ```

  (`sub=none` for the harvest.) Review spawns get no row — they are cheap to
  repeat and step 0 reconstructs them.

## Context economy

Your context is the one resource the whole run shares, and **every turn you
take re-reads all of it**. The cost of a run is your context size times your
number of turns, so cut both.

- **Fewer turns.** Fold reads and local bookkeeping that happen at the same
  moment into one Bash call — the blocks below are already shaped that way.
  The one exception is code-host writes (last rule under **Rules**).
- **Never read issue or PR bodies or CI logs yourself**, nor the contract
  docs' annexes — except the CI annex at the checks gate on a non-GitHub
  host. Workers read them in their own disposable contexts; you run the
  bounded listing commands below.
- **Bounded output.** Ask for the fields you need (`--json`/`--jq`) and cap
  the rest (`2>&1 | head -20`): a malformed command can dump its tool's whole
  `--help`. Never leave a watching or streaming command's progress
  unredirected.
- **Never spawn a worker for what a command answers.** Every spawn costs
  ~750 tokens of envelope whatever it carries.
- **A worker's whole final message is its `RESULT` line.** Anything worth
  keeping belongs on the PR or the issue, not in your context.
- Track per sub-issue: number, model, PR, verdict, fix cycles, wave, the live
  worker's `agentId`, outcome — and write the row to the run log the moment
  it goes terminal (step 7).

## Resuming the orchestrator

A run outlives your turn: workers keep going in the background and their
notifications can arrive late. **While a run is in flight, every prompt that
reaches you is a resume** — a bare `Continue from where you left off.`, an
empty continuation, a notification you think you already handled. There is no
state in which the right answer is "no response requested": either work is
pending and you take its next step, or nothing is and you go to **Wrap-up**.

A worker's `RESULT` you were waiting for is just the next step. Anything else
— or any doubt about where the run stands — **read `RESUME.md` and follow
it**. Before rebuilding anything, check whether its worker is alive
(`ListAgents`) and resume it with **SendMessage**: re-spawning a live
worker's job pays twice for work that was never lost.

## Step 0 — Publish context docs before anything else

Workers branch from `origin/main`, so a domain-context file that is not
committed **and pushed** is invisible to them:

```bash
git status --porcelain -- CONTEXT-MAP.md '**/CONTEXT.md' docs/adr docs/agents AGENTS.md CLAUDE.md
```

If anything shows up, stage **only those paths**, commit on the current branch
(must be `main` — if not, stop and tell the user) and push:

```bash
git add CONTEXT-MAP.md '**/CONTEXT.md' docs/adr docs/agents AGENTS.md CLAUDE.md
git commit -m "docs(domain): publish context map and ADR updates"
git push origin main
```

If the push is rejected, stop and report — never rebase or force. The user is
still there at this point.

## Mode detection

Enumerate the children of the given issue per the tracker's Delivery
operations. GitHub default (OWNER/REPO from `git remote -v`):

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

`hasNextPage: true` → **stop and report**: more than 50 sub-issues is not sized
for this pipeline; tell the user to split the spec. Never proceed on the
first page alone. Keep each sub-issue's labels — the pick reads them. Where
a tracker's enumeration carries no labels, get them per its read-labels
operation instead.

(`#<N>` is the issue ref in the tracker's format, `#<PR>` the change ref in
the code host's.)

- **Open sub-issues exist → spec mode**: loop over them (below).
- **No sub-issues → single mode**: run the delivery pipeline once on the
  issue itself, with no separate spec.
- **Two arguments**: run the pipeline once on `<subissue>` with `<spec>` as
  the spec, no loop. If it ends **merged**, read `WRAP-UP.md` and run only its
  **Close the spec** step (step 4).

## Progress board (spec mode — not optional)

The user follows the run through the harness task list; keep it faithful at
every transition.

1. **Right after mode detection**, create one task per open sub-issue with
   **TaskCreate**, in sub-issue order: subject `#<N> <short>`, activeForm
   `Delivering #<N>`. `<short>` is the title **trimmed to about six words / 50
   characters** at a word boundary, no ellipsis, and it never grows — the
   harness re-injects the whole board into your context on a timer.
2. Pipeline starts on a sub-issue → `status: in_progress`.
3. Terminal transitions, the moment they happen:
   - **merged** (verified CLOSED) → `status: completed`.
   - **ready-to-merge** → back to `pending`, subject
     `#<N> <short> — ready to merge: PR #<PR>`.
   - **escalated** → back to `pending`, subject
     `#<N> <short> — escalated: <one-line reason>`. Never completed.
4. Sub-issues that never became deliverable stay pending; rename them
   `#<N> <short> — blocked by #<M>` at wrap-up.

Single mode skips the board.

**The board is the report — say nothing beside it.** Between the run-config
line and the wrap-up, a spec run's default output is *nothing*: no wave
announcements, no tier tables, no running tallies. Only these, each in one or
two lines:

- the run config, once;
- what you recovered, after a resume;
- a switch into the conflict queue;
- **how** to merge, the first time a sub-issue lands ready-to-merge (once per
  run);
- anything that **stops** the run or needs the human (an escalation and why, a
  denied permission, a spec too large);
- a direct answer to a direct question from the user.

## Spec loop

Repeat while open sub-issues remain:

1. **Pick the next unblocked sub-issue**: for each open sub-issue (lowest
   number first), check its blockers without reading full bodies. Blockers
   may be native dependency links, a `Blocked by` body section, or both —
   check both, for all candidates in one call. GitHub default:

   ```bash
   # native dependencies: count of OPEN blockers (0 or absent = clear)
   gh api repos/{owner}/{repo}/issues/<N> --jq '.issue_dependencies_summary.blocked_by // 0'
   # body fallback: every blocker listed in the section must be CLOSED
   gh issue view <N> --json body --jq '.body' \
     | awk '/^##[#]* *[Bb]locked by/{f=1;next} /^#/{f=0} f'
   gh issue view <BLOCKER> --json state --jq '.state'
   ```

   Extract the whole `Blocked by` **section** as above, never a fixed
   `grep -A<n>` window. Take the first open sub-issue whose blockers are all
   closed, except:

   - **Skip any sub-issue labelled `ready-for-human`** (or the repo's string
     for that role in `docs/agents/triage-labels.md`) — from the enumerated
     labels plus the ones you applied this run. That label is the escalation
     gate; **removing it re-queues the sub-issue**.
   - With `merge: manual`, sub-issues you already delivered as ready-to-merge
     count as done for your loop, and their dependents stay blocked.

2. Run the **delivery pipeline** on it.
3. **merged** / **ready-to-merge** → next iteration. **escalated** / blocked →
   record it, next iteration.
4. No deliverable sub-issue left → **Wrap-up**.

## Parallel mode (`execution: parallel`)

Parallel (the factory default) builds independent sub-issues concurrently and
accepts conflicts between their PRs as expected work. (Sequential with
`merge: auto` avoids them by construction: each PR branches from a `main`
that already holds the previous one. With `merge: manual` siblings branch
from the same `main` either way.)

Work in **waves**:

1. **Wave = every open sub-issue whose blockers are all closed**, minus the
   ones the spec loop's gate excludes.
2. Run the pipeline on each member concurrently: step 0 first for all of them
   (one call), read each tier (step 1), spawn the builds in parallel. A
   resumed member goes straight to review or fix alongside them. As each
   build reports, spawn its reviewer; as each reviewer reports, mark ready;
   fix cycles run per PR as in the sequential pipeline. **Cap concurrent
   build/review/fix workers at 3**; queue the rest.
3. **Merges are strictly serial** — never two at once. **Never refresh the
   siblings after a merge.** With #1, #2 and #3 green together, refreshing
   #2 and #3 when #1 merges, and #2 again when #3 merges, re-runs CI on every
   open sibling at every merge — quadratic in the wave — for nothing the
   gate does not already decide. Each PR is handled only at its own checks
   gate (step 5), right before its merge: if the repo requires up-to-date
   branches GitHub reports it `BEHIND` and the gate updates **that PR only**,
   once; if it does not, the PR merges on the green CI it already has. A
   conflict with a just-merged sibling surfaces as `DIRTY` at that PR's own
   gate — later than an eager refresh would have shown it, but the conflict
   queue only works one PR at a time anyway.
4. **The first conflict of the wave** — `DIRTY` from a gate, or a failed
   merge — switches the wave to the **conflict queue**: read
   `MERGE-FIX.md` and follow it. At most one merge-fix worker is ever alive.
5. Every member delivered (merged, ready-to-merge or escalated) → recompute
   the unblocked set → next wave. None left → **Wrap-up**.

## Delivery pipeline (per sub-issue)

### 0. Entry point — resume, never rebuild

A dead run leaves its sub-issues open, and re-running `/developer <spec>`
picks them up — so ask the code host whether a change already exists before
building; read the model tier (step 1) in the same call. GitHub default:

```bash
gh pr list --state open --search '"Closes #<subissue>" in:body' --json number,isDraft
```

- **No open PR** → step 1 (Model tier), then Build.
- **One open PR, no unresolved review threads** → keep `<PR>`, skip Build,
  go to step 3 (Review); the reviewer settles its own scope. If it comes back
  `blocked reason=no new commits since the last review`, everything it
  raised is resolved: treat it as **CLEAN** and go to Merge — here only.
- **One open PR with unresolved threads** → start at step 4 (Fix cycle),
  cycle 1, with the tier from step 1.
- **More than one open PR matches** → **escalate**; never pick one.

Unresolved-thread count, GitHub default:

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

A resumed PR gets a fresh three-cycle budget; the `ready-for-human` gate is
what stops a sub-issue looping across runs.

### 1. Model tier

Read the sub-issue's `## Complexity` section only — never the body. GitHub
default:

```bash
gh issue view <N> --json body --jq '.body' \
  | awk '/^##[#]* *[Cc]omplexity/{f=1;next} /^#/{f=0} f' | head -3
```

Starts with `complex` → **`opus`**. Anything else, or no section → **`sonnet`**.
No worker is spawned to rate a ticket.

### 2. Build

Spawn `code-author` with `model: <tier>`, `isolation: "worktree"`,
`run_in_background: true`, then log the spawn row:

> BUILD job. Spec issue #`<spec>`, sub-issue #`<subissue>`.
> Run the implement-issue skill on the sub-issue. The sub-issue's
> `## Spec extract` section carries the spec decisions that apply to it —
> read the full spec issue only if that section is missing.
> Your entire final message must be the `RESULT pr=… url=…` line — no summary
> before it, nothing after it. Whatever deserves a record goes in the PR body,
> not in your reply. Report only a PR number you have confirmed exists.

- `RESULT blocked …` → **escalate**, next sub-issue.
- `RESULT pr=<PR> url=<URL>` → **confirm the PR exists** before anything else
  (a worker's `RESULT` is a claim; this is the one free check):

  ```bash
  gh pr view <PR> --json number,state,headRefName
  ```

  On a 404, **never re-spawn the build** — the work is almost certainly
  uncommitted or unpublished in its worktree. Resume the worker (its spawn row
  holds the `agentId`; check `ListAgents`) with **SendMessage**, telling it
  what you found and to run its publish step for real. Worker gone →
  escalate, naming its branch and worktree.

### 3. Review

Spawn `diff-reviewer` with `isolation: "worktree"`, `run_in_background: true`:

> Review PR #`<PR>` by running the review-pr skill on it — its step 1 plus
> the repo's `docs/agents/code-host.md` give the exact checkout procedure
> for your worktree; follow them, not memory. Post the review (inline
> comments + summary) as a single COMMENT submission — never an approval
> event — and do not mark the PR ready or merge; those are orchestrator
> steps. Your entire final message must be the `RESULT verdict=…` line — the
> review itself is your output, your reply is not.

Then **mark the PR ready yourself**, whatever the verdict, unless it already
is (a re-review, or step 0 saw `isDraft: false`). GitHub default:

```bash
gh pr ready <PR>
```

- `verdict=CLEAN` → **Merge** (step 5).
- `verdict=NEEDS_FIXES` → **Fix cycle** (step 4).
- `RESULT blocked reason=no new commits since the last review …` → compare
  the PR head with the sha you noted before the fix pass. **Moved** → the
  fixer pushed and the reviewer misread its anchor: **escalate**. **Same** →
  treat it as that cycle's `NEEDS_FIXES` (the findings stand) and go straight
  to the next fix cycle without re-spawning the reviewer — or **escalate** if
  that was cycle 3.
- `RESULT blocked` because the branch is held by another worktree (git's
  "already used by worktree") → run **Cleanup** (step 6) and re-spawn the
  reviewer, **once per sub-issue**; blocked again → escalate.
- Any other `blocked` or a malformed result → **escalate**.

### 4. Fix cycle (max 3)

For cycle `c` = 1, 2, 3:

1. Fixer model: cycle 1 uses the build tier; each later cycle escalates one
   tier (sonnet → opus; opus stays opus).
2. Note the PR's head sha (`gh pr view <PR> --json headRefOid --jq
   .headRefOid`) — step 3's no-new-commits check compares against it. Spawn
   `code-author` with that model, `isolation: "worktree"`,
   `run_in_background: true`, then log the spawn row:

   > FIX job. PR #`<PR>`. Run the fix-pr skill to address all review
   > threads — its step 1 plus the repo's `docs/agents/code-host.md` give
   > the exact checkout procedure for your worktree; follow them, not
   > memory. Pushing the fixes and replying to the review threads are part
   > of your delegated task. Your entire final message must be the
   > `RESULT pr=… url=…` line — what you fixed belongs in the thread replies,
   > not in your reply to me.

   When the cycle comes from the **checks gate** rather than a review, append:
   `The PR's CI is red: <job URL>. Fix the failing checks too; there may be no
   review threads at all.`

   `RESULT blocked …` → **escalate** (a branch-held-by-worktree block gets the
   same one-shot Cleanup + re-spawn as in step 3).
3. Re-review: spawn `diff-reviewer` with the step 3 prompt, `model:
   "sonnet"`, plus one line:

   > This is a re-review after fix cycle `<c>`. The skill's step 2 will scope
   > your diff to what landed since the last review — use that scope, and
   > check every previous finding was really fixed in code.

   Do not restate the findings; the reviewer reads them on the PR.
   - `CLEAN` → **Merge**.
   - `NEEDS_FIXES` and `c < 3` → next cycle.
   - `NEEDS_FIXES` and `c = 3` → **escalate** (never merge).

### 5. Merge

**`merge: manual`** → nothing to merge: the PR is ready, so record the
sub-issue as **ready-to-merge**, update its board task, run **Cleanup** (step
6), record its row (step 7) and move on. The first time this happens in a
run, say in one line **how** to merge (the code-host doc's merge operation,
concretely).

**`merge: auto`** → the merge is pre-authorized. If the permission system
still asks, say so; if it *denies*, escalate (Rules) — never retry.

**Checks gate — never merge on red CI.** If `code-host.md` says `CI: none`,
there is no gate: merge. Otherwise, on a GitHub host the gate is one call to
the bundled script — read-only, it waits silently and prints a single
verdict. CI takes longer than a foreground Bash call may run, so run it with
**`run_in_background: true`** and act on its line when the completion
notification arrives (in parallel mode, other workers' results keep arriving
meanwhile — handle them as usual):

```bash
bash <skill-dir>/scripts/checks-gate.sh <PR>
```

On another host, read `docs/agents/code-host-ci.md` now (not earlier) and run
the same sequence with its operations: mergeable state, wait for checks to
register, wait for them to finish, classify a red — waiting inside an
`until`/`for` loop or with **Monitor**, never a command that opens with a bare
`sleep` (the harness blocks it). Act on the verdict:

| Verdict | Action |
|---|---|
| `GREEN` | Merge. |
| `BEHIND` | `gh pr update-branch <PR>` (bare, own call), then run the gate again. The script already lets a fresh update settle; `BEHIND` straight after an update → escalate. |
| `DIRTY` | A conflict, never a red: the merge-fix path (`MERGE-FIX.md`; the conflict queue in parallel mode), then the gate again from the top. |
| `NO_CHECKS` | **Infra-red** (below): CI is declared, yet nothing ever registered on the change. |
| `PENDING` | CI still running after an hour: escalate, naming it. |
| `ERROR …` | Run the gate once more; `ERROR` again → escalate, quoting it. |
| `RED code run=<id> url=<job>` | **Retry once per PR**: `gh run rerun <id> --failed` (bare), then the gate again. Red again → one more **fix cycle** (step 4) with `<job>` appended to the fixer's prompt, same three-cycle budget. |
| `RED code url=<link>` | Not an Actions run, so nothing to retry: a **fix cycle** with `<link>`. |
| `RED infra …` | The code never ran (or no runner ever picked it up): spawn no fixer. **Escalate** naming the cause and go to **Wrap-up** — a CI that cannot start reds every later gate identically. The unblock line: restore the CI, re-run `/developer <spec>`. |

One retry, never two: a wobbly suite reds a fine change, and one retry is the
cheapest way to find out — but a retry *loop* merges a genuinely broken
intermittent test by persistence. **Never read CI logs** to decide: the
verdict is the whole diagnosis you get; the fixer reads the logs from the job
URL. Never fall through to the merge on red, however unrelated the failing
check looks.

**The merge.** Never touch local git state — merge remotely, per the
code-host doc. GitHub default, **exactly** in this form, alone in its own Bash
call (no pipe, no `2>&1 | head`, no `;`/`&&`), because the merge-approval hook
matches only the bare command and anything else goes to the auto-mode
classifier, which denies it:

```bash
gh pr merge <PR> --merge
```

No `--delete-branch`: it also tries to delete the local branch, which the
build worker's worktree still holds. Step 6 deletes the remote branch.

A merge that fails **after** a `GREEN` gate is a conflict with a just-merged
change: read `MERGE-FIX.md`, dispatch its job (in parallel mode, through the
conflict queue), then merge again. The same file covers a conflict the human
hits on their own merge under `merge: manual` — always the merge-fix job,
never the main context.

### 6. Cleanup

Run it whenever a sub-issue finishes — merged, ready-to-merge or escalated.
Build and fix workers always leave a branch, commits and `node_modules`
behind; without this every sub-issue leaks a worktree.

All removal goes through the bundled `scripts/cleanup-worktrees.sh` — **never
improvise `git worktree remove`, `git branch -D` or any repair yourself**. It
removes only what matches, never the primary checkout, keeps dirty worktrees,
and deletes a branch only when its commits are on a remote. Every refusal is
a `KEPT` line with its reason and every anomaly a `WARN` line (a detached
primary checkout means a worker escaped its worktree): carry them into the
wrap-up verbatim, never re-run with broader flags, never "fix" the checkout.

After a **merge**, the closing bookkeeping is **one** call — verify the
issue closed, clean up, check the remote branch and record the row (step 7).
GitHub default:

```bash
gh issue view <subissue> --json state --jq '"issue=" + .state'   # expect CLOSED
B=$(gh pr view <PR> --json headRefName --jq .headRefName)
H=$(gh pr view <PR> --json headRefOid --jq .headRefOid)
bash <skill-dir>/scripts/cleanup-worktrees.sh \
  --branch "$B" --branch "fix/pr-<PR>*" \
  --branch "agent/issue-<subissue>-*" --sha "$H" 2>&1 | grep -vE '^(REMOVED|DELETED) '
git ls-remote --exit-code --heads origin "$B" >/dev/null; echo "remote-branch-exit=$?"
echo "<step 7 row>" >> .scratch/developer-run-<spec>.log
```

- `issue=` not `CLOSED` and the host auto-closes → check again once; still
  open → close it per the tracker ops with a comment naming the merged
  change. No auto-close on this host → close it yourself, always.
- `remote-branch-exit=0` → the branch is still there: delete it in a
  **separate**, bare call. `2` → the host already did; skip it.

  ```bash
  git push origin --delete "<branch>"
  ```

For a **ready-to-merge or escalated** sub-issue, run only the cleanup line
(and record the row): the remote branch and the PR stay. A blocked build with
no PR has no `$B`/`$H` — drop those flags; its never-pushed branch comes back
`KEPT (tip not on any remote)`, which is the guard working: leave it and
report it. On another host get branch and head sha per
`docs/agents/code-host.md`.

A reviewer's worktree detached at a sha a later fix superseded never matches
`--sha`; the wrap-up sweep removes it — do not chase it.

### 7. Record the row

The moment a sub-issue goes terminal — **merged**, **ready-to-merge** or
**escalated** — its ledger row goes into the run log (inside the step 6 block
after a merge), before you touch the next sub-issue:

```
<date> spec=#<spec> sub=#<N> model=<tier> effort=<effort> pr=#<PR> verdict=<CLEAN|—> cycles=<n> mergefix=<n> wave=<w|—> outcome=<merged|ready-to-merge|escalated>
```

`effort=` is the build's reasoning effort as pinned in the `code-author`
definition (`medium` today). `cycles=` counts fix cycles (the ticket being
hard), `mergefix=` merge-fix workers (the wave being expensive). `—` where a
field does not apply; `pr=none` for a build that never opened one. Rows with
`outcome=` are what the wrap-up and a resume read; spawn rows have none.

The log is a run artifact: **never stage it**.

## Escalation

When a sub-issue is blocked, non-convergent after 3 fix cycles, or
unmergeable, apply the `ready-for-human` label and comment on the sub-issue
and the spec, per the tracker ops. GitHub default:

```bash
gh issue edit <subissue> --add-label "ready-for-human"
gh issue comment <subissue> --body "Escalated by /developer: <reason>. PR: <url or none>."
gh issue comment <spec> --body "Sub-issue #<subissue> escalated: <one-line reason>."
```

Leave the PR open (never merge an unclean PR), run **Cleanup** (step 6),
record the row (step 7), and continue with the next unblocked sub-issue. The
label makes the escalation outlive this session: every future pick skips it
until a human removes it.

## Wrap-up

When no deliverable sub-issue remains, **read `WRAP-UP.md` and follow it**
(reconcile the board, harvest + ledger, final sweep, close the spec, push
notification, chat summary, execution report). It is read once, here.

## Rules

- Unattended: never stop to ask the user mid-loop. Escalate via labels and
  comments and keep going.
- Sequential: one sub-issue fully delivered before the next starts. Parallel:
  builds, reviews and fixes overlap; merges are always one at a time, and at
  most one merge-fix worker is ever alive.
- Never merge under `merge: manual`. Never merge a change whose checks gate
  did not say `GREEN` — on a repo whose `code-host.md` says `CI: none` there
  is no gate.
- Marking ready and merging are yours, never a worker's; posting the review is
  the reviewer's, never yours. Never author or edit review content.
- Never act on a `RESULT pr=…` you have not confirmed exists.
- Each fresh worker starts stateless: pass everything it needs in its prompt.
  A worker resumed with SendMessage still holds its own context.
- **The agent docs are read-only to this pipeline.** `AGENTS.md`,
  `CLAUDE.md`, `CONTEXT-MAP.md`, `docs/adr/` and `docs/agents/` are
  instructions the run obeys, not state it maintains. Two narrow exceptions:
  `docs/agents/delivery-ledger.md` (the harvest appends to it) and Step 0's
  commit of edits the human already made. Anything else a run learns is
  *proposed* in the summary. Tell workers so when a job goes near these files.
- Never run `git checkout`, `git pull` or any state-changing git command in
  the main context, except Step 0's scoped commit+push, `cleanup-worktrees.sh`,
  the merged-branch `git push origin --delete`, and — local tracker only —
  the `.scratch/` tracker commits from `LOCAL-HOST.md`.
- Never resolve merge conflicts in the main context, not even when the user
  hands you one: that is always the merge-fix job's.
- If a permission is denied — to a worker (posting the review, pushing) or to
  you (marking ready, merging, …) — never re-run or re-shape the denied
  action: **escalate** the sub-issue and continue.
- Every code-host write you run — `gh pr merge`, `gh pr ready`,
  `gh pr update-branch`, `gh run rerun`, `git push origin --delete` (or their
  `docs/agents/code-host.md` equivalents) — is a **bare command in its own
  Bash call**: no pipe, no `2>&1 | head`, no `;`/`&&`, no verification
  chained, and one PR per call — never a loop over several. Permission rules
  and the merge hook match the whole command, and a bulk or chained write
  goes to the auto-mode classifier, which denies it. Their output is a line
  or two anyway.
