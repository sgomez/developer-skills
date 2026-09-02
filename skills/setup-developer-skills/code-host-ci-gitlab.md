<!-- Template written to docs/agents/code-host-ci.md by /setup-developer-skills (GitLab host). Drop this comment line. Skip the whole file if the project has no CI on MRs. -->

# Code host CI: GitLab

Annex to [`code-host.md`](./code-host.md). **Open it only when you are about
to wait for, read or classify a change's pipeline** — publishing an MR,
checking it out, reviewing the diff and merging need nothing from here.

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

> Best-effort: this mapping is maintained without a live GitLab pipeline to
> test against. If a command's shape has drifted, `glab <cmd> --help` is
> authoritative — fix the command here in this doc, not in the skills.

<!-- Anything else this repo's readers need in order to interpret a red — what
green does and does not cover, which lanes run when, how to reproduce the
suite locally — belongs here or in the repo's testing docs, never back in
`code-host.md`: that file is read at the top of every worker's first turn. -->
