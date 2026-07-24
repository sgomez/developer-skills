# Local host / local tracker — standing adjustments

Read this file **once, at the start of the run**, when
`docs/agents/issue-tracker.md` or `docs/agents/code-host.md` says the tracker
or the code host is **local** (files in the repo, no remote). Every adjustment
below is standing: it applies for the whole run, on top of the main SKILL.md.

A run on a remote host (GitHub, GitLab) never needs this file.

## Which adjustments apply

- **Local tracker** — issue files live in `.scratch/`: the Step 0 and
  tracker-write rules below.
- **Local code host** — changes are branch + change file: the branch
  discipline, mark-ready, merge, cleanup and wrap-up rules below.
- Both may be true at once; a local code host implies `merge: manual`.

## Capability overrides

- **Unattended merge is not supported.** If the resolved run config says
  `merge: auto`, override it to `manual` and say so in the run-config line.
- **Issues do not auto-close on merge.** You close the delivered issue
  yourself per the tracker ops right after verifying the merge.

## Tracker writes are yours

Tracker writes (comments, `Status:` changes) are made by you in the primary
checkout, scoped to `.scratch/` paths, committed as `chore(tracker): …` — an
extension of Step 0's exception to the never-touch-git-state rule.

## Step 0 — publishing context docs

Add `.scratch` to the paths of both the `git status --porcelain` check and the
`git add`: the tracker and change files live there and workers read them
through their own checkout.

There is no remote, so there is no push: the commit alone publishes, since
linked worktrees share the repo.

## Delivery pipeline — branch discipline (structural, not optional)

On a local host every worker checks out the change branch itself, and git
allows a branch in only **one** worktree — but a worker's worktree outlives it
whenever it holds changes, which a build or fix worktree always does. So run
**Cleanup** (pipeline step 6, always `--keep-branches`) after **every** worker
reports and before spawning the next one:

```
build → cleanup → review → cleanup → fix → cleanup → re-review
```

Skipping one makes the next worker report blocked on "branch already used by
worktree". (Remote hosts are immune: reviewers fetch the change head from the
remote instead.)

A `KEPT worktree … dirty` line from that cleanup means the worker left
uncommitted changes behind — the script never removes those, so the branch
stays held and the next worker on it will report blocked. That is a worker
discipline failure, not a cleanup failure: escalate the sub-issue rather
than removing the worktree by hand.

## Pipeline step 3 — mark ready

Skip the mark-ready call entirely: the reviewer's change-file commit already
carries `Status: ready`.

## Pipeline step 5 — merge

`merge` is always `manual` here, so the pipeline's terminal state is
ready-to-merge. State the merge commands concretely the moment a sub-issue
gets there:

```bash
git merge --no-ff <branch>
git branch -d <branch>
# then close the issue per the tracker ops (no auto-close on a local host)
```

For the **merge-fix job** (a conflict the human hits on their own merge), see
`MERGE-FIX.md`: on a local host the worker merges local `main` into the branch
in its worktree, and committing is publishing — there is nothing to push.

## Pipeline step 6 — cleanup

- The change ref *is* the branch, and `git rev-parse <branch>` gives the head
  sha — no `gh pr view` calls.
- Always pass `--keep-branches`: the local branch is the only copy of unmerged
  work, so only the worktrees go.
- Skip the `git push origin --delete` on a merged sub-issue — there is no
  remote branch.

## Wrap-up

- **Harvest** — there is no remote to push through, and `main` may never be
  moved unattended: instruct the harvest worker to leave its commit on the
  `agent/harvest-<spec>` branch instead, and list that branch in the wrap-up as
  one more item in the human's merge queue.
- **Final sweep** — `--sweep --keep-branches`; unmerged local branches are the
  only copy of the work.
- **Chat summary** — the merge queue's commands are the local ones above
  (`git merge --no-ff <branch> && git branch -d <branch>`, then close each
  issue per the tracker ops).
