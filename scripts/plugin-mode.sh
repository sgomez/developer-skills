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

# Which mode a Source: line means. Never compare it to REMOTE_NEXT_SOURCE
# character for character: the CLI prints its own rendering of the source
# ("Git (https://…git@next)", "GitHub (owner/repo)"), not the string that was
# passed to `marketplace add`, and that rendering is not ours to pin. An exact
# match here silently classified next mode as prod, which made `refresh` exit
# with "Not in dev or next mode" — so a whole cycle's commits never reached
# the install while `status` reported everything as fine.
source_mode() {
  local src="$1"
  case "$src" in
    "")            echo none ;;
    *"$REPO_DIR"*) echo dev ;;
    *"$GITHUB_SOURCE"*)
      if [[ "$src" == *"@$DEV_BRANCH"* || "$src" == *"#$DEV_BRANCH"* ]]; then
        echo next
      else
        echo prod
      fi ;;
    *)             echo other ;;
  esac
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

plugin_version() {
  sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    "$REPO_DIR/.claude-plugin/plugin.json" | head -1
}

installed_root() {
  echo "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/$MARKETPLACE/$PLUGIN/$(plugin_version)"
}

# next mode installs from GitHub, so an unpushed commit simply is not in it —
# and because the version string is static for the whole cycle, nothing in
# `claude plugin list` says so. This is the one check that catches a refresh
# run a minute too early.
warn_unpushed_next() {
  local local_sha remote_sha
  local_sha="$(git -C "$REPO_DIR" rev-parse "$DEV_BRANCH" 2>/dev/null || true)"
  remote_sha="$(git -C "$REPO_DIR" ls-remote origin "$DEV_BRANCH" 2>/dev/null | awk 'NR==1 {print $1}')"
  [[ -n "$local_sha" && -n "$remote_sha" && "$local_sha" != "$remote_sha" ]] || return 0
  bold "WARNING: local '$DEV_BRANCH' (${local_sha:0:8}) differs from origin (${remote_sha:0:8})."
  note "next mode installs from GitHub — anything unpushed is NOT in the install."
  note "Push, then run: $0 refresh"
}

# What is actually loaded? Compares the installed copy against the tree it is
# supposed to mirror (this checkout in dev mode, origin/<branch> in next mode).
# The version string cannot answer this: it is the same all cycle.
report_installed() {
  local mode="$1" root expected tmp=""
  root="$(installed_root)"
  if [[ ! -d "$root" ]]; then
    note "Installed copy not found under $root — cannot verify what is loaded."
    return 0
  fi
  if [[ "$mode" == dev ]]; then
    expected="$REPO_DIR"
  else
    git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1 || {
      note "No local checkout here — cannot verify the installed copy."
      return 0
    }
    tmp="$(mktemp -d)"
    git -C "$REPO_DIR" fetch -q origin "$DEV_BRANCH" 2>/dev/null || true
    git -C "$REPO_DIR" archive "origin/$DEV_BRANCH" 2>/dev/null | tar -x -C "$tmp" || {
      rm -rf "$tmp"
      note "Could not read origin/$DEV_BRANCH — cannot verify the installed copy."
      return 0
    }
    expected="$tmp"
    note "Installed from origin/$DEV_BRANCH ($(git -C "$REPO_DIR" rev-parse --short "origin/$DEV_BRANCH" 2>/dev/null || echo '?'))"
  fi
  local diffs
  diffs="$(diff -rq "$expected/skills" "$root/skills" 2>&1; diff -rq "$expected/agents" "$root/agents" 2>&1; diff -rq "$expected/hooks" "$root/hooks" 2>&1)" || true
  [[ -z "$tmp" ]] || rm -rf "$tmp"
  if [[ -z "$diffs" ]]; then
    note "Installed copy matches the source (skills, agents, hooks)."
  else
    bold "STALE: the installed copy does not match the source."
    echo "$diffs" | sed 's/^/    /'
    note "Run: $0 refresh   (in next mode, push first)"
  fi
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
  report_installed dev
  note "The plugin is installed user-wide from this checkout."
  note "After editing skills/agents here, run: $0 refresh"
  note "Restart Claude Code sessions to load the new code."
}

cmd_next() {
  bold "Switching to NEXT mode (marketplace -> $REMOTE_NEXT_SOURCE)"
  warn_unpushed_next
  uninstall_user_scope
  swap_marketplace "$REMOTE_NEXT_SOURCE"
  claude plugin install "$PLUGIN@$MARKETPLACE" --scope user
  bold "Next mode active."
  report_installed next
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
  local src mode
  src="$(current_source)"
  mode="$(source_mode "$src")"
  case "$mode" in
    dev)
      require_dev_branch
      bold "Re-syncing the local marketplace and plugin (dev mode)" ;;
    next)
      bold "Re-syncing the remote marketplace and plugin (next mode)"
      warn_unpushed_next ;;
    *)
      bold "Not in dev or next mode (source: ${src:-none}) — run: $0 dev  or  $0 next"
      exit 1 ;;
  esac
  claude plugin marketplace update "$MARKETPLACE"
  # Installs are copies keyed by version; `plugin update` skips when the
  # version is unchanged, so force a fresh copy with uninstall + install.
  uninstall_user_scope
  claude plugin install "$PLUGIN@$MARKETPLACE" --scope user
  report_installed "$mode"
  note "Restart Claude Code sessions to load the refreshed code."
}

cmd_status() {
  local src mode
  src="$(current_source)"
  mode="$(source_mode "$src")"
  case "$mode" in
    none) bold "Mode: NONE — marketplace '$MARKETPLACE' is not configured" ;;
    dev)  bold "Mode: DEV — marketplace '$MARKETPLACE' -> $src" ;;
    next) bold "Mode: NEXT — marketplace '$MARKETPLACE' -> $src"
          warn_unpushed_next ;;
    *)    bold "Mode: PROD — marketplace '$MARKETPLACE' -> $src" ;;
  esac
  echo
  claude plugin list 2>/dev/null | grep -A3 "$PLUGIN@$MARKETPLACE" ||
    note "$PLUGIN@$MARKETPLACE is not installed in this scope context."
  echo
  case "$mode" in
    dev|next) report_installed "$mode" ;;
  esac
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
