# Resuming the orchestrator

Read this file when a prompt reaches you while a run is in flight and it is
**not** a worker's result you were waiting for — a bare `Continue from where
you left off.`, an empty continuation, a notification you believe you already
handled, or a session that was interrupted, compacted or restarted. It is not
read on a normal run.

(This is the orchestrator's own resume. Pipeline step 0 in SKILL.md is the
per-sub-issue one — it is what step B below runs.)

1. **Rebuild the picture** from the three places that survive a dead context,
   never from recall:
   - the progress board (**TaskList**) — which sub-issues are `in_progress`;
   - `.scratch/developer-run-<spec>.log` — the terminal rows already recorded
     (they carry `outcome=`), and the `event=spawned` rows naming the worker
     that was running on each sub-issue still in flight. If a wrap-up already
     ran this spec, the rows from before it are in
     `.scratch/archive/developer-run-<spec>-*.log`;
   - **ListAgents** — which of those workers are still alive.
2. **Recover each non-terminal sub-issue** in this order, stopping at the first
   that works:

   **A. Its worker is still alive** → **SendMessage** to its `agentId` and ask
   it to report. Its context, worktree and commits are intact, so this
   continues the job instead of repeating it — the cheapest recovery, and the
   only one that keeps work already paid for. A worker that finished while you
   were not looking answers here too, with the `RESULT` you missed.

   This works for `code-author`. It usually does not for `diff-reviewer`: a
   review changes no files, so its worktree is removed when it ends and a
   reviewer missing from `ListAgents` is gone for good. Try it if listed;
   otherwise go to B — a review is cheap to repeat, a build is not.

   **B. Its worker is gone** → run pipeline **step 0** on that sub-issue
   exactly as written. It asks the code host rather than your memory, and
   routes the sub-issue to Review, to the Fix cycle, or back to Build when
   nothing was ever opened for it.
3. **Re-enter the loop**: recompute the unblocked set (spec loop step 1, or
   the wave in parallel mode) and carry on. Nothing left → **Wrap-up**.

Say in one line what you recovered and how, before continuing. During an
unattended run the board and that line are the user's whole window into it.
