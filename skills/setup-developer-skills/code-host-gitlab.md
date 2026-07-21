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
- **CI**: GitLab CI runs a pipeline per MR. <!-- Set to "none" if this project
  has no CI on MRs; the pipeline then skips the checks operations below and
  behaves exactly as it did before they existed. -->

## Operations

- **Publish a change**: push the branch, then
  `glab mr create --draft --source-branch <branch> --target-branch main --title "..." --description "..."`.
  Use a heredoc for multi-line descriptions.
- **Find the open change for an issue** (the orchestrator's resume check):
  `glab mr list --state opened --search "Closes #<N>" -F json`, then keep only
  MRs whose `description` really contains `Closes #<N>` — the search matches
  titles too. The `draft` field says whether it still needs marking ready.
- **Count unresolved threads on a change**:
  ```bash
  glab api "projects/:id/merge_requests/<MR>/discussions" \
    --jq '[.[] | select(any(.notes[]; .resolvable and (.resolved | not)))] | length'
  ```
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
- **Wait for the change's CI and gate the merge** (the orchestrator, before
  merging): `glab ci status --branch <source-branch> --live` — or poll
  `glab api "projects/:id/merge_requests/<MR>" --jq .head_pipeline.status`
  until it leaves `running`/`pending`. Anything other than `success` (or
  `skipped`) is a **red build**, not a merge conflict: the answer is another
  fix cycle, never a merge-fix job.
- **Read the checks recorded for the head sha** (the reviewer, before deciding
  whether to run the suite locally):
  ```bash
  glab api "projects/:id/pipelines?sha=<head_sha>" --jq '.[0] | {status, web_url}'
  ```
  `status: "success"` = green; anything else names the pipeline to quote via
  its `web_url`.
- **Classify a red — did the failing job actually execute?** (any reader,
  before spending a fix cycle on it):
  ```bash
  glab api "projects/:id/pipelines/<pipeline_id>/jobs?scope[]=failed" \
    --jq '.[] | {name, status, failure_reason}'
  ```
  `failure_reason: "script_failure"` means the job ran the change's code:
  **code-red** — a fix cycle. `runner_system_failure`,
  `stuck_or_timeout_failure` or `scheduler_failure` — or a pipeline whose
  jobs sit `pending` with no runner — is **infra-red**: the job never ran
  and the red says nothing about the code.
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
