# Wrap-up

Read this file when the loop is over — no deliverable sub-issue remains (all
closed or ready-to-merge, or the rest are blocked by escalated/unmerged ones).
It runs **once per run**; nothing here is needed while sub-issues are still in
flight.

With a **local** tracker or code host, `LOCAL-HOST.md` (already read at the
start of the run) overrides the harvest push, the sweep flags, and the merge
commands in the summary.

## 1. Reconcile the task board

Every task must be completed or renamed per the Progress board rules — nothing
left silently in_progress.

## 2. Harvest discoveries and record the run

Turn what the workers learned into docs, and persist this run's outcome so the
dispatcher can calibrate to this repo. Skip only when the run produced no
changes. The harvest worker does both in one branch/commit; the **ledger rows**
it needs are already written — read them, do not reconstruct them:

```bash
cat .scratch/developer-run-<spec>.log
```

Pass those lines **verbatim**. Each terminal transition wrote its own row
(delivery pipeline step 7), so this file is the run's record even where your
own recall has been compacted away. Only if a sub-issue you know went terminal
has no row — a step 7 that was denied or interrupted — write that one row now,
from what you still hold, and say so in the chat summary.

Distill your own **calibration notes** before spawning the harvest: one line
per sub-issue whose tier proved wrong in either direction this run — cost far
above or below its tier (tokens, tool calls, wall-clock), a pattern the triage
assumed missing that was already merged (or vice versa), a worker that broke
worktree discipline. The ledger rows carry outcomes; these lines carry the
*mechanism*, which the rows cannot express and which is gone once your context
is. `none` when the run priced cleanly.

Spawn one `code-author` with `model: sonnet` and `isolation: "worktree"`:

> HARVEST job. This run delivered PRs #`<list every PR of the run — merged,
> ready-to-merge, or escalated>`. Create branch `agent/harvest-<spec>` from
> origin/main, then do two things on it:
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
> that tier, or issues of a given shape scored `complex` but came back
> `oversized` from triage. Each bullet names the signal and the corrected
> tier (the dispatcher reads them on top of its generic rubric). Change
> nothing there if no pattern is evident yet; never invent a rule from a
> single row on its own. The orchestrator watched this run and its notes
> below carry mechanism the rows cannot — a single row **plus** a note
> naming a structural cause (the pattern did not exist yet; a tier's model
> broke discipline) is enough for a bullet, statistics need repetition but
> mechanisms do not:
>
> ```
> <your calibration notes, verbatim, or none>
> ```
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
> fails, stop and report it. Your entire final message must be the
> `RESULT docs=<updated|none> ledger=<appended|failed>` line — nothing
> before it, nothing after it.

On `ledger=appended`, delete the run log (`rm .scratch/developer-run-<spec>.log`):
its rows now live in the committed ledger, and a stale log would re-append them
the next time this spec runs. On any other result, leave it — it is the only
copy.

This job is best-effort: if it reports blocked, note it in the summary and move
on.

## 3. Final sweep

One last pass of the cleanup script, catching the harvest worktree and anything
a half-failed pipeline left behind — including reviewer worktrees detached at
shas that later fix cycles superseded, and worker branches with improvised
names: the sweep removes every worker worktree under `.claude/worktrees/` by
path, branch or detached.

```bash
bash <skill-dir>/scripts/cleanup-worktrees.sh --sweep
```

Trust the script's final line, not your expectation of it. Claim a clean
sweep only on `leftover=0`; if it prints `LEFTOVER` lines, those worktrees
survived the pass — include them verbatim in the chat summary. If it prints
a `WARN` line (primary checkout detached, or sitting on a worker branch),
include it verbatim too — never repair the primary checkout yourself.

The sweep deletes only the branches of the worktrees it removes in this pass;
it will not reap worker-named branches left over from other runs. If it exits
non-zero with an `ABORT` line, its `--max-branches` safety cap tripped: it
removed the worktrees but deleted **no** branches (nothing was lost — the
branches still hold their commits). Do not blindly re-run with a higher cap —
paste the `WOULD-DELETE` list into the summary and leave the branches for the
human, unless every one is unmistakably this run's own work.

If the permission system **denies the sweep** (its pattern-matched removal can
trip the auto-mode classifier), do not retry it: check `git worktree list`, and
if leftovers remain run targeted `--branch`/`--sha` passes for the sub-issues
this run delivered — the same shape already used in pipeline step 6. Nothing
left → just note the denial and move on.

## 4. Close the spec

A spec whose sub-issues are all delivered is itself done; leaving it open makes
the tracker lie. Re-enumerate the spec's children per the tracker ops (the same
operation as Mode detection — never trust the run's own bookkeeping alone:
sub-issues may have been closed before this run or outside it). If **every**
sub-issue is CLOSED, close the spec per the tracker ops with a comment. GitHub
default:

```bash
gh issue close <spec> --comment "Closed by /developer: all <N> sub-issues delivered and merged."
```

If any sub-issue is still open (ready-to-merge under `merge: manual`,
escalated, or blocked), leave the spec open and say why in the chat summary.
Skip this step in single mode when the issue itself was the spec — it already
closed on merge.

## 5. Push notification

Via the PushNotification tool:
`Spec #<spec>: <N> merged, <M> escalated, <K> still blocked.` — with
`merge: manual`, use
`Spec #<spec>: <N> ready to merge, <M> escalated, <K> still blocked.`
If step 4 closed the spec, use
`Spec #<spec> completed and closed: <N> sub-issues merged.`

## 6. Chat summary

One table, built from the run log's rows: sub-issue, model used, PR, fix
cycles, wave (parallel mode), outcome.

List escalated sub-issues with reasons, and say how to put one back in play:
**remove its `ready-for-human` label and re-run `/developer <spec>`** — the
label is the only thing holding it out of the pick, and the re-run resumes
whatever change it already has instead of building a second one. For a
sub-issue escalated as **oversized**, its escalation comment already carries
the fault lines and the route — `/to-tickets` in a fresh session with a
high-tier model and high effort — point the human at it: splitting the
sub-issue is what unblocks it, removing the label alone just re-runs the same
wall.

When anything escalated, **end the summary with the decisions themselves**:
one direct question per escalated sub-issue, phrased so a one-line reply
unblocks it — "close #363 as a duplicate of #349, or narrow it to a remaining
gap?", "re-cut #368 with /to-tickets along the fault lines in its escalation
comment?". You already know exactly
what each escalation is waiting on; do not make the human interview you to
find out.

With `merge: manual`, list the ready-to-merge changes **in dependency order** —
that is the human's merge queue, and merging in that order minimizes conflicts
— and give the **exact commands** per the code-host doc's merge operation. End
the queue with its final step: once the last sub-issue is closed, close the
spec itself per the tracker ops (`gh issue close <spec>` on GitHub). Sibling
changes branched from the same `main` may conflict on merge — say so, and point
at the escape hatch: abort the half-merge and ask you to run the **merge-fix
job** (`MERGE-FIX.md`) on that change; a worker resolves it in its own
worktree, never the main context.

Note whether the harvest updated docs.

## 7. Execution report

How the run actually unfolded. In parallel mode, one line per wave listing the
jobs that ran concurrently and their outcomes, e.g. `Wave 2: #12 ∥ #14 ∥ #15 —
2 merged, 1 escalated, 1 merge-fix on #14`. In sequential mode, the delivery
order with any merge-fix jobs noted.
