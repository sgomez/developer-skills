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

### Steps

1. **Bump the version** in `.claude-plugin/plugin.json`.
2. **Update `CHANGELOG.md`** ([Keep a Changelog](https://keepachangelog.com)
   format):
   - Add a new `## [X.Y.Z] - YYYY-MM-DD` section at the top, above the previous
     version.
   - Group entries under `Added` / `Changed` / `Fixed` / `Documentation`.
   - Add the matching link reference at the bottom of the file:
     `[X.Y.Z]: https://github.com/sgomez/developer-skills/releases/tag/vX.Y.Z`
3. **Commit** the version bump and changelog together, e.g.
   `git commit -m "feat: <summary> (X.Y.Z)"`.
4. **Tag** the version-bump commit: `git tag vX.Y.Z`.
5. **Push** the commit and the tag: `git push origin main --follow-tags`.
6. **Publish the GitHub release**, using that version's changelog section as the
   body and marking it as a pre-release while on `0.x`:
   ```sh
   gh release create vX.Y.Z --title vX.Y.Z --notes-file <section.md> \
     --prerelease --latest=false --verify-tag
   ```

The git tag `vX.Y.Z` must point at the exact commit that set `version` to
`X.Y.Z` in `.claude-plugin/plugin.json`.
