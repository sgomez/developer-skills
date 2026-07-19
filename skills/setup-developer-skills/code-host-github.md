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
- **CI**: GitHub Actions runs on pull requests. <!-- Set to "none" if this
  repo has no CI on PRs; the pipeline then skips both checks below and
  behaves exactly as it did before they existed. -->

## Checking the change's CI status

Two operations read the same checks, for two different readers.

- **Wait for the checks and gate the merge** (the orchestrator, before
  merging):

  ```bash
  gh pr checks <PR> --watch --fail-fast   # exits non-zero if any check fails
  ```

  A non-zero exit is **not** a merge conflict: it is a red build, and the
  answer is another fix cycle, never a merge-fix job.

- **Read the checks already recorded for the head sha** (the reviewer, before
  deciding whether to run the suite locally):

  ```bash
  gh pr checks <PR> --json name,state,link --jq \
    '[.[] | select(.state != "SUCCESS" and .state != "SKIPPED")]'
  ```

  Empty output with at least one check present = green. Any entry is a
  failing or still-running check; its `link` is the job URL to quote.
