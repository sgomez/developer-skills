<!-- Template written to docs/agents/code-host.md by /setup-developer-skills (local host). Drop this comment line. -->

# Code host: Local (no remote)

This repo has no remote code host. A "PR" is a **local branch plus a change
file** committed on it; reviews and thread replies live in that file. The
`gh` commands shown inline in the delivery skills are the GitHub factory
defaults — **the operations below override them.**

- **Change ref**: the branch name (e.g. `agent/issue-03-user-auth`).
- **Change file**: `.scratch/changes/<branch-with-slashes-as-dashes>.md`,
  committed on the branch. It holds everything a PR would: a `Status:` line
  (`draft` / `ready` / `merged`), the issue ref it closes, `## What changed`,
  `## Test plan`, optional `## Discoveries`, and appended `## Review N`
  sections.
- **Base branch**: `main`. Linked worktrees share refs with the primary
  checkout, so `git fetch origin` is meaningless here — branch from local
  `main`: `git checkout -b <branch> main` (never `git checkout main`).
- **Publishing commits**: committing **is** publishing — branches and
  commits made in a worktree are immediately visible to the whole repo.
  There is nothing to push.
- **Merge policy support**: **`merge: manual` only.** `main` is checked out
  in the primary worktree, and no unattended process may move it under the
  user's feet. A CLEAN change is recorded ready-to-merge; the human merges
  with `git merge --no-ff <branch>` and then deletes the branch.
- **Worktree/branch discipline (orchestrator)**: the branch is the **only
  copy** of unmerged work — always pass `--keep-branches` to
  `cleanup-worktrees.sh`, and run that cleanup **after every worker
  reports** (not just at sub-issue end) so the branch is free for the next
  worker to check out directly.

## Operations

- **Publish a change**: create the change file on the branch with
  `Status: draft` and commit it (`chore(change): open change file for
  <branch>` or fold it into the implementation commit).
- **Change metadata**: branch = the ref itself; head sha =
  `git rev-parse <branch>`; state = `Status:` line in the change file
  (`git show <branch>:.scratch/changes/<file>.md`).
- **Check out a change in a linked worktree (review and fix)**: the
  orchestrator has already cleaned the previous worker's worktree, so the
  branch is free: `git checkout <branch>`. If git refuses because the
  branch is still held by another worktree, report blocked — do not
  improvise.
- **Read the diff**: `git diff main...HEAD`.
- **Read feedback**: read the change file's `## Review N` sections. A
  finding is an unchecked `- [ ]` item; `- [x]` with an indented reply is
  resolved.
- **Post a review**: append a `## Review N` section to the change file —
  one `- [ ] \`<file>:<line>\` — <finding>` item per actionable finding,
  then a summary paragraph (non-blocking notes included; start it with
  "CLEAN" when nothing blocks). Commit **only the change file** — the one
  write a reviewer is allowed.
- **Mark ready**: set `Status: ready` in the change file (same commit as
  the review).
- **Reply to a thread**: under the finding, append an indented
  `> Fixed in <short-sha>: <what changed>` and tick the box to `- [x]`.
  Commit along with the fixes.
- **Comment on a change**: append under a `## Comments` heading at the
  bottom of the change file.
- **Merge**: never unattended (see above). Ready-to-merge is the terminal
  state; the human merges and deletes the branch.
- **Issue auto-close**: no. Reference the issue ref in the change file
  ("Closes <ref>" line); whoever merges closes the issue per the tracker's
  Delivery operations.
