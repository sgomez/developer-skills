# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Changes staged on the `next` branch, published as a new version once ready.

### Added
- **The worker agents now carry the worktree sandbox's failure modes.** Inside
  a worktree the harness checks every Bash command stays in it, and two of its
  failure modes read as data rather than as errors: output piped to a consumer
  that stops early (`gh … | head`, and `gh issue view --comments` with no pipe
  at all) comes back **empty with exit 0**, and a chained `cmd_a && cmd_b` or
  an inline multi-path heredoc is refused outright. A worker that read the
  empty output as "no data" drew the wrong conclusion on its first command.
  `code-author`, `diff-reviewer` and `dispatcher` now state the symptom and
  the way around it (redirect to a file, split the chain, run the script by
  path). This is harness behaviour, identical in every repo — it ships with
  the agents, and `/setup-developer-skills` now says out loud that it does not
  belong in a repo's `docs/agents/code-host.md`.

### Changed
- **Contract docs are now a short core plus deferred annexes.** Every worker
  read `docs/agents/code-host.md` and `docs/agents/issue-tracker.md` whole in
  its first turn, before looking at a line of code — and most of what it paid
  for belonged to one phase it would often never reach. The CI mechanics (wait
  for the checks, read the ones recorded for a head sha, tell a code-red from
  an infra-red) move to a new **`docs/agents/code-host-ci.md`**, opened only at
  the checks gate; the rules for *creating* child issues (the native sub-issue
  link, the mandatory `## Spec extract` section) move to a new
  **`docs/agents/issue-authoring.md`**, read by `/to-tickets` and never by the
  delivery pipeline. The four skills and the three worker agents now say the
  annexes are **deferred, not optional** — read at the step that names them,
  never up front — and the steps that do need them say so on the spot. Without
  that half the split saves nothing: a worker that opens both files anyway has
  only gained a hop. `/setup-developer-skills` writes the annexes, offers to
  split an existing unsplit doc (verbatim: a relocation, not a rewrite), and
  carries the rule that keeps it from regrowing — core files stay under ~100
  lines, and phase-specific prose the repo adds later goes in the annex, not
  in the file every worker opens first.
- **Every worker agent now declares its `tools`.** `dispatcher` already did;
  `code-author` and `diff-reviewer` were inheriting the full set, MCP servers
  and `Agent` included, so a worker could spawn workers and a reviewer carried
  the same write surface as a builder. `code-author` gets the builder set plus
  `WebFetch`/`WebSearch` (implementing against an external library means
  reading its docs); `diff-reviewer` gets `Edit` rather than `Write` — the one
  file it may legitimately touch is a local code host's change file, and that
  is an append to an existing file. `diff-reviewer` also says out loud that
  the list is not a sandbox: it holds `Bash`, so read-only stays a rule it
  keeps, not a wall. The real isolation is still the worktree.

## [0.21.0] - 2026-09-01

### Added
- **The `oversized` knob and its `--build-oversized` flag.** A ticket triage
  scores too big is no longer a dead end that only a mid-run label edit can
  reopen. The knob joins `execution` and `merge` in
  `docs/agents/developer-defaults.md` (factory default `escalate`, unchanged
  behaviour); `oversized: build` — or `--build-oversized` for one run — builds
  the ticket at `opus` instead, taking triage's fault lines as the builder's
  order of work. Setup asks for it as its third question, recommending
  `escalate`.
- **`mergefix=<n>` in every ledger row.** `cycles=` prices the ticket being
  hard; the new field prices the *wave* being expensive, and only it lets a
  later calibration say "this spec's tickets all rewrite the same files —
  deliver the next one sequentially". Three of six PRs in one field run needed
  a merge-fix and the row schema had nowhere to say so, so the lesson lived in
  the chat summary and died there. The wrap-up's table and its
  parallel-was-expensive line read the same field.
- **The author's no-split directive vetoes an `oversized` verdict.** A body
  that says in so many words that the ticket ships as one unit ("deliberately
  indivisible", "no dividir") caps the dispatcher at `complex`/`opus`, fault
  lines still attached, with the veto named in `reason=`. The orchestrator
  makes the same check before escalating, so a triage that missed the
  directive does not cost a round trip. It is the one place a triage verdict
  is overruled, and only in that direction.

### Changed
- **A re-review reads the fix pass, not the whole change again.** `review-pr`
  now opens with a scope step: it asks the code host which revision the last
  review was submitted against and diffs from there (`git diff <sha>..HEAD`),
  falling back to the full `origin/main...HEAD` on a first review or a
  rewritten branch. The full diff stays readable as context, but untouched
  code is out of bounds for new findings — it was already reviewed. What
  replaces the re-read is a mandatory check that every previous finding was
  really fixed in code, and a `blocked` verdict when a fix pass pushed
  nothing at all. A three-cycle PR used to pay for four full reviews of the
  same change.
- **Re-reviews run on sonnet.** The first review is discovery across the whole
  change and keeps `diff-reviewer`'s pinned opus; the fix cycle's re-review is
  verification of a diff the skill has already scoped down, and the
  orchestrator now spawns it with `model: "sonnet"`.
- **All three code-host templates carry a read-the-last-reviewed-revision
  operation** — GitHub's review `commit_id`, GitLab's positioned-discussion
  `head_sha`, and a new `Reviewed at <sha>` line the local host writes at the
  top of each `## Review N` section.
- **The agent docs are read-only to a delivery run.** The harvest used to
  fold PR discoveries into `AGENTS.md` and anything under `docs/agents/`, then
  push straight to `main`: a sonnet worker rewriting the instructions every
  future run obeys, with no review anywhere in the path — the one class of
  change with more leverage than code, and the only one that skipped the
  reviewer. It now writes `docs/agents/delivery-ledger.md` and nothing else
  (the dispatcher reads that one back, so it is state, not instructions), and
  the discoveries land in `.scratch/developer-discoveries-<spec>.md` as
  proposals the wrap-up summary lists for a human to apply. `RESULT
  docs=<updated|none>` becomes `discoveries=<n>`.
- **Setup declares itself the owner of those docs**, and is told to update
  them against the templates without rewriting the repo's own prose — a stale
  sentence gets reported, not silently corrected. New guidance to keep
  perishable facts (an issue's state today) out of files whose next reader
  will try to fix them.
- **The `Other` code-host checklist names the new operation.** A custom host
  written from scratch by setup was the one shape that could miss
  read-the-last-reviewed-revision and so review the whole change every cycle,
  for good.

### Fixed
- **`scripts/plugin-mode.sh refresh` was dead in `next` mode — a whole
  cycle's commits never reached the install.** It matched the CLI's rendered
  `Source:` line (`Git (https://…git@next)`) against the string passed to
  `marketplace add` (`…git#next`), so next mode classified as prod: `refresh`
  exited *"Not in dev or next mode"* and `status` reported **PROD** for a
  correctly configured next install. Mode is now read from the source's
  substance (repo, plus an `@`/`#` branch marker), never character for
  character. Field evidence: a 3½-hour `/developer` run on the `0.21.0-next`
  build was byte-identical to `v0.20.0` — every change below and above it in
  this section was tested by nothing.
- **`plugin-mode.sh` now says what is actually loaded.** `dev`, `next`,
  `refresh` and `status` diff the installed copy against the tree it should
  mirror (this checkout, or `origin/<branch>`) and print `STALE` with the
  differing files, and next mode warns when local `next` is ahead of origin —
  what it installs comes from GitHub, so an unpushed commit is not in it. The
  static `X.Y.Z-next` version could never carry this: it is the same string
  all cycle, which is exactly why a stale install looked healthy.
- **A conflicting PR is no longer diagnosed as a CI that cannot start.** The
  Merge step's checks gate now reads `mergeStateStatus` *before* waiting for
  checks: a `DIRTY` branch gets no checks from the host, so the wait could
  only spend its five minutes and arrive at `no checks reported` — which the
  infra-red rule reads as an un-startable CI, escalating the sub-issue and
  **ending the run**. Two PRs hit it in one field run (spec #994) and only the
  orchestrator improvising past its own instructions saved them. The
  mergeability read is now a declared code-host operation (GitHub and GitLab
  templates), and infra-red applies only to a branch the gate confirmed was
  mergeable.
- **`cleanup-worktrees.sh` understands a locked worktree.** A worktree held by
  a live worker was reported `FAILED` and counted as a `leftover` — the wrap-up
  reads that as a leak, and the run that produced it summarized one live fixer
  as a leaked worktree. The script now parses the `locked` line: a lock naming
  a **running** pid is `KEPT` with the holder named and reported as `HELD`
  (a new `held=` count in the `OK` line, out of `leftover=`); a lock naming a
  **dead** pid is stale and is lifted, after which the ordinary dirty and
  remote-containment gates still decide; a lock placed by hand is never
  overridden. Pinned by three new cases in `tests/cleanup-worktrees.test.sh`.
- **A worker may not end its turn waiting on a background command.** The
  orchestrator cannot see a worker's background job, so a turn ending on
  "waiting for the test run to finish" is indistinguishable from a worker that
  died without reporting — in the field one fixer did it twice, with its fixes
  unpushed, costing two resume round trips and a stale head sha the
  orchestrator had to catch by hand. `code-author` and `diff-reviewer` now
  state the rule: checks run in the foreground, or are polled to completion in
  the same turn, before the `RESULT` line.
- **A ticket's blockers are no longer a triage size signal.** The dispatcher
  scored an issue `oversized` partly on its three `Blocked by` entries — all
  merged into `main` before the build, since the orchestrator only triages a
  sub-issue once its blockers are delivered. It scored the ticket for finished
  work, and inverted the rubric's own rule that a merged pattern makes a
  ticket *cheaper*: the issue came back CLEAN on its first review with zero fix
  cycles.
- **The post-merge sibling refresh covers every still-open member, one call
  per Bash invocation.** A wave member mid-fix-cycle is precisely the one that
  goes stale, and skipping it deferred a conflict to the merge gate forty
  minutes later with the conflict queue idle in between; an `update-branch`
  that fails on a conflict is now stated as what *enqueues* a PR. The
  refreshes must also be issued as separate commands — a `for` loop over the
  wave reads as a bulk code-host write to the permission classifier and was
  denied wholesale, while the same calls run singly went through untouched.
- **Merge conflicts no longer fan out into parallel rewrites.** Merge-fix
  workers resolve against `main` *as it is now*, so running three at once
  delivered one PR and queued two rewrites — a run in the field spent two opus
  workers to redo the same conflict, and O(N²) is the shape of that for N
  conflicting PRs. The first conflict of a wave now switches it to a
  **conflict queue**: at most one merge-fix worker alive in the whole run,
  spawned only for the PR at the head of the queue and only after the previous
  one is in `main`, with a plain merge retried first (the winner's merge often
  took the conflict with it). Builds and reviews of non-conflicting members
  carry on underneath — the queue serializes the merge path, not the wave.
- **Merge-fix rebases onto fresh `main` instead of merging `main` into the
  branch**, so the PR's diff stays the PR's own work and the reviewer is not
  handed the whole of `main` a second time. It falls back to a merge when the
  branch is the wrong shape for a rebase, and says which it did.
- **A stale base no longer escalates a healthy PR.** The orchestrator records
  `main`'s sha before spawning the merge-fix and re-checks it before merging.
  If `main` moved while the worker ran, the failure is stale-base, not a bad
  resolution: it costs an `update-branch` and a respawn, and does **not**
  consume the one-retry budget that used to escalate PRs with nothing wrong
  with them.

## [0.20.0] - 2026-08-12

### Added
- **Two `PreToolUse` guards that make `/developer` rules enforceable instead of
  hopeful.** `hooks/require-background-workers.sh` refuses a spawn of
  `code-author`, `diff-reviewer` or `dispatcher` with an explicit
  `run_in_background: false`, and tells the model to re-issue the identical
  call in the background. `hooks/no-ci-logs-in-orchestrator.sh` refuses
  `gh run view … --log*` from the primary checkout while a run is in flight —
  workers, which run in linked worktrees, are exactly who should read those
  logs and fall through untouched. Both stay silent unless every guard holds,
  and `tests/developer-hooks.test.sh` pins the silences as tightly as the
  denials.
- **`/developer` knows how to resume itself.** A new *Resuming the
  orchestrator* section states that while a run is in flight every prompt
  reaching the orchestrator is a resume — a bare "continue" included — and
  never a no-op. It rebuilds the run from the three things that outlive a dead
  context (the task board, the run log, `ListAgents`), then recovers each
  unfinished sub-issue in cost order: resume the live worker with
  **SendMessage**, else re-enter the per-sub-issue pipeline step 0, else start
  it from triage. Field runs lost a whole build and stalled for over an hour
  because none of this was written down.
- **Spawn rows in the run log.** BUILD, FIX and MERGE-FIX/HARVEST spawns now
  append an `event=spawned … agent=<agentId>` line to
  `.scratch/developer-run-<spec>.log`, so a sub-issue in flight leaves a trace
  a resume can read after a compaction. Terminal rows are the ones carrying
  `outcome=`, and the wrap-up now filters on that before handing rows to the
  harvest — spawn rows never reach the ledger.

### Fixed
- **`/developer` confirms a build's PR exists before reviewing it.** A field run
  had a `code-author` report `RESULT pr=<N>` for a number the host 404s on, with
  the entire implementation still uncommitted in its worktree — the publish step
  had never run. Nothing in the pipeline was checking, and only the reviewer's
  incidental failure caught it. The Build step now spends one `gh pr view` on
  every reported number, and on a 404 resumes the live worker with
  **SendMessage** instead of re-spawning the build: in the field that recovered
  the whole thing in ~29 minutes against ~49 to rebuild it.
- **The merged-branch delete no longer errors on hosts that delete it for you.**
  Many hosts remove the head branch on merge, and against one of those the
  cleanup step's bare `git push origin --delete` failed with `remote ref does
  not exist` on every single merge of a run — noise indistinguishable from a
  delete that failed for a reason worth knowing. It is now guarded by
  `git ls-remote --exit-code --heads`. The delete itself stays: `cleanup-
  worktrees.sh` only ever deletes *local* branches.
- **A red CI run gets one retry before `/developer` pays for a fix cycle.**
  `gh run rerun <run-id> --failed`, once per PR and never twice: an
  intermittent suite reds a change that is fine, and one CI run is far cheaper
  than a fixer plus a re-review, while a retry *loop* would merge a genuinely
  broken flaky test by persistence. A field run spent this exact case and only
  escaped it because the orchestrator improvised the retry.
- **The orchestrator may not read CI logs.** `gh run view --log-failed` and
  anything like it dumps raw job output into the context the whole design
  protects — six such calls compacted a field run's main context. The Merge
  step's `--json` classification is now stated as the whole diagnosis the
  orchestrator gets; past it, the answer is the retry and then the fixer, which
  already receives the failing job's URL.
- **The `/developer` wrap-up archives the run log instead of deleting it.** It
  now moves to `.scratch/archive/developer-run-<spec>-<timestamp>.log`, which
  stops the next run re-appending its rows just as well as `rm` did, without
  being destructive. Reaching the wrap-up is not proof the run is over — a
  human lifting an escalation restarts the loop, and a field run that did
  exactly that lost the rows of four sub-issues and had the second harvest
  rebuild them from recall. A resume also reads the archive when a wrap-up
  already ran this spec.
- **The `/developer` checks gate no longer reads "no checks yet" as red.**
  `gh pr checks` exits non-zero both when a check fails and when none is
  registered, and the gate's comment claimed only the first — so the seconds
  right after a `gh pr update-branch` (which moves the head sha) looked like a
  red with no run to classify. The gate now waits for CI to attach at least one
  check before watching them, and treats a branch that never gets one as
  infra-red. The skill also states that a command may never open with a bare
  `sleep` — the harness blocks it — and points at `until`/`for` loops or the
  Monitor tool instead.

### Changed
- **Every `/developer` worker spawn is `run_in_background: true`**, in both
  execution modes, dispatchers included. A foreground spawn holds the
  orchestrator's turn open for the worker's whole run, so a Ctrl-C or a dropped
  connection destroys the worker's context, worktree and commits; a background
  worker survives the same interruption and stays reachable. Sequential mode
  now means *wait for the result before spawning the next*, not *spawn in the
  foreground*.
- **The orchestrator keeps each running worker's `agentId`** (dropped as soon
  as its `RESULT` arrives) and gives every spawn a `description` naming the job
  and the sub-issue, so a live worker can be identified and resumed instead of
  rebuilt.

## [0.19.3] - 2026-07-24

### Fixed
- **`cleanup-worktrees.sh` can no longer destroy the only copy of any
  work.** Two structural guards replace trust in the caller: a worktree with
  uncommitted changes (staged, unstaged, or untracked) is never removed, and
  a local branch is deleted only when its tip is contained in a
  remote-tracking ref — so everything the script deletes is restorable with
  `git branch <name> <remote>/<name>`. Unpushed branches, dirty worktrees,
  and checked-out branches all come back as `KEPT` lines naming the reason,
  and the final `OK` line grows a `kept=<n>` count.

### Changed
- **`cleanup-worktrees.sh --sweep` matches worker worktrees by path only.**
  The sweep no longer applies the `agent/*` / `fix/pr-*` / `worktree-agent-*`
  name globs to worktrees elsewhere in the repo — a checkout of yours that
  happens to sit on a worker-named branch is out of its reach. Worktrees
  outside `.claude/worktrees/` are reached only by explicit `--branch`/`--sha`
  flags, which stay caller-scoped by design.
- `--max-branches` now counts only branches that already passed the
  remote-containment gate, so kept branches no longer eat into the cap.

### Added
- `tests/cleanup-worktrees.test.sh`: self-contained regression tests (bare
  origin + clone fixtures) pinning the cleanup script's guarantees. Run with
  `bash tests/cleanup-worktrees.test.sh`.

## [0.19.2] - 2026-07-24

### Fixed
- **`cleanup-worktrees.sh --sweep` no longer reaps worker branches from other
  runs.** The final-sweep branch deletion matched `agent/*`, `fix/pr-*` and
  `worktree-agent-*` against **every** ref in the repo, so a run launched
  without `--keep-branches` deleted every worker-named branch ever
  accumulated — not just its own — including old branches unrelated to the
  current spec. The sweep now deletes only the branches of the worktrees it
  removes in this pass; a worker-named branch with no worktree survives and
  must be targeted with an explicit, run-scoped `--branch` glob. Explicit
  `--branch` deletion is unchanged (still caller-scoped, repo-wide by design).

### Added
- **`--max-branches <n>` safety cap on `cleanup-worktrees.sh`.** Any single
  invocation that would delete more than `<n>` local branches (default 20; `0`
  disables) now deletes **none** of them: it prints a `WOULD-DELETE` line per
  candidate and an `ABORT` line, and exits 3. The worktrees are already
  removed (non-destructive — the branches still hold their commits), leaving
  the branch list for a human to confirm rather than executing a mass deletion.

## [0.19.1] - 2026-07-24

### Fixed
- **`cleanup-worktrees.sh` no longer aborts on an empty match list under old
  bash.** Three loops iterated `"${patterns[@]}"` / `"${shas[@]}"` without the
  empty-array guard the branch-freeing loop already used, so under `set -u` on
  bash < 4.4 (notably macOS's default `/bin/bash` 3.2) a run with no matching
  array — `--sha` only, or `--sweep` over a detached worktree with no `--sha` —
  raised `unbound variable` and exited. Guarded all three with the existing
  `${arr[@]+"${arr[@]}"}` idiom; behaviour on bash ≥ 4.4 is unchanged, where the
  bare expansion was already safe.

## [0.19.0] - 2026-07-21

The pipeline's cheapest worker stops authoring its only design decision:
an `oversized` ticket's split is now drafted where the original cut was
made, not approved off a low-effort triage line.

### Changed
- **An `oversized` split proposal is a seed, not a decision.** The
  dispatcher's `hints=` on an `oversized` verdict now name the issue's
  **fault lines** — where it splits — instead of posing as the finished
  partition, and the escalation comment and wrap-up route the actual cut to
  `/to-tickets` in a fresh session with a high-tier model and high effort,
  the conditions the original spec→tickets cut was made under. The
  dispatcher runs at pinned `effort: low` — right for classifying, and the
  `oversized` signals are checklist-shaped — but its hints were the
  pipeline's only design-shaped output, and the wrap-up used to invite a
  one-line "approve the proposed split?": an anchor on the cheapest
  worker's hardest task. The routing is advisory by construction (skills
  inherit the session's model and effort; only agents pin theirs) — a
  pinned-tier split worker is parked in the backlog until a run shows a bad
  partition actually being approved.

## [0.18.0] - 2026-07-21

Everything the spec #397 field run taught: the build ladder loses its cheap
rung, a red the CI never ran stops costing fix cycles, sibling PRs stay in
sync after every merge instead of failing behind it, the run's calibration
lessons reach the ledger, and the builder's reasoning effort stops drifting
with the operator's session settings.

### Changed
- **Builder effort pinned to `medium`, and recorded per ledger row.**
  `code-author` was the only worker without an `effort:` in its definition
  (dispatcher pins `low`, diff-reviewer `high`), so builds ran at whatever
  the operator's saved session default happened to be — a personal setting
  the pipeline neither chose nor recorded, changing silently between runs.
  `medium` is the value every ledgered run actually built with, so the pin
  changes nothing today; it stops the variable drifting tomorrow. The run
  log row gains `effort=` next to `model=` so each row is self-contained
  when comparing runs (older rows without the field parse as before).
- **A red the CI never ran is no longer a fix cycle.** All three CI readers
  now classify a red before spending on it, via the code-host docs' new
  classify-a-red operation (on GitHub: a failed job with zero executed
  steps, or a `startup_failure` run, never exercised the code): the merge
  gate escalates and ends the run instead of dispatching a fixer — an
  un-startable CI reds every later PR identically — the reviewer treats it
  as "no checks recorded" and falls back to its local run, and a CI-only
  fix job reports `blocked reason=ci-infra` instead of waiting for a green
  that cannot come. Field evidence (spec #397): a repo out of Actions
  minutes cost a full fix cycle — a worker polling a job with zero steps —
  plus an escalation, for a red that said nothing about the code. The
  GitLab template maps the same split via `failure_reason`; a code-host doc
  without the operation keeps the old behaviour (every red is code-red). `trivial` now builds with sonnet
  and the fix-cycle escalation is sonnet → opus. Field evidence (spec #308,
  plus the ledger's earlier haiku rows): on comparable tickets haiku builds
  cost as much or more than sonnet in tokens and wall-clock, missed domain
  vocabulary sitting two lines above their edit, and were the run's only
  workers to escape their worktrees and operate on the primary checkout —
  the cheap tier wasn't cheap.
- **Parallel staleness fixed at the source.** After every serial merge the
  orchestrator refreshes the wave's still-open sibling PRs per the code
  host's update-branch operation (`gh pr update-branch` on GitHub), and the
  checks gate re-syncs a red PR that is merely `BEHIND` main — once per PR —
  before spending a fix cycle. Spec #308 lost three 10–15-minute fix cycles
  to branches cut from a `main` that predated a sibling's merge; each was
  one API call's worth of work.
- **Scoring lessons now reach the ledger.** The dispatcher's rubric scores
  pattern existence at triage time explicitly — first-of-family up a tier,
  copy-of-a-merged-pattern down one — and the wrap-up hands the harvest the
  orchestrator's own calibration notes (the *mechanism* behind a mispriced
  tier), so run lessons land in the ledger's `## Local calibration` instead
  of dying in the chat summary.

### Fixed
- **Sweep warns on a hijacked primary checkout.** `cleanup-worktrees.sh` now
  prints a `WARN` when the primary checkout sits on a worker branch
  (`agent/*`, `fix/pr-*`, `worktree-agent-*`), not only when it is in
  detached HEAD — the on-a-branch escape produced only an easily missed
  `KEPT` line before. The sweep also deletes stray `worktree-agent-*`
  branches whose worktree is already gone.

## [0.17.0] - 2026-07-19

Context economy: the orchestrator stops paying for material it will not use,
the builders stop re-reading the whole spec once per sub-issue, and a ticket
that cannot fit in one session is now caught before a builder burns three fix
cycles on it. Plus the lessons of the first field run: the pipeline no longer
leaks worktrees, and a run that escalates ends with the questions that
unblock it.

### Added
- **`oversized` triage verdict** (report C4). The dispatcher's rubric gains a
  fourth verdict for issues that do not fit in a single fresh context window —
  3+ modules with no pattern to imitate, several vertical slices behind one
  title, a migration paired with a feature. The orchestrator does not build
  them: it escalates straight to a human, spending no build, review or fix
  cycle, and the escalation comment carries the **proposed split** the
  dispatcher already worked out (its `hints=` field changes job for this
  verdict). Until now the strongest signal triage could send was
  `complex → opus`, and a stronger model does not make an oversized ticket
  fit — it just fails more expensively. A malformed `RESULT` still falls back
  to `opus` **and builds**: an unparseable line is not an `oversized` verdict.
- **CI gate before merge** (report D3). With `merge: auto`, the Merge step now
  waits for the change's checks (`gh pr checks --watch --fail-fast`) and
  refuses to merge on red. Red checks are routed to a **fix cycle** with the
  failing job's URL, not to the merge-fix job: previously every merge failure
  was read as a conflict, so a repo with required checks answered a red build
  by dispatching an opus worker to resolve conflicts that did not exist, then
  escalated with the wrong diagnosis. A repo with no branch protection could
  merge its own red build outright. The `code-host-*.md` templates gained a
  `CI` declaration and the operations to read it, and
  `/setup-developer-skills` now asks for it; `CI: none` reproduces the old
  behaviour exactly.
  - `approve-merge.sh` enforces the same gate deterministically: the hook now
    checks the change's `statusCheckRollup` and approves only on green.
    Otherwise it stays silent — it never emits a `deny` — so a red or pending
    build falls back to the normal permission flow instead of being waved past
    the auto-mode classifier. A repo with **no** checks at all is still
    approved, unchanged; an unreachable or unauthenticated `gh` counts as
    unknown, and unknown is not green.
  - `fix-pr` accepts a **CI-only** job: failing checks count as feedback, so a
    change whose build broke after a CLEAN review no longer hits the skill's
    "nothing to act on" refusal — which would have escalated every red build
    the new gate caught, the exact opposite of the gate's purpose. Such a job
    has no threads to reply to; it records what it fixed as a comment on the
    change instead.
- **`## Spec extract` in every ticket** (report C3). The three delivery-ops
  templates now require whatever splits a spec — `/to-tickets` — to copy the
  parent's applicable Implementation and Testing Decisions verbatim into each
  child. A ticket carrying that section is self-sufficient, and the default
  inverts: `implement-issue`, the code-author BUILD job and the dispatcher
  read the ticket, falling back to the full parent spec only when the section
  is missing. A ten-child spec used to have its whole body read ten times,
  competing with the code exploration a builder cannot cut.

### Changed
- **The reviewer trusts green CI** (report C8). `review-pr` now reads the
  checks recorded for the change's head sha before doing anything expensive:
  green means no dependency install and no local suite — the diff and spec
  fidelity are the review; red is an automatic NEEDS_FIXES quoting the failing
  job's URL, with no attempt to reproduce it. Running the suite was the most
  expensive part of every review, in the most expensive model, and on a repo
  with CI it was the third run of the same commands on the same commit. Repos
  that declare no CI keep running it locally, unchanged.
- **`/developer` loads its conditional material on demand** (report C2). The
  orchestrator skill was one 814-line block mixing the common path with
  material most runs never reach; it now keeps the common path and reads three
  siblings when the step needs them: `LOCAL-HOST.md` (every local-host and
  local-tracker adjustment, read at the start only when a contract doc says
  the host or tracker is local), `MERGE-FIX.md` (the merge-fix job, read at the
  first conflict) and `WRAP-UP.md` (the seven closing steps including the
  harvest prompt, read once when the loop ends). A GitHub run on a spec that
  merges cleanly no longer pays for any of it.
- **A wrap-up with escalations ends with the questions that unblock them** —
  one per escalated sub-issue, phrased so a one-line reply resolves it. The
  first field run described its two escalations accurately and the human
  still had to ask "what do you need from me?" — the orchestrator knew the
  answer all along.

### Fixed
- **Worker worktrees no longer leak past the run.** The first field run left
  eleven behind, in three shapes the cleanup could not name: reviewer
  worktrees detached at a sha a later fix cycle superseded (the per-sub-issue
  pass names only the final head sha), a merge-fix worker improvising
  `mergefix/pr-N` because `fix/pr-N` was still held by the first fix cycle's
  live worktree, and a final sweep blind to both. `cleanup-worktrees.sh
  --sweep` now also matches by **path** — every worker worktree under
  `.claude/worktrees/`, branch or detached — and deletes the branches those
  removals free.
- **Colliding fix branches get canonical fallback names.** A second fix cycle
  uses `fix/pr-N-r2` (`-r3`, …) and the merge-fix job `fix/pr-N-merge` when
  `fix/pr-N` is taken; the per-sub-issue cleanup matches `fix/pr-N*`, so a
  collision no longer produces a name nothing matches.
- **The sweep reports what it could not remove instead of an unconditional
  `OK`.** It re-checks the filesystem after the prune — a failed removal can
  leave a directory git has already forgotten — prints a `LEFTOVER` line per
  survivor, and the final line carries a `leftover=` count. The wrap-up
  claims a clean sweep only on `leftover=0`; the first field run summarized
  "all worktrees swept" over eleven survivors because the script's `OK` only
  ever meant "everything I matched".

## [0.16.0] - 2026-07-19

Run robustness: a `/developer` run can now be interrupted and re-launched
without paying for the work it already did, and it stops paying twice for the
work it will never finish. **Breaking**: the plugin is now the only install
route — see *Removed*.

### Added
- **Resume instead of rebuild** (report D1). The delivery pipeline gains a
  step 0: before triaging a sub-issue it asks the code host whether an open
  change already references it (`gh pr list --search '"Closes #<N>" in:body'`),
  and enters at the right stage — Review when the PR has no unresolved threads,
  the Fix cycle when it has, Triage/Build only when there is no PR at all. A
  session that died mid-run used to re-enumerate the same open sub-issues and
  rebuild them from scratch, opening a second PR per sub-issue and paying for a
  second review of it. Two open changes for one sub-issue escalate rather than
  guess. The `code-host-{gitlab,local}.md` templates map the two new operations
  (find the open change for an issue; count its unresolved threads) for the
  other hosts.
- **The `ready-for-human` label is now a gate, not just a marker** (report D2).
  The pick (spec loop step 1 and the parallel wave) skips any sub-issue
  carrying the escalation label — previously it was applied on escalation and
  never read again, so "skip what you escalated" lived only in the session's
  memory and the *next* run happily picked the same sub-issue up and burned
  three more fix cycles against the same wall. The contract is symmetric and
  documented in the wrap-up: **removing the label re-queues the sub-issue**,
  and the re-run resumes its PR (D1) instead of rebuilding it. The GitHub
  sub-issue enumeration now fetches labels for this.
- **Ledger rows are written when they happen** (report C6). Each sub-issue
  appends its row to `.scratch/developer-run-<spec>.log` the moment it goes
  terminal (new pipeline step 7); the wrap-up reads that file instead of
  recalling ten sub-issues' worth of tiers, PR numbers and cycle counts through
  a context compaction. The harvest gets the rows verbatim, and the log is
  deleted once they are committed to the ledger.

### Changed
- **A worker's entire final message is its `RESULT` line** (report C1). The old
  contract ("end your reply with exactly one line, nothing after it") only
  pinned the *last* line, so a thorough builder prefaced it with a summary that
  landed whole in the orchestrator's context — 30–50 such reports in a ten
  sub-issue run, none of which survive the run. All three agents and every
  spawn prompt now require the line to be the whole message, and point the
  worker at the durable homes for anything worth keeping: the PR body,
  `## Discoveries`, thread replies.
- **Workers run targeted, quiet checks** (report C5). `implement-issue` now
  prescribes the discipline `/implement` already had: during TDD run **only the
  affected test file**, with the project's quietest reporter, and the full suite
  **once**, at the end — on red, re-run just the failing file. `fix-pr` and
  `review-pr` ask for quiet reporters and targeted re-runs too, and the
  worktree bootstrap installs silently (`pnpm install --reporter=silent`) in
  both `implement-issue` and `code-author`. The context eaters inside a worker
  were never the source files: they were install logs and the same green suite
  printed five times.
- **Blockers are parsed by section** (report D5). `grep -A3 -i "blocked by"`
  read a fixed window by construction — dropping the fourth blocker of a longer
  list and capturing the head of the next section on a shorter one. Replaced
  with section extraction (`awk '/^##[#]* *[Bb]locked by/{f=1;next} /^#/{f=0} f'`)
  in `/developer` and `delivery-ops-github.md`. The sub-issue GraphQL queries
  (`first: 50`, unchecked — `first: 20` in `implement-issue`) now fetch
  `pageInfo { hasNextPage }` and **stop the run when it is true**: a spec with
  more children than one page was silently delivered as complete, and a spec
  that genuinely has 50+ sub-issues is not sized for this pipeline — it gets
  reported for splitting, not paginated through.

### Removed
- **The `npx skills add sgomez/developer-skills` install route is gone**
  — **breaking**. The plugin (`/plugin install developer-skills@sgomez`) is now
  the only supported way to install. That route copied skill folders but could
  not install agents, so it delivered a `/developer` that could not run until
  `/setup-developer-skills` hand-copied `dispatcher`, `code-author` and
  `diff-reviewer` into `.claude/agents/` — agents that then sat outside
  `/plugin update` and drifted from the release. It bought no portability
  either: the pipeline depends on Claude-Code-only primitives (per-spawn model
  tiers, `effort:`, worktree isolation), so it served the same audience as the
  plugin route, worse.

  **If you installed that way**: install the plugin, restart the session, and
  delete the three stale files from your repo's `.claude/agents/` — an
  un-namespaced `code-author.md` there shadows nothing, but it will rot.
  `/setup-developer-skills` now refuses to proceed when the plugin is not
  loaded, and everything it wrote to `docs/agents/` stays valid.

### Fixed
- **The merge hook only approves from the primary checkout** (report D6).
  `approve-merge.sh` keyed on a `merge: auto` line in
  `docs/agents/developer-defaults.md` under the caller's `cwd` — a committed
  file, so it is equally present in every worker's worktree, and a worker that
  ran `gh pr merge` on its own would have been auto-approved. It now also
  requires `git-dir == git-common-dir`, true only in the primary checkout where
  the orchestrator runs. Merging was already the orchestrator's alone; now the
  hook enforces it deterministically instead of trusting the prose.
- **The linked-worktree check no longer misreads the primary checkout as a
  worktree.** Every worker guards its checkout by comparing `git rev-parse
  --git-dir` against `--git-common-dir`, which git prints in whichever form is
  shortest from the current directory: identical at the repository root, but
  `/abs/path/.git` versus `../.git` from any subdirectory of it. The guard read
  that difference as "I am safely inside a worktree" and let the checkout run,
  detaching the user's HEAD — the exact accident the guard existed to prevent,
  and the source of the `WARN primary checkout … is in detached HEAD` line the
  cleanup script reports. All four call sites (`review-pr`, `fix-pr`,
  `implement-issue` and `approve-merge.sh`) now pass `--path-format=absolute`,
  so the two paths are comparable — and the `diff-reviewer` agent stopped
  being a fifth, since it now states the rule the checkout must satisfy and
  leaves the command to the skill it already tells the worker to follow. In the hook
  the same defect ran the other way and silently withheld approval: it also
  now resolves `docs/agents/developer-defaults.md` from the repository root
  rather than from `cwd`, so a `merge: auto` run started from a subdirectory is
  approved as intended.

## [0.15.0] - 2026-07-16

`merge: auto` finally delivers unattended under Claude Code's **auto mode**.
The classifier had been denying the orchestrator's merge as an unreviewed
one — correctly, on the facts: under this pipeline's design nobody ever
approves the PR. An allow-list rule never exempted it (observed with
`Bash(gh pr merge:*)` in place for days while merges were still denied); a
PreToolUse `allow` does, because it resolves before the classifier runs.

### Added
- **PreToolUse hook that auto-approves the pipeline's one sanctioned merge.**
  A new plugin hook (`hooks/approve-merge.sh`, registered by `hooks/hooks.json`,
  which Claude Code auto-loads from the standard path — the manifest must not
  name it too) grants a PreToolUse `allow` decision to exactly
  `gh pr merge <PR> --merge|--squash|--rebase`, and only in repos whose
  `docs/agents/developer-defaults.md` carries `merge: auto`. This is the
  deterministic path the allow-list alone could not provide: in auto mode the
  classifier re-evaluates the orchestrator's unattended merge as a
  "merge without human approval" pattern and denies it *even with*
  `Bash(gh pr merge:*)` allow-listed — observed with the rule in place for
  days before a merge was still denied. Everything else defers untouched:
  chained commands, `--admin`, any non-merge Bash, and `merge: manual` repos
  never get the `allow`, so nothing is widened beyond that single command.

### Fixed
- **A review worker can no longer detach the primary checkout.** The
  `review-pr` checkout step was a two-part advisory — "confirm you are in a
  linked worktree, *then* check out the change head detached" — that a worker
  could skip, running `git checkout --detach FETCH_HEAD` in the primary
  checkout and leaving it in detached HEAD at the PR head. The worktree check
  is now folded into the checkout command itself
  (`[ "$(git rev-parse --git-dir)" != "$(git rev-parse --git-common-dir)" ] || exit 1`),
  so a drifted cwd yields a clean `blocked` report instead of hijacking the
  user's working state. Mirrored in both `diff-reviewer` agent copies.

## [0.14.0] - 2026-07-11

The review gate sheds every trace of approval authority, unblocking the
pipeline under Claude Code's **auto mode**: its classifier denied the old
reviewer spawn as Self-Approval — a sub-agent with delegated review-posting
*and* mark-ready authority over a PR authored by a sibling sub-agent of the
same session.

### Changed
- **Marking the PR ready moves from the reviewer to the orchestrator.**
  The `diff-reviewer` still posts the review itself — always a single
  COMMENT submission, never an approval event and never `gh pr ready` —
  and the `/developer` orchestrator runs the code-host doc's mark-ready
  operation after the verdict. Local hosts unchanged: `Status: ready`
  travels in the reviewer's change-file commit. The reviewer spawn prompt
  drops the self-attested authorization wording ("you are authorized to
  perform these code-host writes") that the classifier read as delegated
  self-approval.
- `/developer`'s permission-denial rule now also covers the orchestrator's
  own code-host writes (marking ready, merging): a denied action is never
  re-run or re-shaped into a different command — the sub-issue escalates.

### Fixed
- `/setup-developer-skills` no longer writes any `autoMode` block. The old
  one was doubly wrong: it went into the shared `.claude/settings.json` — a
  scope the auto-mode classifier deliberately ignores (a checked-in repo
  must not grant itself trust), so it was dead config — and it is
  unnecessary anyway, because explicit `permissions.allow` rules resolve
  *before* the classifier and narrow rules carry over into auto mode, so
  the pipeline's allowlisted writes are never classified. The `gh`/`glab`
  rules stay in the shared file; the machine-specific cleanup-worktrees.sh
  rule goes to `.claude/settings.local.json`.

## [0.13.0] - 2026-07-10

The `/developer` pipeline learns across runs and finishes what it starts: the
dispatcher calibrates its triage from a per-repo delivery ledger, forwards
its exploration as build hints, and the wrap-up closes the spec/PRD itself
once every sub-issue is delivered.

### Added
- **Spec auto-close**. The `/developer` wrap-up now closes the spec/PRD issue
  itself when every sub-issue is verified CLOSED against the tracker (with a
  comment naming the delivery), instead of leaving it open forever. With
  `merge: manual` the spec stays open and the human merge queue gains an
  explicit final step — close the spec after the last sub-issue; the
  two-argument mode (`/developer <spec> <subissue>`) runs the same check
  when the delivered sub-issue was the spec's last open one.
- **Delivery ledger + dispatcher calibration** (report F1). The wrap-up harvest
  job now also records the run in `docs/agents/delivery-ledger.md` — one
  `## Run log` row per delivered sub-issue (date, model, PR, verdict, fix
  cycles, wave, outcome) — and distills a `## Local
  calibration` section from the accumulated log when a class of issue proves
  consistently mis-tiered. The `dispatcher` reads that calibration on top of
  its generic rubric, so triage learns this repo's real complexity across
  runs.
- **Dispatcher triage brief** (report FF1). `dispatcher`'s `RESULT` line now
  also carries `touches=` (dirs/modules the issue will touch) and `hints=`
  (the pattern or file to imitate) — the exploration it already does to
  score complexity, previously thrown away. The orchestrator forwards
  `hints` verbatim into the Build step's prompt, so the builder starts from
  what triage already found instead of re-exploring the same ground cold.

## [0.12.0] - 2026-07-09

Second round of alignment with mattpocock/skills v1.1 (see 0.11.0): the
review gate adopts the Spec axis and the Fowler smell baseline from Matt's
new `/code-review`, and TDD matches the v1.1 loop (refactor deferred to
review).

### Added
- `review-pr` now reads the **originating spec** (the issue behind the PR's
  `Closes #N`, plus its parent spec/PRD) and checks **spec fidelity**:
  requirements missing, partial, or implemented wrong, and scope creep are
  actionable findings. Previously the CLEAN gate never fetched the issue, so
  a PR implementing the wrong thing could pass.
- `review-pr` carries Fowler's refactoring-smell catalogue (mysterious name,
  feature envy, data clumps, …) as **non-blocking notes** — judgement calls
  that never flip the verdict.
- `diff-reviewer` verdict semantics updated to match: spec violations are
  NEEDS_FIXES; refactoring smells are notes under CLEAN.

- `delivery-ops-gitlab.md`: "Discover a sub-issue's blockers" operation for
  parity with GitHub — body sections stay canonical; native blocking links
  (GitLab Premium) are cross-checked when present.

### Changed
- `implement-issue` TDD loop aligned with mattpocock/skills v1.1: red →
  green only; refactor-level cleanups are deferred to the review phase
  (the diff-reviewer flags them).
- `implement-issue` now explicitly follows the parent spec's Implementation
  Decisions and Testing Decisions (pre-agreed seams, prior-art tests) —
  `/to-spec` agrees those with the user precisely so the implementing agent
  honours them.
- **Terminology: "PRD" → "spec"** across the whole surface (skill
  descriptions, orchestrator prose and prompts, agent definitions, README,
  plugin manifest), matching `/to-spec`'s vocabulary. Placeholders renamed
  too (`<prd>` → `<spec>`, `<PRD_NUMBER>` → `<SPEC_NUMBER>` — the
  orchestrator↔worker prompts changed in lockstep). "PRD" remains only where
  it aids recognition, mirroring Matt's own usage: first-contact alias in the
  README and the `/developer` trigger, "spec/PRD" where a skill must locate
  documents older repos still name PRD (review-pr's originating spec, the
  delivery-ops parent markers), and the local tracker's `PRD.md` filename,
  which Matt's local seed still writes.

### Fixed

Findings from the first real local-host run (local tracker + local code
host, three sub-issues):

- `/developer`: on a local code host the review of a fresh change
  dead-ended on git's "branch already used by worktree" — the build
  worker's worktree outlives it and holds the change branch. The
  after-every-worker cleanup is now a structural part of the delivery
  pipeline (not a prose aside), and the orchestrator recovers from a
  branch-held blocked report with a one-shot Cleanup + re-spawn instead of
  escalating.
- `/developer` wrap-up: the final `--sweep` can be denied by the auto-mode
  permission classifier (pattern-matched worktree removal). The wrap-up now
  falls back to targeted `--branch` passes after checking
  `git worktree list`, and README + setup offer an `autoMode.allow`
  sentence for `cleanup-worktrees.sh` — needed on every host, including
  local.
- `merge: manual` runs left the user asking "and now what?": the
  orchestrator now states the exact merge commands (per the code-host doc)
  the moment a sub-issue becomes ready-to-merge and again in the wrap-up
  merge queue, including the close-issue step where the host has no
  auto-close.
- Merge conflicts are never resolved in the main context (new rule): the
  merge-fix job now also serves `merge: manual` — the human aborts the
  half-merge and the orchestrator dispatches a worker to make the branch
  mergeable in its own worktree.

### Documentation
- README: division-of-labour paragraph — Matt's skills plan (grilling →
  spec → tickets) and offer the HITL endpoint (`/implement` +
  `/code-review`); `/developer` is its AFK counterpart, building, reviewing
  and validating each ticket with isolated clean-context agents.

## [0.11.0] - 2026-07-08

Integration with [mattpocock/skills v1.1](https://www.aihero.dev/skills/skills-changelog-v1-1-wayfinder-to-spec-to-tickets-grilling-improvements),
which renamed `/to-prd` → `/to-spec` and merged `/to-plan` + `/to-issues` →
`/to-tickets`, and prefers the tracker's native blocking links over
`Blocked by` body sections.

### Added
- `/developer` and `implement-issue` now check GitHub's **native issue
  dependencies** (`issue_dependencies_summary.blocked_by`) in addition to the
  `Blocked by` body section when picking the next unblocked sub-issue —
  `/to-tickets` wires native edges where the tracker has them, so body-only
  parsing could silently see everything as unblocked.
- `delivery-ops-github.md`: new "Discover a sub-issue's blockers" operation
  covering both native dependencies and the body fallback; body sections
  remain required as the portable fallback.
- `delivery-ops-local.md`: explicit rule that tickets are per-issue files
  under `.scratch/<feature>/issues/` — overriding `/to-tickets`' local-files
  default of a single root `tickets.md`, which the pipeline cannot see.

### Changed
- All references to `/to-prd` and `/to-issues` updated to `/to-spec` and
  `/to-tickets` (setup skill flow, delivery-ops templates).

### Documentation
- README: install command and dependency table updated to the v1.1 skill
  names, plus a `wayfinder` row and its place in the intended loop
  (`/wayfinder` → `/to-spec` → `/to-tickets` → `/developer`).

## [0.10.0] - 2026-07-08

### Added
- Tracker- and host-agnostic delivery pipeline: issues and changes live wherever
  `docs/agents/issue-tracker.md` and the new `docs/agents/code-host.md` say.
  GitHub (`gh`), GitLab (`glab`), and local (markdown issues under `.scratch/`,
  changes as local branches with a committed change file) are first-class;
  anything else configures as freeform prose. The skills keep their `gh`
  commands inline as the factory default and defer to the contract docs.
- Code-host templates (`code-host-{github,gitlab,local}.md`) and issue-tracker
  `Delivery operations` templates (`delivery-ops-{github,gitlab,local}.md`)
  bundled with `setup-developer-skills`.
- `--keep-branches` flag in `cleanup-worktrees.sh` for local code hosts, where
  the branch is the only copy of unmerged work.

### Changed
- `setup-developer-skills` no longer rejects non-GitHub repos: it configures
  the issue tracker and the code host as independent axes, skips the code-host
  question when no git remote exists (local is inferred), and forces
  `merge: manual` on local hosts (unattended merges never move a checked-out
  `main`).
- `setup-developer-skills` no longer tries to invoke `setup-matt-pocock-skills`
  (which declares `disable-model-invocation`): it refuses to start until
  Matt's setup has run, and tells the user the order.
- The `/developer` orchestrator reads the two contract docs at run start,
  closes delivered issues explicitly when the code host has no auto-close, and
  adapts Step 0 publishing, cleanup, and the docs harvest to local hosts.
- `issue-tracker-subissues.md` was absorbed into `delivery-ops-github.md`.

### Documentation
- README: setup order (`/setup-matt-pocock-skills` first, enforced), the two
  configuration axes, per-host permission blocks, and updated requirements
  (GitLab and local are now supported).

## [0.9.0] - 2026-07-06

### Added
- Configurable run defaults and a manual-merge mode for the developer pipeline.

## [0.8.0] - 2026-07-06

### Added
- Deterministic worktree cleanup script.

### Changed
- Deduplicated prompt content across the worker flows.

## [0.7.0] - 2026-07-06

### Added
- Discoveries capture during runs and a wrap-up docs harvest step.

## [0.6.0] - 2026-07-06

### Added
- Worktree bootstrap discipline.

### Changed
- Quieter merge flow.

## [0.5.0] - 2026-07-05

### Added
- `tasks` list and report commands.
- Worktree cleanup support.

## [0.4.0] - 2026-07-05

### Added
- Optional `--parallel` wave mode for the developer orchestrator.

### Documentation
- Documented required permissions and the Matt Pocock skills.

## [0.3.0] - 2026-07-04

### Documentation
- Documented Antigravity CLI install via native Claude plugin import.

## [0.2.0] - 2026-07-03

### Changed
- Renamed the `architect` agent to `dispatcher`.

### Fixed
- Hardened worker flows against first-run failure modes.

### Added
- Added project license.

## [0.1.0] - 2026-07-03

### Added
- Initial release: unattended PRD delivery pipeline for Claude Code.

### Fixed
- Plugin `agents` manifest field requires explicit `.md` file paths.
- Moved agents to the canonical top-level `agents/` directory.

[Unreleased]: https://github.com/sgomez/developer-skills/compare/v0.21.0...next
[0.21.0]: https://github.com/sgomez/developer-skills/releases/tag/v0.21.0
[0.20.0]: https://github.com/sgomez/developer-skills/releases/tag/v0.20.0
[0.19.3]: https://github.com/sgomez/developer-skills/releases/tag/v0.19.3
[0.19.2]: https://github.com/sgomez/developer-skills/releases/tag/v0.19.2
[0.19.1]: https://github.com/sgomez/developer-skills/releases/tag/v0.19.1
[0.19.0]: https://github.com/sgomez/developer-skills/releases/tag/v0.19.0
[0.18.0]: https://github.com/sgomez/developer-skills/releases/tag/v0.18.0
[0.17.0]: https://github.com/sgomez/developer-skills/releases/tag/v0.17.0
[0.16.0]: https://github.com/sgomez/developer-skills/releases/tag/v0.16.0
[0.15.0]: https://github.com/sgomez/developer-skills/releases/tag/v0.15.0
[0.14.0]: https://github.com/sgomez/developer-skills/releases/tag/v0.14.0
[0.13.0]: https://github.com/sgomez/developer-skills/releases/tag/v0.13.0
[0.12.0]: https://github.com/sgomez/developer-skills/releases/tag/v0.12.0
[0.11.0]: https://github.com/sgomez/developer-skills/releases/tag/v0.11.0
[0.10.0]: https://github.com/sgomez/developer-skills/releases/tag/v0.10.0
[0.9.0]: https://github.com/sgomez/developer-skills/releases/tag/v0.9.0
[0.8.0]: https://github.com/sgomez/developer-skills/releases/tag/v0.8.0
[0.7.0]: https://github.com/sgomez/developer-skills/releases/tag/v0.7.0
[0.6.0]: https://github.com/sgomez/developer-skills/releases/tag/v0.6.0
[0.5.0]: https://github.com/sgomez/developer-skills/releases/tag/v0.5.0
[0.4.0]: https://github.com/sgomez/developer-skills/releases/tag/v0.4.0
[0.3.0]: https://github.com/sgomez/developer-skills/releases/tag/v0.3.0
[0.2.0]: https://github.com/sgomez/developer-skills/releases/tag/v0.2.0
[0.1.0]: https://github.com/sgomez/developer-skills/releases/tag/v0.1.0
