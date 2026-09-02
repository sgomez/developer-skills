<!-- Template written to docs/agents/code-host.md by /setup-developer-skills (GitHub host). Drop this comment line. -->

# Code host: GitHub

Changes for this repo are delivered as **GitHub pull requests**, using the
`gh` CLI (it infers OWNER/REPO from `git remote -v`).

GitHub is the **factory default** of the delivery skills (`implement-issue`,
`review-pr`, `fix-pr`, `/developer`): every code-host operation they name —
publish a change, check out a change in a worktree, post a review, mark
ready, reply to threads, merge — already carries its `gh` mechanics inline
in the skill. **No overrides: follow the skills' inline commands as
written.**

Repo-specific facts:

- **Change ref**: the PR number.
- **Base branch**: `main`. Start work from `origin/main`
  (`git fetch origin main && git checkout -b <branch> origin/main`) —
  never `git checkout main`.
- **Issue auto-close**: yes — `Closes #<n>` in the PR body closes issue
  `#<n>` when the PR merges, **provided the issue lives in this repo's
  GitHub Issues**. If this repo's issues live elsewhere (see
  `docs/agents/issue-tracker.md`), there is no auto-close: reference the
  issue in the PR body by its tracker ref, and close it per the tracker's
  Delivery operations after the merge.
- **Merge policy support**: both `merge: auto` and `merge: manual`.
- **Publishing commits**: `git push origin <branch>` (from a local
  `fix/pr-<PR>` branch: `git push origin HEAD:<pr-branch>`).
- **CI**: GitHub Actions runs on pull requests. How to wait for the checks,
  read the ones recorded for a head sha, and tell a code-red from an
  infra-red lives in the annex [`code-host-ci.md`](./code-host-ci.md) —
  **open it only when you are about to do one of those three things**, which
  for most jobs is never. <!-- Set to "none" if this repo has no CI on PRs,
  and delete the annex; the pipeline then skips the CI operations entirely
  and behaves exactly as it did before they existed. -->

## Read the last reviewed revision

The reviewer, to settle its scope (`review-pr` step 2) — GitHub records the
sha each review was submitted against:

```bash
gh api "repos/{owner}/{repo}/pulls/<PR>/reviews" \
  --jq 'map(select(.state != "PENDING")) | last | .commit_id // empty'
```

Empty = never reviewed (full scope). Otherwise the sha anchors the
incremental diff, once `git merge-base --is-ancestor <sha> HEAD` confirms the
branch was not rewritten under it.

## Is the change mergeable?

Read before waiting on anything (the orchestrator, at the top of its checks
gate):

```bash
gh pr view <PR> --json mergeStateStatus --jq .mergeStateStatus
```

`DIRTY` = conflicts with the base: GitHub runs **no checks** against it, so
waiting for one can only time out. It is a conflict, never a red and never an
un-startable CI — take the merge-fix path. `BEHIND` = mergeable but stale
(`gh pr update-branch <PR>`). `CLEAN`/`UNSTABLE`/`BLOCKED` = the checks are
the question — that is the point where the CI annex gets opened, and not
before.

<!-- Keep this file under ~100 lines. Every worker reads it whole in its first
turn, before looking at a line of code, so anything used in only one phase of
a job belongs in an annex that names its trigger — as the CI operations do. -->
