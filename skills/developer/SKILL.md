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
  --build-oversized             # build `oversized` tickets instead of escalating
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

Read those two once at the start (they are short — an allowed exception to
"never read bodies yourself").

**Their annexes are deferred, and every worker inherits that.** Each core doc
links phase annexes naming the phase that opens them: `code-host-ci.md` is
opened at the **checks gate**, when a change's CI has to be waited on, read
or classified — nowhere earlier; `issue-authoring.md` is for whatever
*creates* issues (`/to-tickets`) and this pipeline never opens it at all.
Read an annex at the step that names it and not before. A run that opens
them at the start pays the whole contract, three workers deep, per
sub-issue, to use a fraction of it. **Every command block below shows the GitHub
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

Three knobs govern a run. Resolve each one **before mode detection**, in this
precedence order: CLI flag > repo default > factory default.

| Knob        | Values                    | Factory default |
|-------------|---------------------------|-----------------|
| `execution` | `parallel` / `sequential` | `parallel`      |
| `merge`     | `auto` / `manual`         | `manual`        |
| `oversized` | `escalate` / `build`      | `escalate`      |

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

What `oversized` means — what to do with a sub-issue triage scores
`oversized` (`--build-oversized` sets it to `build` for the run):

- **`escalate`** — the default and the safe reading: the ticket is handed to
  a human to re-cut, and nothing is built (Triage step).
- **`build`** — build it anyway, at `opus`, exactly as if triage had said
  `complex`. This is the user's standing answer to "the ticket is too big":
  they have decided the split is not worth the round trip. Note the risk once
  when you resolve the config, then stop arguing it — the dispatcher's fault
  lines still go into the builder's prompt as its order of work, and if the
  builder does come back with half a feature, that PR escalates through the
  ordinary non-convergent path rather than a second opinion about size.

## Workers (subagents)

| Step    | Subagent        | Model                           | Isolation  | Skill it runs     |
|---------|-----------------|---------------------------------|------------|-------------------|
| triage  | `dispatcher`    | sonnet (pinned)                 | —          | (scores a wave)   |
| build   | `code-author`   | chosen by triage                | `worktree` | `implement-issue` |
| review  | `diff-reviewer` | opus first, sonnet on re-review | `worktree` | `review-pr`       |
| fix     | `code-author`   | escalates per cycle             | `worktree` | `fix-pr`          |
| harvest | `code-author`   | sonnet (pinned)                 | `worktree` | (reads PR bodies) |

Spawn each via the **Agent** tool with the matching `subagent_type`. Pass
`isolation: "worktree"` to every code-author and diff-reviewer spawn. Pass
`model` explicitly to code-author spawns (triage decides the tier) and to
**re-review** diff-reviewer spawns (`model: "sonnet"`) — the first review is
discovery across the whole change and stays on the agent's pinned opus, while a
re-review is verification of a diff the skill has already scoped down to the
last fix pass. Never run the skills yourself in the main context — the point is
isolation.

**Every spawn is `run_in_background: true`**, dispatchers included, in both
execution modes. A foreground spawn holds your turn open for the worker's whole
run, and anything that interrupts that turn — a Ctrl-C, a dropped connection —
takes the worker down with it: its context, its worktree and its commits are
gone for good. The same interruption leaves a background worker running and
still reachable. Sequential mode is not an exception to this: it means *wait
for this worker's result before spawning the next*, not *spawn it in the
foreground*.

Three things at every spawn, each cheap now and each the difference between a
resume and a rebuild later:

- Give the Agent tool a `description` that names the job and the sub-issue —
  `Build #<N>`, `Review PR #<PR>`, `Fix #<N> cycle 2`. It is how the worker is
  identified in the agent list and in the user's view of the run.
- **Keep the `agentId`** the tool returns for as long as that worker runs: it
  is the handle that picks the worker back up instead of starting it over (see
  **Resuming the orchestrator**). Drop it when its `RESULT` arrives.
- On a **BUILD, FIX or HARVEST** spawn — the jobs that hold uncommitted work
  and are expensive to lose — append a spawn row to this run's log as soon as
  the tool hands you the `agentId`, so the job leaves a trace that outlives
  your context:

  ```bash
  mkdir -p .scratch
  echo "$(date +%F) spec=#<spec> sub=#<N> event=spawned job=<build|fix|harvest> agent=<agentId> model=<tier>" \
    >> .scratch/developer-run-<spec>.log
  ```

  (`sub=none` on the harvest, which belongs to the whole run.) Triage and
  review spawns skip the row entirely: both are cheap to repeat, and pipeline
  step 0 reconstructs where a PR stands without them. Step 7 writes the other
  kind of row, the terminal one — a resume reads both, the wrap-up reads only
  the terminal ones.

## Context economy

The loop may cover many sub-issues; your context must survive all of them.

- **Never read issue or PR bodies yourself.** Workers read them in their own
  disposable contexts. You only run the cheap listing commands below.
- **Every command you run prints a bounded projection, never a blob.** Ask
  for the fields you need (`--json`/`--jq`, `--format`) and cap what is left
  (`head -20`, `| wc -l`). Two failure modes cost the most: a streaming or
  watching command (`gh pr checks --watch`, `gh run watch`) repainting its
  progress into your transcript, and a **malformed** command dumping its
  tool's entire `--help` — a single mis-escaped `gh pr list --search` did
  exactly that for 4k tokens in one field run. So send both streams of any
  probe you are not certain of through a cap: `<cmd> 2>&1 | head -20`. What
  you need from these commands is one number, one state or one exit code.
- **Every spawn costs about the same whatever it carries** — roughly 750
  tokens of prompt, launch metadata and result notification, against a payload
  that is often one word. So batch the work that can be batched (triage scores
  a whole wave in one dispatcher) and never spawn a worker to recover
  something a default already covers. Builds, reviews and fixes cannot be
  batched — each needs its own worktree and its own clean context — and are
  worth their envelope; a second dispatcher for one missing score is not.
- **Never read CI logs yourself** either — `gh run view --log-failed` and
  anything like it. The Merge step's `--json` classification is the whole
  diagnosis the orchestrator gets; the rest is the fixer's, in its context.
- A worker's whole final message **is** its `RESULT` line — the agents require
  it and every spawn prompt below restates it. A worker that reports prose
  before its line is spending your context, not its own; nothing it says there
  survives the run, so anything worth keeping belongs on the PR or the issue.
- Track per sub-issue: number, task id, chosen model, PR number, verdict, fix
  cycles, wave (parallel mode), the `agentId` of the worker running on it right
  now (dropped the moment its `RESULT` arrives), outcome (merged /
  ready-to-merge / escalated / blocked) — and write the row to the run log the
  moment the sub-issue goes terminal (delivery pipeline step 7), so the wrap-up
  reads facts instead of recalling them. Also keep the dispatcher's
  `touches`/`hints` just long enough to forward `hints` into that sub-issue's
  Build step — discard both once the build is spawned, they have no use after
  that.

## Resuming the orchestrator

A run outlives your turn: workers keep going in the background, their
notifications can arrive late, and sessions get interrupted, compacted or
restarted. So **while a run is in flight, every prompt that reaches you is a
resume** — including a bare `Continue from where you left off.`, an empty
continuation, or a notification you believe you have already handled. There is
no state in which the right answer is "no response requested": either work is
pending and you take its next step, or nothing is, and you go to **Wrap-up**.
Silence is the one failure mode this pipeline cannot recover from on its own.

(This is the orchestrator's own resume. Pipeline step 0 is the per-sub-issue
one — it is what step B below runs.)

On any such prompt:

1. **Rebuild the picture** from the three places that survive a dead context,
   never from recall:
   - the progress board (**TaskList**) — which sub-issues are `in_progress`;
   - `.scratch/developer-run-<spec>.log` — the terminal rows already recorded,
     and the `event=spawned` rows naming the worker that was running on each
     sub-issue still in flight. If a wrap-up already ran this spec, the rows
     from before it are in `.scratch/archive/developer-run-<spec>-*.log`;
   - **ListAgents** — which of those workers are still alive.
2. **Recover each non-terminal sub-issue** in this order, stopping at the first
   that works:

   **A. Its worker is still alive** → **SendMessage** to its `agentId` and ask
   it to report. Its context, its worktree and its commits are all intact, so
   this continues the job rather than repeating it — by far the cheapest
   recovery, and the only one that does not throw away work already paid for.
   A worker that finished while you were not looking answers here too, with the
   `RESULT` whose notification you missed.

   This works for `code-author`. It usually does not for `diff-reviewer`: a
   review changes no files, so its worktree is removed when it ends and a
   reviewer missing from `ListAgents` is missing for good. Try it if it is
   listed; otherwise go straight to B — a review is cheap to repeat, a build
   is not.

   **B. Its worker is gone** → run pipeline **step 0** on that sub-issue
   exactly as written. It asks the code host rather than your memory, and
   routes the sub-issue to Review, to the Fix cycle, or back to Triage when
   nothing was ever opened for it.

3. **Re-enter the loop**: recompute the unblocked set (spec loop step 1, or the
   wave in parallel mode) and carry on. Nothing left → **Wrap-up**.

Say in one line what you recovered and how, before continuing. During an
unattended run the board and that line are the user's whole window into it.

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
   with **TaskCreate**, in sub-issue order: subject `#<N> <short>`,
   activeForm `Delivering #<N>`. The whole plan must be on the board before
   the first worker spawns.

   `<short>` is the sub-issue title **trimmed to about six words / 50
   characters**, cut at a word boundary and with no ellipsis — enough for the
   user to tell the rows apart, and it never grows. Keep the same `<short>`
   for that sub-issue's every later rename. The number is the identifier; the
   words are only a label, and the full title is one `gh issue view` away for
   anyone who needs it. This is not cosmetic: the harness re-injects the
   **whole board** into your context on a timer, so every character of every
   subject is re-read many times over a long run — a board of 25 full titles
   costs more over a run than the entire spawn traffic it is tracking.
2. When the delivery pipeline starts on a sub-issue → **TaskUpdate**
   `status: in_progress`. In parallel mode every wave member goes
   in_progress as its build spawns, so the board shows exactly what is
   running concurrently.
3. Terminal transitions, the moment they happen:
   - **merged** (sub-issue verified CLOSED) → `status: completed`.
   - **ready-to-merge** (`merge: manual`, verdict CLEAN) → back to
     `status: pending` and rename the subject to
     `#<N> <short> — ready to merge: PR #<PR>`. Not completed — the human
     still has to merge it.
   - **escalated** → back to `status: pending` and rename the subject to
     `#<N> <short> — escalated: <one-line reason>`. Never mark an escalated
     sub-issue completed — unchecked items at the end are the human's queue.
4. Sub-issues that never became deliverable (blocked by an escalated one, or
   by a ready-to-merge one the human hasn't merged yet) stay pending; rename
   them `#<N> <short> — blocked by #<M>` at wrap-up.

Single mode (no sub-issues) skips the board.

**The board is the report — do not narrate the run beside it.** Between the
run-config line and the wrap-up, a spec run's default output is *nothing*: the
task list already says which sub-issue is building, which is in review, which
is merged and which is waiting, and it says it live, without costing a turn.
Prose that restates it — "wave 1 launched", "triage complete", a table of the
tier each sub-issue drew, "5 of 25 merged" — is a second, staler copy of the
board, and the user has to read past it to reach the part that is not on the
board. Keep the board current instead; that *is* the progress report.

Six things still get said, each in **one or two lines**, never a table:

- the resolved run config, once, before starting (Run configuration);
- what you recovered, once, after a resume (Resuming the orchestrator);
- a switch into the conflict queue (Parallel mode);
- **how** to merge, the first time a sub-issue lands ready-to-merge under
  `merge: manual` — once for the run, not once per PR; the wrap-up repeats it
  for the rest;
- anything that **stops** the run or needs the human: an escalation and why,
  a denied permission, a spec too large to size;
- a direct question from the user, answered directly — the silence rule
  governs unprompted narration, never a reply.

Everything else the run learns goes where it survives: the board, the PR, the
issue, the run log, and the wrap-up summary at the end.

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
   the ones with no open change get triaged and built. Spawn **one**
   `dispatcher` for all of them at once (Triage step — one spawn per wave, not
   per member, capped at 5 issues a spawn), then their `code-author` BUILD
   jobs in parallel
   (each in its own worktree, `run_in_background: true`) — **minus any member
   the Triage step escalates as `oversized`**, which leaves the wave without
   a build (under `oversized: build`, or against a no-split directive, it is
   built like any other member). A resumed member goes
   straight into the review or fix stage alongside them. As each build
   reports its PR, spawn its `diff-reviewer`; as each reviewer reports,
   mark that PR ready (step 3 of the pipeline); fix cycles run per PR
   exactly as in the sequential pipeline. Cap concurrent build/review/fix
   workers at **3**; queue the rest of the wave.
3. **Merges stay strictly serial** — never merge two PRs concurrently. With
   `merge: auto`, merge each PR as it reaches CLEAN. **After every successful
   merge, refresh the wave's still-open PRs** per the code host's
   update-branch operation — GitHub default, per open sibling:

   ```bash
   gh pr update-branch <PR>
   ```

   It is a remote operation — no local git. Each sibling branched from a
   `main` that did not contain this merge; left stale, its CI goes red for
   synchronization, not for a bug, and a full fix cycle ends up doing what
   this one call does. A sibling whose update fails on a conflict is left
   alone — but note it: that failure is what puts the PR in the conflict
   queue (step 4), which is the only place a conflicting PR is worked on.
   Learning it here rather than at the merge gate is most of the point —
   spec #994 skipped one refresh and met the conflict forty minutes later,
   with the queue idle in between.

   **Every still-open member, including the ones mid-fix-cycle.** A PR that
   is being fixed is exactly the one that will still be open in an hour and
   exactly the one that goes stale; skipping it because "it is not ready yet"
   defers the conflict to the moment you most want a clean merge.

   **One PR per Bash call.** Issue the refreshes as separate commands, not as
   a `for` loop over the wave: a loop that writes to the code host reads as a
   bulk operation to the permission classifier and gets denied wholesale
   (observed in spec #994 — the same two calls, run singly, went through
   untouched).

   Every PR in the wave branched from the same `main`, so any PR merged
   after the first may conflict: on merge failure **after** the Merge step's
   checks gate passed, run the merge-fix job (`MERGE-FIX.md`) and retry once.
   With `merge: manual` there is nothing to serialize — each CLEAN PR just
   becomes ready-to-merge.

   **The first conflict of the wave closes the parallel phase.** From that
   moment the wave finishes through a **conflict queue** (below), not
   concurrently. Conflicts are not independent work: every conflicting PR
   resolves against the same `main`, and the first one merged invalidates
   every resolution computed beside it. Two merge-fix workers running at once
   are one worker and one rewrite waiting to happen.
4. **Conflict queue.** Once step 3 has seen one conflict, the wave's
   remaining unmerged PRs form a queue, ordered oldest-PR-first, and it
   drains **one at a time**:

   - **At most one merge-fix worker is alive in the whole run.** Never spawn
     a second while one is running, whatever the worker cap allows.
   - A PR's merge-fix is spawned **only when that PR is at the head of the
     queue** — i.e. after the previous PR is merged into `main`. Until its
     turn a queued PR gets **no merge-fix worker**; its conflict is not stale
     work, it is work not yet started. (Step 3's `gh pr update-branch` refresh
     still runs on it after every merge — that call is remote, cheap, and
     often *is* the resolution.)
   - When the head PR merges, drop it from the queue and try the next one's
     merge before assuming it still conflicts: the winner's merge, plus the
     refresh, resolves most of the rest for free. Only a merge that actually
     fails earns a merge-fix worker.
   - Everything that is not the merge path — builds, reviews, and review fix
     cycles, including a queued PR's own — carries on in parallel underneath.
     The queue serializes conflict resolution, not the wave.

   Say the switch out loud once, in one line, e.g. `#936 conflicts — wave
   finishing through the conflict queue: #936 → #937 → #938.`

5. When every wave member is delivered (merged, ready-to-merge, or
   escalated), recompute the unblocked set → next wave. None left →
   **wrap-up**.

Everything else — context economy, escalation, wrap-up, rules — is unchanged.

## Delivery pipeline (per sub-issue)

### 0. Entry point — resume, never rebuild

(Pipeline step 0, not the top-level Step 0 that publishes the context docs.
This is the per-sub-issue resume, reached both on a fresh run and as step B of
**Resuming the orchestrator**.)

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
- **One open PR, no unresolved review threads** → keep its `<PR>`, skip
  Triage and Build, start at step 3 (Review). The reviewer settles its own
  scope from the PR's review history, so this covers both shapes: a build
  that was never reviewed (full scope) and one whose review was answered in
  full but never reached a verdict (incremental). If it comes back
  `blocked reason=no new commits since the last review`, the previous review
  was the last word and everything it raised is resolved: treat it as
  **CLEAN** and go to Merge — here only, because no fix pass ran this cycle
  to leave findings standing.
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

**Triage a whole wave in one spawn, not one spawn per sub-issue.** In parallel
mode this step runs once for the wave, covering every member the pipeline's
step 0 found without an open change; in sequential mode the wave is one
sub-issue and the same prompt carries a list of one. Batch at most **5**
issues per dispatcher; a larger wave takes a second batched spawn, never a
spawn per issue. The reason is the spawn envelope, not the dispatcher: a
triage round trip costs the orchestrator ~750 tokens of prompt, launch
metadata and notification whatever it carries, and it carries one word. Five
scores in one spawn pay that once instead of five times, and triage is the
step where it is free to do so — the scores are independent, the codebase
glance is shared, and nothing downstream needs them at different times.

Spawn `dispatcher` with `run_in_background: true`:

> Triage issues #`<N1>`, #`<N2>`, … Score each one's implementation
> complexity per your rubric, independently of the others. Your entire final
> message must be one
> `RESULT issue=… complexity=… model=… touches=… hints=… why=…` line per
> issue, in the order given — nothing before the first, nothing between them,
> nothing after the last. Do not explain your scoring anywhere except the
> `why=` field, which is capped at 15 words: your final message lands in my
> context whole and stays there for the rest of the run, so a paragraph in
> front of the lines is charged to every turn that follows and read by no one.

**Repeat that last sentence in the spawn prompt every time.** It is the rule
this worker breaks most often — twice in field runs, once after the agent
definition had already been hardened — and the spawn prompt is the last thing
it reads before working. Parse `why=` and drop it: it exists to give the
dispatcher's justification a 20-token home instead of a 330-token one, not
because anything downstream needs it.

Match each line back to its sub-issue by `issue=`. A member with **no line at
all** is treated exactly like a malformed one (below). Then, per sub-issue,
parse `complexity=` first:

- **`complexity=oversized`** → the sub-issue does not fit in a single fresh
  context window, and what happens next is the `oversized` knob's call (Run
  configuration):
  - **`oversized: escalate`** (default) → **Do not build it.** No model tier
    rescues a ticket that does not fit: the builder runs out of room, the
    review finds half a feature, and three fix cycles burn against the same
    wall. Go straight to **Escalation**, quoting the dispatcher's `hints=` —
    they carry the fault lines — and move to the next sub-issue. No BUILD, no
    review, no fix cycles are spent on it.
  - **`oversized: build`** → continue to Build at `opus`, passing the
    dispatcher's `hints=` through as usual; the fault lines become the
    builder's order of work. Do not escalate, do not label, and do not
    re-argue the size — the knob is the answer to that argument.

  Before escalating, check the issue body once for an explicit **no-split
  directive** ("deliberately indivisible", "no dividir", "ship as one unit").
  The dispatcher is told to veto its own `oversized` score when it finds one,
  so an `oversized` line on such a ticket means triage missed it: build it at
  `opus` as if the knob said `build`. This is the one place you overrule a
  triage verdict, and only ever in that direction — the author's directive
  outranks the rubric, never the reverse.
- Anything else → parse `model=<tier>` and continue to Build.

On any malformed or missing result, default to `opus` and build — a line you
cannot parse, or that never arrived, is not an `oversized` verdict. Parse
`touches=` and `hints=` too, defaulting each to `none` if the line predates
these fields or omits them — never block the pipeline on a missing hint.
Never re-spawn a dispatcher to recover one missing line: the default costs
less than the round trip it would take to improve on it.

### 2. Build

Spawn `code-author` with `model: <tier>`, `isolation: "worktree"` and
`run_in_background: true`, then log the spawn row (Workers):

> BUILD job. Spec issue #`<spec>`, sub-issue #`<subissue>`.
> Run the implement-issue skill on the sub-issue. The sub-issue's
> `## Spec extract` section carries the spec decisions that apply to it —
> read the full spec issue only if that section is missing.
> Triage found: `<dispatcher's hints, verbatim, or omit this line
> entirely when hints=none>`.
> Your entire final message must be the `RESULT pr=… url=…` line — no summary
> before it, nothing after it. Whatever deserves a record goes in the PR body,
> not in your reply. Report only a PR number you have confirmed exists.

- `RESULT blocked …` → **escalate** (see below) and move to the next
  sub-issue.
- `RESULT pr=<PR> url=<URL>` → **confirm the PR exists**, then keep `<PR>` and
  continue:

  ```bash
  gh pr view <PR> --json number,state,headRefName
  ```

  Never skip it. A build has reported `pr=<N>` for a number the host 404s on,
  with its whole implementation sitting uncommitted in its worktree because the
  publish step never ran at all. A worker's `RESULT` is a claim; this is the one
  cheap command that turns it into a fact, and the only thing standing between a
  fabricated line and a reviewer sent after a PR that was never opened. (Change
  metadata is read per `docs/agents/code-host.md` on another host.)

  On a 404, **do not re-spawn the build** — the work is almost certainly intact
  in the worker's worktree. Recover the worker per **Resuming the orchestrator**
  step A: its spawn row holds the `agentId`, `ListAgents` says whether it is
  still alive, and **SendMessage** tells it what you found and to run its
  publish step for real, reporting only a number it has verified. If the worker
  is gone, escalate naming its branch and worktree, so nobody rebuilds on top of
  work that still exists.

### 3. Review

Spawn `diff-reviewer` with `isolation: "worktree"` and
`run_in_background: true`:

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
- `RESULT blocked reason=no new commits since the last review …` → the fix
  pass pushed nothing, so there is nothing to re-review. Treat it exactly as
  that cycle's `NEEDS_FIXES`: the previous findings still stand. Do not
  re-spawn the reviewer — go straight to the next fix cycle (or escalate if
  the budget is spent).
- `RESULT blocked` because the change branch is held by another worktree
  (the worker quotes git's "already used by worktree" error) → a previous
  worker's worktree wasn't cleaned: run **Cleanup** (step 6) and re-spawn
  the reviewer, **once per sub-issue** — if it blocks again, escalate.
- Any other `RESULT blocked` or malformed result → **escalate**, next
  sub-issue.

### 4. Fix cycle (max 3)

For cycle `c` = 1, 2, 3:

1. Fixer model: cycle 1 uses the build tier, each later cycle escalates one
   tier (sonnet → opus; opus stays opus). A sub-issue resumed straight
   into this step has no build tier — step 0 already set it to `opus`.
2. Spawn `code-author` with that model, `isolation: "worktree"` and
   `run_in_background: true`, then log the spawn row (Workers):

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
3. Re-review: spawn `diff-reviewer` again with the step 3 prompt plus
   `model: "sonnet"`, and append one line to it:

   > This is a re-review after fix cycle `<c>`. The skill's step 2 will scope
   > your diff to what landed since the last review — use that scope, and
   > check every previous finding was really fixed in code.

   Do not restate the findings in the prompt: they are on the PR, which is
   where the reviewer reads them.
   - `CLEAN` → **Merge**.
   - `NEEDS_FIXES` and `c < 3` → next cycle.
   - `NEEDS_FIXES` and `c = 3` → **escalate** (do NOT merge), next sub-issue.

### 5. Merge

**With `merge: manual`** (the factory default) there is nothing to merge:
you already marked the PR ready after the review, so record the sub-issue
as **ready-to-merge**, update its board task (`— ready to merge: PR #<PR>`),
run **Cleanup** (step 6), record its row (step 7), and move on. The sub-issue
stays open until the human merges, so its dependents remain blocked this run.

Say **how** to merge the **first** time a sub-issue becomes ready-to-merge —
a bare "ready to merge" leaves the user asking what to do, especially off
GitHub. State the code-host doc's merge operation concretely, in one line,
once for the whole run: the board carries every later PR, and the wrap-up
repeats the command.

**With `merge: auto`**: this merge is pre-authorized — the user opted into
`merge: auto` in `docs/agents/developer-defaults.md` (or passed
`--auto-merge` this run), which is standing authorization to merge PRs whose
review verdict is CLEAN. If the permission system still asks, say exactly
that; if it *denies*, follow the denial rule under Rules (escalate, never
retry).

**Checks gate — never merge on red CI.** If `docs/agents/code-host.md`
declares a CI system, wait for the PR's checks and read their result before
merging. **This is the step that opens `docs/agents/code-host-ci.md`** (that
doc's CI annex) if the repo has one — read it now, not at the start of the
run, and take its wait / read / classify operations from there. GitHub
default:

```bash
# 0. is the branch even mergeable? a conflicting PR never gets a check
gh pr view <PR> --json mergeStateStatus --jq .mergeStateStatus
# 1. wait until CI has attached at least one check to the current head sha
for _ in $(seq 20); do
  [ "$(gh pr view <PR> --json statusCheckRollup --jq '.statusCheckRollup | length')" -gt 0 ] && break
  sleep 15
done
# 2. then wait for them to finish — non-zero here means a check actually failed.
#    --watch repaints a progress table every 10s; keep all of it out of your
#    context and read the failures back only if the exit code says there are any.
gh pr checks <PR> --watch --fail-fast >/dev/null 2>&1 \
  || gh pr checks <PR> --json name,state,link \
       --jq '.[] | select(.state != "SUCCESS" and .state != "SKIPPED")'
```

Step 0 comes first and it decides whether the rest runs at all. On **`DIRTY`**
(GitHub's word for "conflicts with the base") the branch is unmergeable, the
host will not run checks against it, and steps 1–2 can only spend their five
minutes to report the absence: leave the gate now and take the conflict path —
the merge-fix job (`MERGE-FIX.md`), or the conflict queue in parallel mode —
then re-enter this gate from the top once the resolution is pushed. Field
evidence (spec #994): two PRs went `DIRTY` after a sibling merged, and each
burned the full wait to arrive at `no checks reported`, which the infra-red
rule below then reads as a CI that cannot start. Diagnosing a conflict as
infra-red escalates a healthy sub-issue and **ends the run** — the most
expensive misreading this gate can make, from a call that costs one second.

Step 1 is not optional either. `gh pr checks` exits non-zero for **two**
different reasons — a check failed, and *no check is registered yet* (`no checks reported
on the '<branch>' branch`) — and nothing downstream can tell them apart: the
classify step below needs a `<run-id>` that does not exist yet. The window is
real and you will hit it, because `gh pr update-branch` (the `BEHIND` path
below, and parallel mode's post-merge refresh) moves the head sha and CI takes
a few seconds to attach runs to the new one. Waiting for the checks to appear
turns that into a wait instead of a red.

Still no check after the loop's ~5 minutes, in a repo whose code-host doc
declares CI **and on a branch step 0 said was mergeable** → that is
**infra-red**: nothing ever picked the change up. Take the infra-red branch
below. A `DIRTY` branch is never infra-red, however long it waits — that is
step 0's whole job.

**Never open a command with a bare `sleep`** — the harness blocks it, here and
anywhere else in this skill. Wait inside an `until`/`for` loop like the one
above, or with the **Monitor** tool.

- **Green** (or the code-host doc declares no CI) → merge.
- **Red** → this is **not** a conflict (step 0 already ruled that out).
  First check whether the branch is merely **behind `main`** — a sibling
  merged after this branch was cut:

  ```bash
  gh pr view <PR> --json mergeStateStatus --jq .mergeStateStatus   # BEHIND?
  ```

  On `BEHIND`, run the code host's update-branch operation
  (`gh pr update-branch <PR>` on GitHub) and re-run this gate — **once per
  PR**; the red was synchronization, not a bug, and no fixer is needed.

  Still red on an up-to-date branch → **classify the red** before paying
  for a fixer, per the CI annex's classify-a-red operation. GitHub
  default (`<run-id>` comes from the failing check's `link`):

  ```bash
  gh run view <run-id> --json conclusion,jobs --jq '{run: .conclusion,
    failed: [.jobs[] | select(.conclusion != "success" and .conclusion != "skipped")
    | {name, steps: (.steps | length)}]}'
  ```

  - **Code-red** — a failed job executed steps (`steps > 0`): the change
    was exercised and failed. Before paying for a fixer, **retry the run
    once**:

    ```bash
    gh run rerun <run-id> --failed
    ```

    then re-enter this gate. Green → merge, and no fix cycle was spent.
    Red again → the failure is real: treat it as one more **fix cycle**
    (step 4), spawning the fixer with the failing job's URL appended to its
    prompt. The same three-cycle budget applies; exhausted → **escalate**.

    **Once per PR, and never twice.** A suite whose infrastructure wobbles —
    a service the tests dial refusing connections, an unhandled teardown
    error, a timeout — reds a change that is fine, and a fix cycle against
    it buys nothing; one retry is the cheapest way to find out, cheaper than
    a worker plus a review. But a retry *loop* merges a genuinely broken
    intermittent test by persistence, which is worse than spending the
    cycle. One retry, then believe it.
  - **Infra-red** — every failed job sits at `steps: 0`, the run concluded
    `startup_failure`, or no runner ever picked the job up: the code was
    never exercised, so there is nothing a fixer can fix. Spawn none.
    **Escalate** the sub-issue naming the cause (runner offline, CI
    minutes exhausted) and go to **wrap-up**: a CI that cannot start reds
    every later PR's gate identically, so continuing burns builds that
    cannot merge. The wrap-up's unblock question is one line: restore the
    CI (minutes, runner), then re-run `/developer <spec>`.
  - The CI annex defines no classify operation, or there is no annex and
    the code-host doc names none (or the host cannot tell) → every red is
    code-red, as before.

  **Never read CI logs in the main context.** The `--json` query above is the
  whole diagnosis you are allowed: `gh run view --log-failed`, `--log`, and
  any grep over them dump raw job output straight into the context this
  design exists to protect — the same rule as "never read issue or PR bodies
  yourself" (Context economy), and the reason the fixer is handed the failing
  job's URL instead of your reading of it. If the `--json` classification is
  not enough to decide, the answer is the retry above, then the fixer — never
  a closer look.

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
describes, then merge again. In parallel mode this conflict is also what
switches the wave to its **conflict queue** (Parallel mode, step 4) — the job
below is spawned for one PR at a time, never for every conflicting sibling at
once. That file also covers the conflict a human hits
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
to touch the primary checkout, keeps any worktree with uncommitted changes,
and deletes a branch only when its commits are on a remote — nothing it
deletes is ever the only copy of work. Every refusal is a `KEPT` line naming
its reason: treat those like `WARN` lines — carry them into the wrap-up
summary verbatim, and never re-run with broader flags or improvised git to
force what the script declined. If it finds the primary in detached HEAD
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
worktree. Its never-pushed branch comes back `KEPT (tip not on any remote)` —
that is the guard working, not a failure: the branch is the only copy of
whatever the build did. Leave it and report it.)

If the sub-issue was **merged**, also delete the remote branch now (the merge
deliberately skipped `--delete-branch`, and `cleanup-worktrees.sh` only ever
deletes *local* branches):

```bash
if git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
  git push origin --delete "$BRANCH"
else
  echo "remote branch already gone"
fi
```

Ask before you push: many hosts delete the head branch themselves on merge, and
against one of those a bare `git push origin --delete` fails with `remote ref
does not exist` on **every** merge of the run. That noise is indistinguishable
from a delete that failed for a reason worth knowing, which is the whole cost of
leaving it unguarded.

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
echo "$(date +%F) spec=#<spec> sub=#<N> model=<tier> effort=<effort> pr=#<PR> verdict=<CLEAN|—> cycles=<n> mergefix=<n> wave=<w|—> outcome=<merged|ready-to-merge|escalated>" \
  >> .scratch/developer-run-<spec>.log
```

(`effort=` is the reasoning effort the build ran at — the `code-author`
definition pins it (`medium` today), so copy that value; it exists so rows
stay comparable across runs if the pin ever changes. `mergefix=` counts the
merge-fix workers this PR needed — `0` for a PR that merged on its first
try. It is a separate number from `cycles=` because it prices a different
thing: `cycles` is the ticket being hard, `mergefix` is the *wave* being
expensive, and only that field lets a later calibration say "this spec's
tickets all rewrite the same files — deliver it sequentially". `verdict=—` /
`wave=—`
where the field does not apply — an escalated sub-issue that never got a
CLEAN, sequential mode. `pr=none` for a build that never opened one, and
`model=none effort=none pr=none cycles=0` for a sub-issue escalated as
`oversized`, which never reached a builder at all — that row is what lets
the harvest notice a spec whose tickets are systematically too big.)

Write it here and the wrap-up reads facts instead of recalling them: a run that
survives ten sub-issues, a context compaction, and a resume (step 0) still
reports the exact tier, PR and cycle count of the first one. The row is the
same one the wrap-up hands the harvest and the same one the chat summary
tabulates — write it once, correctly, now.

This row and the `event=spawned` rows from the Workers section share the file,
and the difference is the `outcome=` field: every row written here carries one,
no spawn row does. That is what the wrap-up filters on when it hands the
harvest the run's record, and what a resume filters on when it looks for
sub-issues still in flight.

The log is a run artifact, not tracked work: **never stage it**. The
context-docs publish (the top-level Step 0) and the local-tracker
`chore(tracker):` commits both name their own paths, so neither picks it up.

## Escalation

When a sub-issue is blocked, triaged **oversized** (under
`oversized: escalate`, and absent a no-split directive in its body),
non-convergent after 3
fix cycles, or unmergeable, apply the `ready-for-human` triage label to the
sub-issue and comment on both the sub-issue and the spec, per the tracker
ops. GitHub default:

```bash
gh issue edit <subissue> --add-label "ready-for-human"
gh issue comment <subissue> --body "Escalated by /developer: <reason>. PR: <url or none>."
gh issue comment <spec> --body "Sub-issue #<subissue> escalated: <one-line reason>."
```

**Escalating an `oversized` sub-issue**, the comment must carry the **fault
lines**, not just the verdict: the dispatcher already saw where the work
splits and said so in `hints=`. Pass those hints through verbatim — as the
seed of the re-cut, never as the partition itself: splitting a ticket is
design work, and the comment routes it to `/to-tickets` in a fresh session
with a high-tier model and high effort, the conditions the original cut was
made under. Say `PR: none` — nothing was built. GitHub default:

```bash
gh issue comment <subissue> --body "Escalated by /developer: oversized — does not fit in a single fresh context window.

Fault lines, from triage (a starting point, not the split): <the dispatcher's hints, verbatim>

To split it: run /to-tickets on this issue in a fresh session with a high-tier model and high effort, starting from the fault lines above. Then remove the \`ready-for-human\` label to put the new sub-issues in play. PR: none."
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
- **The agent docs are read-only to this pipeline.** `AGENTS.md`, `CLAUDE.md`,
  `CONTEXT-MAP.md`, `docs/adr/` and everything under `docs/agents/` are
  instructions the run obeys, not state it maintains — a run that rewrites its
  own instructions changes every future run, unattended and unreviewed. Two
  exceptions, both narrow: `docs/agents/delivery-ledger.md`, which the harvest
  appends to because the dispatcher reads it back (wrap-up step 2), and Step
  0's commit of context docs, which publishes edits **the human already made**
  and authors nothing. Everything else a run learns is *proposed* in the
  summary and applied by a human, or by `/setup-developer-skills` for the
  parts its templates own. This binds the workers too: say so in their prompts
  when a job goes anywhere near these files.
- Every worker spawn is `run_in_background: true`, in both execution modes.
  Never hold your turn open waiting for a worker to finish.
- Cap the output of every command you run, and never leave a watching or
  streaming command's progress unredirected — see **Context economy**. Your
  context is the one resource the whole run shares.
- In spec mode, keep the board current and say nothing beside it — no wave
  announcements, no triage tables, no running tallies. Six exceptions, all
  one-liners, listed under **Progress board**.
- While a run is in flight, no prompt that reaches you is a no-op — a bare
  "continue" is a resume, not a question. Reconstruct and take the next step
  per **Resuming the orchestrator**; never answer that no response is needed.
- Before rebuilding anything, check whether its worker is still alive
  (`ListAgents`) and resume it with **SendMessage**. Re-spawning a live
  worker's job pays twice for work that was never lost.
- Never act on a `RESULT pr=…` you have not confirmed exists — one `gh pr view`
  after every build, before the reviewer is spawned. A worker's report is a
  claim until you check it, and this is the only claim you can check for free.
- Each worker *starts* stateless: pass everything it needs in its prompt; never
  assume a fresh spawn can see prior steps. A worker resumed with SendMessage
  is the one exception — it still holds its own context.
- Never run `git checkout`, `git pull`, or any state-changing git command in
  the main context — the only exceptions are Step 0's scoped commit+push of
  context docs, the `cleanup-worktrees.sh` script (steps 6 and wrap-up),
  the merged-branch `git push origin --delete`, and — local tracker only —
  the scoped `.scratch/` tracker-write commits from `LOCAL-HOST.md`. If the
  script warns that the primary checkout is detached, report it — never
  repair it.
- Only spawn the fix worker when the review said `NEEDS_FIXES` or the
  checks gate found the change's CI **code-red** *and* the one retry it
  allows came back red too — an infra-red (the failing job never executed)
  escalates and ends the run instead.
- Retry a red CI run exactly once per PR, never twice, and never diagnose it
  by reading its logs in the main context.
- Never spawn a build for a sub-issue triaged `oversized` **under
  `oversized: escalate`** — escalate it with the fault lines instead. Buying
  it a stronger model is the one thing that does not work. Under
  `oversized: build`, or when the issue body forbids splitting, the ticket is
  built at `opus` and this rule does not apply.
- Never merge a change whose CI checks are red, whatever the merge policy
  and however unrelated the failing check looks.
- Never resolve merge conflicts in the main context — not even when the
  user hands you one interactively. That is always the merge-fix job's
  work, in its own worktree.
- Never run two merge-fix workers at once. Conflicting PRs drain through the
  conflict queue one at a time, each one's merge-fix spawned only after the
  previous PR is in `main` — parallel merge-fixes resolve against a `main`
  that the winner is about to move, so all but one are rewritten.
- Marking ready and merging are yours, never a worker's; posting the review
  is the reviewer's, never yours. Never author, edit, or amend review
  content in the main context.
- If a permission is denied — a worker reports one (posting the review,
  pushing, commenting), or your own code-host write is denied (marking
  ready, merging, …) — never re-run the denied action yourself or re-shape
  it into a different command: that is tunneling around the denial and will
  also be blocked. Treat the sub-issue as blocked: **escalate** it and
  continue the loop.
