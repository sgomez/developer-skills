<!-- Template written to docs/agents/code-host.md by /setup-developer-skills (GitLab host). Drop this comment line. -->

# Code host: GitLab

Changes for this repo are delivered as **GitLab merge requests**, using the
[`glab`](https://gitlab.com/gitlab-org/cli) CLI (it infers the project from
`git remote -v`). Wherever a delivery skill says "PR", read "MR"; the `gh`
commands shown inline in the skills are the GitHub factory defaults — **the
operations below override them**.

- **Change ref**: the MR number (`!42` — GitLab numbers issues and MRs
  separately, so it never collides with an issue `#42`).
- **Base branch**: `main`. Start work from `origin/main`
  (`git fetch origin main && git checkout -b <branch> origin/main`) —
  never `git checkout main`.
- **Merge policy support**: both `merge: auto` and `merge: manual`.
- **Publishing commits**: `git push origin <branch>` (from a local
  `fix/mr-<MR>` branch: `git push origin HEAD:<source-branch>`).

## Operations

- **Publish a change**: push the branch, then
  `glab mr create --draft --source-branch <branch> --target-branch main --title "..." --description "..."`.
  Use a heredoc for multi-line descriptions.
- **Change metadata**: `glab mr view <MR> -F json` — fields `iid`, `title`,
  `source_branch`, `sha` (head), `state`, `draft`.
- **Check out a change in a linked worktree (review, read-only)**: GitLab
  exposes MR head refs — `git fetch origin merge-requests/<MR>/head &&
  git checkout --detach FETCH_HEAD`. Never `glab mr checkout` in a linked
  worktree (the source branch is checked out in the build worker's
  worktree and git will refuse); never `git checkout main`.
- **Check out a change in a linked worktree (fix, will push)**:
  `glab mr checkout <MR>`; if it fails because the branch is held by
  another worktree, `git fetch origin merge-requests/<MR>/head:fix/mr-<MR>
  && git checkout fix/mr-<MR>` and push later with
  `git push origin HEAD:<source-branch>`.
- **Read the diff**: `git fetch origin main && git diff origin/main...HEAD`,
  plus `glab mr diff <MR>` for the rendered view.
- **Read feedback**: `glab mr view <MR> --comments` for notes;
  `glab api "projects/:id/merge_requests/<MR>/discussions"` for inline
  threads — a thread is unresolved while any note has `"resolved": false`.
- **Post a review**: GitLab has no batched review submission. Post each
  actionable finding as a positioned discussion:

  ```bash
  # diff_refs come from: glab api "projects/:id/merge_requests/<MR>" --jq .diff_refs
  glab api "projects/:id/merge_requests/<MR>/discussions" --method POST \
    -f body="<finding>" \
    -f "position[position_type]=text" \
    -f "position[new_path]=<file>" -f "position[new_line]=<line>" \
    -f "position[base_sha]=<base_sha>" -f "position[head_sha]=<head_sha>" \
    -f "position[start_sha]=<start_sha>"
  ```

  If a positioned discussion is rejected (line not in the diff), fall back
  to an unpositioned discussion whose body starts with `` `<file>:<line>` ``.
  Then post the overall summary (including non-blocking notes) as a plain
  note: `glab mr note <MR> --message "..."`. Never use `glab mr approve` —
  the summary note starting with "CLEAN" is the approval signal.
- **Mark ready**: `glab mr update <MR> --ready`.
- **Reply to a thread**:
  `glab api "projects/:id/merge_requests/<MR>/discussions/<DISCUSSION_ID>/notes" --method POST -f body="..."`,
  then resolve it explicitly (GitLab does not auto-resolve on push):
  `glab api "projects/:id/merge_requests/<MR>/discussions/<DISCUSSION_ID>" --method PUT -f resolved=true`.
- **Comment on a change**: `glab mr note <MR> --message "..."`.
- **Merge**: `glab mr merge <MR>` (add `--squash` only if the repo asks for
  it). Do **not** pass `--remove-source-branch` — the branch is still
  checked out in the build worker's worktree; delete it in Cleanup, after
  the worktrees are gone: `git push origin --delete <source-branch>`.
- **Issue auto-close**: yes — `Closes #<n>` in the MR description closes
  issue `#<n>` on merge to the default branch, **provided the issue lives
  in this project's GitLab Issues**. Otherwise reference the issue by its
  tracker ref and close it per the tracker's Delivery operations after the
  merge.

> Best-effort: this mapping is maintained without a live GitLab pipeline to
> test against. If a command's shape has drifted, `glab <cmd> --help` is
> authoritative — fix the command here in this doc, not in the skills.
