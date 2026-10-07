# Merge-fix job

Read this file at the **first merge conflict** of a run — not before. It holds
the merge-fix job's spawn prompt and the two situations that call for it.

## When to dispatch it

1. **The change conflicts with `main`** (pipeline step 5): its checks gate
   said `DIRTY`, or a merge you ran after a `GREEN` gate failed. In parallel
   mode this is routine, not exceptional: every wave member branched from the
   same `main`, so any change merged after the first may conflict. Budget
   **one merge-fix per conflicting change** against an unchanged `main`
   before escalating.
2. **The human's own merge hit a conflict** under `merge: manual` — mid-run or
   after wrap-up — and they bring it to you. Never resolve it in the main
   context: that fills the context this pipeline exists to protect. Have them
   abort the half-merge (`git merge --abort`), dispatch the job below, run
   **Cleanup** (pipeline step 6) when it reports, and tell them to retry the
   merge, which is now conflict-free.

A merge that fails **before** the change's CI checks are green is not a
conflict — see the Merge step's checks gate; fix the red checks first.

## One at a time, always

**At most one merge-fix worker may be alive in the whole run.** A merge-fix
resolves the branch against `main` *as it is right now*; the moment any other
PR merges, that resolution describes a `main` that no longer exists and the
work is thrown away. Running three of them concurrently does not deliver three
PRs — it delivers one and queues two rewrites.

So in parallel mode the first conflict switches the wave to the **conflict
queue** (below), and this job is spawned only for the PR at the head of it,
only after the previous conflicting PR is merged. Before spawning, always **try the plain
merge again first**: the PR that just merged often carried the conflict away
with it, and `gh pr update-branch` handles most of what is left for free. Only
a merge that actually fails earns a worker.

## The conflict queue (parallel mode)

The first conflict of a wave — a `DIRTY` from the checks gate, or a failed
merge — opens the wave's conflict queue. Conflicts are not independent work:
every conflicting PR resolves against the same `main`, and the first one
merged invalidates every resolution computed beside it. So the PRs that
conflict — and only those — form a queue, oldest-PR-first, that drains **one
at a time**:

- **At most one merge-fix worker is alive in the whole run**, whatever the
  worker cap allows.
- A PR's merge-fix is spawned **only when that PR is at the head of the
  queue** — after the previous queued PR is in `main`. Until its turn a queued PR
  gets no merge-fix worker; its conflict is work not yet started.
- When the head PR merges, drop it and run the next one's checks gate before
  assuming it still conflicts: the winner's merge plus an update-branch
  resolves most of the rest for free. Only a merge that actually fails, or a
  gate that still says `DIRTY`, earns a merge-fix worker.
- **Never hold a `GREEN` sibling for the queue.** A PR that is not in it —
  its gate never said `DIRTY` — merges the moment its gate says `GREEN`,
  merge-fix running or not. Holding it buys nothing: a merge that does not
  conflict with the rebased branch leaves that branch merely behind, which
  its gate absorbs, and a merge that does conflict would have conflicted just
  the same an hour later. On spec #964 holding two green PRs behind one
  merge-fix cost ten minutes and a second gate. If siblings are already
  `GREEN` when the head PR's turn comes, merge them first and spawn the
  merge-fix after: it then rebases onto a `main` that has stopped moving.
- Everything that is not the merge path — builds, reviews, review fix cycles,
  including a queued PR's own — carries on in parallel underneath. The queue
  serializes conflict resolution, not the wave.

Say the switch out loud once, in one line, e.g. `#936 conflicts — wave
finishing through the conflict queue: #936 → #937 → #938.`

## The job

Record the base first — you need it to tell a stale resolution from a real
second failure:

```bash
git ls-remote origin main        # remember this sha as BASE
```

Spawn a `code-author` with model `opus`, `isolation: "worktree"` and
`run_in_background: true`, then log the spawn row (SKILL.md, Workers) with
`job=fix`:

> MERGE-FIX job. PR #`<PR>` cannot be merged into main (conflict with a
> previously merged PR). In your worktree get the PR branch per the
> fix-that-pushes checkout in `docs/agents/code-host.md` (GitHub default:
> `git fetch origin pull/<PR>/head:fix/pr-<PR>`, then
> `git checkout fix/pr-<PR>` as a separate call — never joined with `&&`,
> which the worktree sandbox refuses; do not use `gh pr checkout` or check out the branch by name, it is
> checked out in the build worker's worktree and git will refuse). If git
> also refuses `fix/pr-<PR>` — an earlier fix cycle's worktree still holds
> it — use `fix/pr-<PR>-merge` in both commands; never any other name, the
> cleanup matches on `fix/pr-<PR>*`.
>
> Then `git fetch origin main` and **rebase the branch onto `origin/main`**
> (`git rebase origin/main`), resolving the conflicts as they come — using
> the `resolving-merge-conflicts` skill if it appears in your available
> skills. Rebase, not a merge of main into the branch: the PR's diff has to
> stay the PR's own work, and a merge commit drags the whole of `main` into a
> diff the reviewer already read. If the rebase turns out to be the wrong
> shape for this branch (it has merge commits of its own, or the same hunk
> conflicts on every one of a long chain of commits), `git rebase --abort`,
> merge `origin/main` in instead, and say which you did in your RESULT line.
>
> Run the project checks, then push with
> `git push --force-with-lease origin HEAD:<pr-branch>` (a plain push after a
> rebase is rejected; `--force-with-lease` refuses if anyone else moved the
> branch, which is the safety you want). If you merged instead of rebasing,
> push without the force flag (and note that a force-push marks the code
> host's already-posted inline review threads as outdated — that is expected
> here, not something to repair). Your entire final message must be the
> `RESULT pr=… url=… base=<the sha you rebased onto> strategy=<rebase|merge>`
> line — nothing before it, nothing after it.

When it reports, check the base **before** anything else:

```bash
git ls-remote origin main        # still BASE?
```

The worker pushed a new head, so every path below goes through the **checks
gate** (SKILL.md, step 5) before any merge — never merge straight after a
merge-fix.

- **`main` is still at BASE** → run the gate. `DIRTY` again, or a merge
  after `GREEN` that fails again, means the resolution was genuinely wrong:
  **escalate**.
- **`main` has moved** (another PR merged while the worker ran — usually a
  `GREEN` sibling of this run) → run the gate. A `GREEN` or `BEHIND` means
  the move did not touch the resolution; `BEHIND` takes an update-branch as
  usual. Only a `DIRTY` makes the resolution stale through no fault of the
  worker: spawn the job once more against the new base. **A stale-base
  failure does not consume the one-retry budget** — that budget counts
  attempts against an unchanged `main`, and burning it on a moving base
  escalates PRs that had nothing wrong with them. Two consecutive stale bases
  that **none of this run's merges explain** mean something else is merging
  behind your back: stop, and say so.

On a **local code host** the worker rebases onto local `main` in its worktree;
committing is publishing, there is nothing to push.
