# Merge-fix job

Read this file at the **first merge conflict** of a run — not before. It holds
the merge-fix job's spawn prompt and the two situations that call for it.

## When to dispatch it

1. **A merge you ran failed** (pipeline step 5) because the change conflicts
   with a previously merged one. In parallel mode this is routine, not
   exceptional: every wave member branched from the same `main`, so any change
   merged after the first may conflict. Budget **one merge-fix per conflicting
   change** before escalating.
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
queue** (SKILL.md, Parallel mode, step 4), and this job is spawned only for
the PR at the head of it, only after the previous PR is merged. Before
spawning, always **try the plain merge again first**: the PR that just merged
often carried the conflict away with it, and `gh pr update-branch` handles most
of what is left for free. Only a merge that actually fails earns a worker.

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
> `git fetch origin pull/<PR>/head:fix/pr-<PR> && git checkout fix/pr-<PR>`
> — do not use `gh pr checkout` or check out the branch by name, it is
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

When it reports, check the base **before** merging:

```bash
git ls-remote origin main        # still BASE?
```

- **`main` is still at BASE** → merge the PR. If that merge fails again, the
  resolution was genuinely wrong: **escalate**.
- **`main` has moved** (another PR merged while the worker ran) → the
  resolution is stale through no fault of the worker. Try
  `gh pr update-branch <PR>` and merge; if it still conflicts, spawn the job
  once more against the new base. **A stale-base failure does not consume the
  one-retry budget** — that budget counts attempts against an unchanged
  `main`, and burning it on a moving base escalates PRs that had nothing
  wrong with them. Two consecutive stale bases mean something else is merging
  behind your back: stop, and say so.

On a **local code host** the worker rebases onto local `main` in its worktree;
committing is publishing, there is nothing to push.
