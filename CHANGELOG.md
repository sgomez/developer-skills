# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Changes staged on the `next` branch, published as a new version once ready.

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

[Unreleased]: https://github.com/sgomez/developer-skills/compare/v0.15.0...next
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
