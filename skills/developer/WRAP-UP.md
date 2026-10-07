# Report

Read this file when the workflow's completion notification arrives. The
workflow already did the wrap-up work — harvest and ledger, final sweep,
closing the spec — and its result object holds everything below:
`subIssues` (number, title, blockers, outcome, reason, pr, model, cycles,
mergefix, wave, notes), `specPr` on a spec delivered on its integration
branch (pr, branch, outcome, reason, cycles, mergefix, notes), `harvest`,
`wrapUp` (the sweep's lines and whether the spec closed), or `error` when the
plan refused to start.

On the integration branch a sub-issue's `integrated` outcome means its PR
merged into `developer/spec-<N>`, not into `main`; the sub-issue stays open
until the spec PR merges. `specPr.outcome` is what reached `main`: `merged`,
`ready-to-merge`, `escalated`, or `draft` (sub-issues still undelivered, so
neither reviewed nor merged).

With a **local** tracker or code host, `LOCAL-HOST.md` gives the merge
commands for the summary.

## 1. Push notification

Via the PushNotification tool:
`Spec #<spec>: <N> merged, <M> escalated, <K> still blocked.` — with
`merge: manual`, use
`Spec #<spec>: <N> ready to merge, <M> escalated, <K> still blocked.`
If the spec was closed, use
`Spec #<spec> completed and closed: <N> sub-issues merged.`
On the integration branch, count sub-issues as `integrated` and say what
happened to the spec PR: `Spec #<spec>: <N> integrated, spec PR #<pr>
<merged | ready to merge | escalated | left as draft>.`

## 2. Chat summary

One table: sub-issue, model, PR, fix cycles, merge-fixes, wave (parallel
mode), outcome. With a `specPr`, a last row for it: the spec PR, its fix
cycles (the whole-spec review's), merge-fixes, outcome. When `mergefix` is non-zero on much of the run, say so in a
line under the table — the sub-issues were rewriting the same files, and that
is the run's own evidence for delivering the next spec of that shape
sequentially.

Carry `notes` (cleanup `KEPT`/`WARN` lines) and `wrapUp` verbatim where they
report anything but a clean sweep: `LEFTOVER`, `KEPT`, `WARN`, `ABORT`
lines, or a denied sweep. `held=<n>` is a worker still alive, not a leak.
Never repair the primary checkout yourself.

List escalated sub-issues with reasons, and say how to put one back in play:
**remove its escalation label and re-run `/developer <spec>`** — the re-run
resumes whatever change it already has instead of building a second one.
Sub-issues the run never started (`blocked`) are listed with their blocker.

When anything escalated, **end the summary with the decisions themselves**:
one direct question per escalated sub-issue, phrased so a one-line reply
unblocks it — "close #363 as a duplicate of #349, or narrow it to a remaining
gap?", "re-cut #368 with /to-tickets — three fix cycles never converged?".

With `merge: manual` and a `specPr` ready to merge, the human's queue is that
one PR: give its merge command, and say the spec and its sub-issues close
with it. Without one, list the ready-to-merge changes **in dependency order**
(from `blockers`) — that is the human's merge queue — and give the **exact
commands** per the code-host doc's merge operation. End the queue with
closing the spec once its last sub-issue is closed (`gh issue close <spec>`
on GitHub). Sibling changes branched from the same `main` may conflict on
merge — point at the escape hatch: abort the half-merge and ask you for the
merge-fix job (SKILL.md, step 3).

**Proposed doc changes.** `harvest.reason` carries `discoveries=<n>`. On
`n > 0`, read `.scratch/developer-discoveries-<spec>.md` and list each entry:
title, target doc, the one-line edit. They are proposals — no agent doc was
modified by this run, and say so. On `0`, one line: nothing worth promoting.
A harvest that did not report `ledger=appended` leaves the run log in
`.scratch/` — say so.

## 3. Execution report

In parallel mode, one line per wave (dependency depth) listing its
sub-issues and outcomes, e.g. `Wave 2: #12 ∥ #14 ∥ #15 — 2 merged, 1
escalated, 1 merge-fix on #14`. A sub-issue starts as soon as its own
blockers merge, so waves overlap; they describe the dependency shape, not
time slots. In sequential mode, the delivery order with any merge-fixes.
