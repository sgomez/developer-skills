#!/usr/bin/env bash
# plugin-mode.sh — toggle the sgomez marketplace between prod (published GitHub
# marketplace), dev (this checkout's uncommitted changes), and next (the
# pushed "next" branch on GitHub, testable from any machine).
#
#   scripts/plugin-mode.sh dev       # marketplace -> this checkout (branch: next), install user-wide
#   scripts/plugin-mode.sh next      # marketplace -> GitHub "next" branch (any machine), install user-wide
#   scripts/plugin-mode.sh prod      # marketplace -> GitHub default branch, remove the user-wide install
#   scripts/plugin-mode.sh refresh   # dev/next only: pick up latest changes (re-sync + update)
#   scripts/plugin-mode.sh status    # which mode is active, what is installed
#
# `dev` copies this checkout into the install, so it only works on this
# machine but needs no push — good for testing edits before they're
# committed. `next` instead points at the pushed "next" branch on GitHub via
# a git ref (owner/repo.git#next), so the exact same command works on any
# machine, even one without this checkout — but it only sees changes once
# they're pushed to "next". `dev`/`refresh` (in dev mode) refuse to run from
# any branch other than "next" to keep the copy meaningful; `next` has no
# such requirement since it always pulls from GitHub regardless of your
# local branch.
#
# "next" (both flavors) carries one static pre-release version (X.Y.Z-next)
# for the whole cycle, so the copy/ref-keyed installer sees nothing new and
# would skip an update: dev/next/refresh force uninstall + install instead.
# The suffix tells the loaded build apart from the published release in
# `claude plugin list`; it says nothing about how fresh the copy is, which is
# what `refresh` is for.
#
# The marketplace keeps its name ("sgomez") in every mode, so the plugin id
# developer-skills@sgomez stays stable: any project-scoped install resolves
# against whichever source is active. Restart Claude Code sessions after a
# switch — plugins load at session start.

set -euo pipefail

MARKETPLACE="sgomez"
PLUGIN="developer-skills"
GITHUB_SOURCE="sgomez/developer-skills"
DEV_BRANCH="next"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REMOTE_NEXT_SOURCE="https://github.com/${GITHUB_SOURCE}.git#${DEV_BRANCH}"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
note() { printf '  %s\n' "$*"; }

current_source() {
  # Prints the active source of the sgomez marketplace, or nothing if absent.
  claude plugin marketplace list 2>/dev/null |
    awk -v m="$MARKETPLACE" '
      $0 ~ "^  . " m "$" { hit = 1; next }
      hit && /Source:/    { sub(/^ *Source: */, ""); print; exit }
      hit && /^  ./       { exit }
    '
}

require_dev_branch() {
  # Dev mode copies the working tree, so it must be the "next" branch.
  local branch
  branch="$(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [[ "$branch" != "$DEV_BRANCH" ]]; then
    bold "Dev mode expects the '$DEV_BRANCH' branch, but this checkout is on '${branch:-unknown}'."
    note "Switch with: git switch $DEV_BRANCH"
    exit 1
  fi
}

uninstall_user_scope() {
  # Best-effort: only the user-scope install is ours to manage here.
  claude plugin uninstall "$PLUGIN@$MARKETPLACE" --scope user 2>/dev/null ||
    claude plugin uninstall "$PLUGIN" --scope user 2>/dev/null || true
}

swap_marketplace() {
  local target="$1"
  claude plugin marketplace remove "$MARKETPLACE" 2>/dev/null || true
  claude plugin marketplace add "$target"
}

cmd_dev() {
  require_dev_branch
  bold "Switching to DEV mode (marketplace -> $REPO_DIR, branch: $DEV_BRANCH)"
  uninstall_user_scope
  swap_marketplace "$REPO_DIR"
  claude plugin install "$PLUGIN@$MARKETPLACE" --scope user
  bold "Dev mode active."
  note "The plugin is installed user-wide from this checkout."
  note "After editing skills/agents here, run: $0 refresh"
  note "Restart Claude Code sessions to load the new code."
}

cmd_next() {
  bold "Switching to NEXT mode (marketplace -> $REMOTE_NEXT_SOURCE)"
  uninstall_user_scope
  swap_marketplace "$REMOTE_NEXT_SOURCE"
  claude plugin install "$PLUGIN@$MARKETPLACE" --scope user
  bold "Next mode active."
  note "The plugin is installed user-wide from GitHub's '$DEV_BRANCH' branch."
  note "This is the same command on every machine — push to '$DEV_BRANCH' first."
  note "After pushing new commits to '$DEV_BRANCH', run: $0 refresh"
  note "Restart Claude Code sessions to load the new code."
}

cmd_prod() {
  bold "Switching to PROD mode (marketplace -> github.com/$GITHUB_SOURCE)"
  uninstall_user_scope
  swap_marketplace "$GITHUB_SOURCE"
  bold "Prod mode active."
  note "User-wide dev install removed; the marketplace points at GitHub again."
  note "Project-scoped installs now resolve against the published releases."
  note "Restart Claude Code sessions to apply."
}

cmd_refresh() {
  local src
  src="$(current_source)"
  if [[ "$src" == *"$REPO_DIR"* ]]; then
    require_dev_branch
    bold "Re-syncing the local marketplace and plugin (dev mode)"
  elif [[ "$src" == "$REMOTE_NEXT_SOURCE" ]]; then
    bold "Re-syncing the remote marketplace and plugin (next mode)"
  else
    bold "Not in dev or next mode (source: ${src:-none}) — run: $0 dev  or  $0 next"
    exit 1
  fi
  claude plugin marketplace update "$MARKETPLACE"
  # Installs are copies keyed by version; `plugin update` skips when the
  # version is unchanged, so force a fresh copy with uninstall + install.
  uninstall_user_scope
  claude plugin install "$PLUGIN@$MARKETPLACE" --scope user
  note "Restart Claude Code sessions to load the refreshed code."
}

cmd_status() {
  local src
  src="$(current_source)"
  if [[ -z "$src" ]]; then
    bold "Mode: NONE — marketplace '$MARKETPLACE' is not configured"
  elif [[ "$src" == *"$REPO_DIR"* ]]; then
    bold "Mode: DEV — marketplace '$MARKETPLACE' -> $src"
  elif [[ "$src" == "$REMOTE_NEXT_SOURCE" ]]; then
    bold "Mode: NEXT — marketplace '$MARKETPLACE' -> $src"
  else
    bold "Mode: PROD — marketplace '$MARKETPLACE' -> $src"
  fi
  echo
  claude plugin list 2>/dev/null | grep -A3 "$PLUGIN@$MARKETPLACE" ||
    note "$PLUGIN@$MARKETPLACE is not installed in this scope context."
}

case "${1:-}" in
  dev)     cmd_dev ;;
  next)    cmd_next ;;
  prod)    cmd_prod ;;
  refresh) cmd_refresh ;;
  status)  cmd_status ;;
  *)
    sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
