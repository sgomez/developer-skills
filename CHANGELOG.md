# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Changes staged on the `next` branch, published as a new version once ready.

### Added
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

[Unreleased]: https://github.com/sgomez/developer-skills/compare/v0.12.0...next
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
