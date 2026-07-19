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

## The job

Spawn a `code-author` with model `opus` and `isolation: "worktree"`:

> MERGE-FIX job. PR #`<PR>` cannot be merged into main (conflict with a
> previously merged PR). In your worktree get the PR branch per the
> fix-that-pushes checkout in `docs/agents/code-host.md` (GitHub default:
> `git fetch origin pull/<PR>/head:fix/pr-<PR> && git checkout fix/pr-<PR>`
> — do not use `gh pr checkout` or check out the branch by name, it is
> checked out in the build worker's worktree and git will refuse). If git
> also refuses `fix/pr-<PR>` — an earlier fix cycle's worktree still holds
> it — use `fix/pr-<PR>-merge` in both commands; never any other name, the
> cleanup matches on `fix/pr-<PR>*`. Merge
> `origin/main` into it, resolve the conflicts — using the
> `resolving-merge-conflicts` skill if it appears in your available skills —
> run the project checks, and push with
> `git push origin HEAD:<pr-branch>`. Your entire final message must be the
> `RESULT pr=… url=…` line — nothing before it, nothing after it.

Then merge again. If it still fails, **escalate**.

On a **local code host** the worker merges local `main` into the branch in its
worktree and commits — committing is publishing, there is nothing to push.
