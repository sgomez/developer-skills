# Agent instructions

## Repository layout

This repo is a Claude Code plugin (a "marketplace" with a single plugin).

- `skills/` — one directory per skill (`developer`, `fix-pr`, `implement-issue`,
  `review-pr`, `setup-developer-skills`), each with its own `SKILL.md`.
- `agents/` — worker agent definitions as top-level `.md` files
  (`code-author.md`, `diff-reviewer.md`, `dispatcher.md`).
- `.claude-plugin/plugin.json` — the plugin manifest and **canonical version**.
- `.claude-plugin/marketplace.json` — marketplace entry; points at `./`. The
  schema *allows* a per-plugin `version`, but we deliberately omit it so
  `plugin.json` stays the single source of truth — **do not add one here**.
- `CHANGELOG.md` — user-facing history (see release process below).

## Conventions

- **Commits** follow [Conventional Commits](https://www.conventionalcommits.org)
  (`feat:`, `fix:`, `docs:`, `chore:`, `refactor:`…).
- **Never** add a `Co-Authored-By: Claude` / Anthropic trailer to commits.
- The version lives in **one place** (`.claude-plugin/plugin.json`); nothing
  else should hard-code it.

## Releasing a new version

Any change that bumps the version **must** update the changelog and publish the
release. Never bump `version` in `.claude-plugin/plugin.json` without completing
every step below.

Versioning follows [Semantic Versioning](https://semver.org). While the project
is `0.x`, every GitHub release is a **pre-release** (there is no stable/`Latest`
release until `1.0.0`).

Development happens on the **`next` branch** (kept at the same version as the
last release). Try it out with `scripts/plugin-mode.sh dev` (this checkout,
uncommitted edits included — this machine only) or `scripts/plugin-mode.sh
next` (the pushed `next` branch on GitHub — works the same on any machine).
`scripts/plugin-mode.sh prod` switches back to the published release.
Changelog entries land under the `## [Unreleased]` heading as you go; a release
promotes that section to the new version.

### Steps

1. **Bump the version** in `.claude-plugin/plugin.json`.
2. **Update `CHANGELOG.md`** ([Keep a Changelog](https://keepachangelog.com)
   format):
   - Rename the `## [Unreleased]` heading to `## [X.Y.Z] - YYYY-MM-DD`, then add
     a fresh empty `## [Unreleased]` section above it for the next cycle.
   - Group entries under `Added` / `Changed` / `Fixed` / `Documentation`.
   - Update the link references at the bottom of the file: repoint
     `[Unreleased]` to `.../compare/vX.Y.Z...next` and add the matching
     `[X.Y.Z]: https://github.com/sgomez/developer-skills/releases/tag/vX.Y.Z`
3. **Commit** the version bump and changelog together on `next`, e.g.
   `git commit -m "feat: <summary> (X.Y.Z)"`.
4. **Merge `next` into `main`** — publishing always goes through `main`:
   ```sh
   git switch main && git merge --ff-only next
   ```
   Keep it a fast-forward so `main` lands the exact bump commit (rebase `next`
   onto `main` first if it has diverged).
5. **Tag** the version-bump commit on `main`: `git tag vX.Y.Z`.
6. **Push** `main` and the tag: `git push origin main --follow-tags`.
7. **Publish the GitHub release**, using that version's changelog section as the
   body and marking it as a pre-release while on `0.x`:
   ```sh
   gh release create vX.Y.Z --title vX.Y.Z --notes-file <section.md> \
     --prerelease --latest=false --verify-tag
   ```
8. **Continue development on `next`**: `git switch next && git merge --ff-only main`
   so both branches share the release commit before the next cycle.

The git tag `vX.Y.Z` must point at the exact commit that set `version` to
`X.Y.Z` in `.claude-plugin/plugin.json`.
