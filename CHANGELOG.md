# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
