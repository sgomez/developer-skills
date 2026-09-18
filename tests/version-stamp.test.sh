#!/usr/bin/env bash
# Regression tests for .githooks/pre-commit, which stamps the `-next`
# pre-release in .claude-plugin/plugin.json with the commit time so every
# commit on a cycle carries its own version.
#
# Pins: a `-next` version gets stamped (and a stamped one re-stamped), a bare
# release version is left alone, the stamp lands in the commit itself and in
# the working tree, and unstaged edits to the file are neither committed nor
# lost. Self-contained: builds throwaway git repos under a temp dir. Run
# directly:
#
#   bash tests/version-stamp.test.sh
#
# Exits 0 with a PASS summary, or 1 listing every failed assertion.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ROOT/.githooks/pre-commit"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

T="" checks=0 fails=0
pass() { checks=$((checks + 1)); }
fail() { checks=$((checks + 1)); fails=$((fails + 1)); echo "FAIL [$T] $*" >&2; }
expect() { # expect <description> <actual> <extended regex>
  [[ "$2" =~ $3 ]] && pass || fail "$1: got '$2', want /$3/"
}

manifest() {
  printf '{\n  "name": "p",\n  "description": "%s",\n  "version": "%s"\n}\n' "$2" "$1"
}

# new_repo <version> — a repo whose first commit holds that manifest, hook on.
new_repo() {
  local d="$TMP/repo$((checks + fails))-$RANDOM"
  mkdir -p "$d/.claude-plugin" "$d/.githooks"
  git -C "$d" init -q
  git -C "$d" config user.email t@example.com
  git -C "$d" config user.name t
  manifest "$1" first >"$d/.claude-plugin/plugin.json"
  git -C "$d" add -A
  git -C "$d" commit -q --no-verify -m init
  cp "$HOOK" "$d/.githooks/pre-commit"
  git -C "$d" config core.hooksPath .githooks
  echo "$d"
}

committed_version() { git -C "$1" show HEAD:.claude-plugin/plugin.json | sed -n 's/.*"version": "\(.*\)".*/\1/p'; }
worktree_version() { sed -n 's/.*"version": "\(.*\)".*/\1/p' "$1/.claude-plugin/plugin.json"; }

STAMP='^0\.24\.0-next\.[0-9]{14}$'

T="next-version-stamped"
R="$(new_repo 0.24.0-next)"
echo x >"$R/a"; git -C "$R" add a; git -C "$R" commit -q -m one
expect "committed" "$(committed_version "$R")" "$STAMP"
expect "working tree" "$(worktree_version "$R")" "$STAMP"
[[ -z "$(git -C "$R" status --porcelain --untracked-files=no)" ]] && pass || fail "tree not clean after commit"

T="stamped-version-restamped"
first="$(committed_version "$R")"
sleep 1
echo y >"$R/a"; git -C "$R" add a; git -C "$R" commit -q -m two
second="$(committed_version "$R")"
expect "second commit" "$second" "$STAMP"
[[ "$second" > "$first" ]] && pass || fail "second stamp '$second' does not sort after '$first'"

T="release-version-untouched"
R="$(new_repo 0.24.0)"
echo x >"$R/a"; git -C "$R" add a; git -C "$R" commit -q -m release
expect "committed" "$(committed_version "$R")" '^0\.24\.0$'

T="unstaged-edit-preserved"
R="$(new_repo 0.24.0-next)"
manifest 0.24.0-next "edited, not staged" >"$R/.claude-plugin/plugin.json"
echo x >"$R/a"; git -C "$R" add a; git -C "$R" commit -q -m one
git -C "$R" show HEAD:.claude-plugin/plugin.json | grep -q '"description": "first"' &&
  pass || fail "unstaged description leaked into the commit"
grep -q '"description": "edited, not staged"' "$R/.claude-plugin/plugin.json" &&
  pass || fail "unstaged description lost from the working tree"
expect "working tree" "$(worktree_version "$R")" "$STAMP"

if [[ "$fails" -gt 0 ]]; then
  echo "FAILED: $fails of $checks assertions" >&2
  exit 1
fi
echo "PASS: all $checks assertions"
