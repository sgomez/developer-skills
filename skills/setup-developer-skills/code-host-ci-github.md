<!-- Template written to docs/agents/code-host-ci.md by /setup-developer-skills (GitHub host). Drop this comment line. Skip the whole file if the repo has no CI on PRs. -->

# Code host CI: GitHub

Annex to [`code-host.md`](./code-host.md). **Open it only when you are about
to wait for, read or classify a change's CI** — publishing a change, checking
it out, reviewing the diff and merging need nothing from here.

Three operations read the same checks, for different readers.

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

- **Classify a red — did the failing job actually execute?** (any reader,
  before spending a fix cycle on it): take `<run-id>` from the failing
  check's `link` (`…/actions/runs/<run-id>/job/<job-id>`), then

  ```bash
  gh run view <run-id> --json conclusion,jobs --jq '{run: .conclusion,
    failed: [.jobs[] | select(.conclusion != "success" and .conclusion != "skipped")
    | {name, steps: (.steps | length)}]}'
  ```

  A failed job with `steps > 0` ran against the change: **code-red** — a
  fix cycle. Every failed job at `steps: 0`, a run conclusion of
  `startup_failure`, or a job no runner ever picked up: **infra-red** —
  the job never started (runner offline, Actions minutes exhausted) and
  the red says nothing about the code.

<!-- Anything else this repo's readers need in order to interpret a red — what
green does and does not cover, which lanes run when, how to reproduce the
suite locally — belongs here or in the repo's testing docs, never back in
`code-host.md`: that file is read at the top of every worker's first turn. -->
