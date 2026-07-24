#!/usr/bin/env bash
# Regression tests for skills/developer/scripts/cleanup-worktrees.sh.
#
# Self-contained: builds throwaway git fixtures (bare origin + clone) under a
# temp dir and asserts the script's REMOVED / DELETED / KEPT / ABORT
# behavior — above all the loss-proof guarantees: no dirty worktree removed,
# no branch deleted whose tip is not on a remote, no sweep reach beyond
# .claude/worktrees/. Run directly:
#
#   bash tests/cleanup-worktrees.test.sh
#
# Exits 0 with a PASS summary, or 1 listing every failed assertion.
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/skills/developer/scripts/cleanup-worktrees.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

T="" checks=0 fails=0
pass() { checks=$((checks + 1)); }
fail() { checks=$((checks + 1)); fails=$((fails + 1)); echo "FAIL [$T] $*" >&2; }

assert_contains()     { case "$1" in *"$2"*) pass ;; *) fail "output should contain: $2"; echo "--- output was:"; echo "$1" ;; esac; }
assert_not_contains() { case "$1" in *"$2"*) fail "output should NOT contain: $2"; echo "--- output was:"; echo "$1" ;; *) pass ;; esac; }
assert_rc()           { [[ "$RC" -eq "$1" ]] && pass || fail "expected exit $1, got $RC"; }
assert_branch()       { git -C "$R" show-ref --verify --quiet "refs/heads/$1" && pass || fail "branch $1 should exist"; }
assert_no_branch()    { git -C "$R" show-ref --verify --quiet "refs/heads/$1" && fail "branch $1 should be gone" || pass; }
assert_dir()          { [[ -d "$1" ]] && pass || fail "dir should exist: $1"; }
assert_no_dir()       { [[ -d "$1" ]] && fail "dir should be gone: $1" || pass; }

# new_fixture <name> — bare origin + clone with a pushed main; sets $R (repo)
# and $W (the harness worker-worktree dir inside it).
new_fixture() {
  local d="$TMP/$1"
  mkdir -p "$d"
  git init -q --bare "$d/origin.git"
  git clone -q "$d/origin.git" "$d/repo" 2>/dev/null
  git -C "$d/repo" config user.email test@example.com
  git -C "$d/repo" config user.name test
  git -C "$d/repo" commit -q --allow-empty -m init
  git -C "$d/repo" branch -q -M main
  git -C "$d/repo" push -q origin main 2>/dev/null
  R="$d/repo" W="$d/repo/.claude/worktrees"
  mkdir -p "$W"
}

# mkwt <branch> <path> — branch off main, linked worktree at <path>, one
# commit inside so the branch diverges and the worktree ends clean.
mkwt() {
  git -C "$R" branch -q "$1" main
  git -C "$R" worktree add -q "$2" "$1"
  ( cd "$2" && echo work > "f-${1//\//-}.txt" && git add . && git commit -q -m "work on $1" )
}
pushbr() { git -C "$R" push -q origin "$1" 2>/dev/null; }

# run <repo> <args...> — sets $OUT and $RC
run() {
  local repo="$1"; shift
  RC=0
  OUT="$(cd "$repo" && bash "$SCRIPT" "$@" 2>&1)" || RC=$?
}

# --- targeted --branch: pushed branch + clean worktree → both removed -------
T="targeted-pushed"
new_fixture t1
mkwt agent/issue-01-a "$W/wt1"; pushbr agent/issue-01-a
run "$R" --branch 'agent/issue-01-*'
assert_rc 0
assert_contains "$OUT" "REMOVED worktree"
assert_contains "$OUT" "DELETED branch agent/issue-01-a"
assert_no_dir "$W/wt1"
assert_no_branch agent/issue-01-a
assert_contains "$OUT" "OK removed=1 branches_deleted=1 kept=0 leftover=0"

# --- unpushed branch: worktree goes, branch is the only copy and stays ------
T="unpushed-branch-kept"
new_fixture t2
mkwt agent/issue-02-b "$W/wt1"                     # never pushed
run "$R" --branch 'agent/issue-02-*'
assert_rc 0
assert_contains "$OUT" "REMOVED worktree"
assert_contains "$OUT" "KEPT branch agent/issue-02-b (tip not on any remote"
assert_no_dir "$W/wt1"
assert_branch agent/issue-02-b

# --- dirty worktree: kept with reason, branch survives via checkout guard ---
T="dirty-worktree-kept"
new_fixture t3
mkwt agent/issue-03-c "$W/wt1"; pushbr agent/issue-03-c
echo scratch > "$W/wt1/untracked-junk.txt"
run "$R" --branch 'agent/issue-03-*'
assert_rc 0
assert_contains "$OUT" "KEPT worktree"
assert_contains "$OUT" "dirty — 1 uncommitted path"
assert_dir "$W/wt1"
assert_contains "$OUT" "KEPT branch agent/issue-03-c (still checked out elsewhere)"
assert_branch agent/issue-03-c

# --- --sha: detached reviewer worktree removed ------------------------------
T="sha-detached"
new_fixture t4
sha="$(git -C "$R" rev-parse main)"
git -C "$R" worktree add -q --detach "$W/rev1" main
run "$R" --sha "$sha"
assert_rc 0
assert_contains "$OUT" "REMOVED worktree"
assert_no_dir "$W/rev1"

# --- sweep is path-only: worker dir swept, the rest of the repo untouched ---
T="sweep-path-only"
new_fixture t5
mkwt improvised/name-1 "$W/wt1"; pushbr improvised/name-1
mkwt agent/issue-99-z "$TMP/t5/outside-wt"; pushbr agent/issue-99-z
git -C "$R" branch -q agent/old-run main           # stray branch, no worktree
run "$R" --sweep
assert_rc 0
assert_contains "$OUT" "DELETED branch improvised/name-1"
assert_no_branch improvised/name-1
assert_no_dir "$W/wt1"
assert_dir "$TMP/t5/outside-wt"                    # worker-named, outside dir: out of reach
assert_branch agent/issue-99-z
assert_not_contains "$OUT" "outside-wt"
assert_branch agent/old-run                        # no worktree in this pass: never reaped
assert_contains "$OUT" "leftover=0"

# --- sweep + dirty worker worktree: KEPT and honestly counted as LEFTOVER ---
T="sweep-dirty-leftover"
new_fixture t6
mkwt agent/issue-04-d "$W/wt1"; pushbr agent/issue-04-d
echo scratch > "$W/wt1/junk.txt"
run "$R" --sweep
assert_rc 0
assert_contains "$OUT" "KEPT worktree"
assert_contains "$OUT" "LEFTOVER worktree"
assert_contains "$OUT" "leftover=1"
assert_dir "$W/wt1"
assert_branch agent/issue-04-d

# --- --max-branches: cap trips, nothing deleted, worktrees already gone -----
T="max-branches-cap"
new_fixture t7
for n in 1 2 3; do mkwt "agent/cap-$n" "$W/wt$n"; pushbr "agent/cap-$n"; done
run "$R" --sweep --max-branches 2
assert_rc 3
assert_contains "$OUT" "WOULD-DELETE branch agent/cap-1"
assert_contains "$OUT" "WOULD-DELETE branch agent/cap-3"
assert_contains "$OUT" "ABORT 3 branches exceed --max-branches=2"
assert_not_contains "$OUT" "DELETED branch"
for n in 1 2 3; do assert_branch "agent/cap-$n"; assert_no_dir "$W/wt$n"; done

# --- --keep-branches: worktree goes, branch untouched even though pushed ----
T="keep-branches"
new_fixture t8
mkwt agent/issue-05-e "$W/wt1"; pushbr agent/issue-05-e
run "$R" --branch 'agent/issue-05-*' --keep-branches
assert_rc 0
assert_contains "$OUT" "REMOVED worktree"
assert_not_contains "$OUT" "DELETED branch"
assert_branch agent/issue-05-e

# --- no remote at all (local code host): no branch ever passes the gate -----
T="no-remote"
d="$TMP/t9"; mkdir -p "$d"
git init -q "$d/repo"
git -C "$d/repo" config user.email test@example.com
git -C "$d/repo" config user.name test
git -C "$d/repo" commit -q --allow-empty -m init
git -C "$d/repo" branch -q -M main
R="$d/repo" W="$d/repo/.claude/worktrees"
mkdir -p "$W"
mkwt agent/issue-06-f "$W/wt1"
run "$R" --branch 'agent/issue-06-*'
assert_rc 0
assert_contains "$OUT" "REMOVED worktree"
assert_contains "$OUT" "KEPT branch agent/issue-06-f (tip not on any remote"
assert_branch agent/issue-06-f

# --- main is untouchable even when a glob names it outright -----------------
T="main-protected"
new_fixture t10
run "$R" --branch 'main'
assert_rc 0
assert_branch main
assert_contains "$OUT" "OK removed=0 branches_deleted=0 kept=0 leftover=0"

# --- no selector at all → usage, exit 2 -------------------------------------
T="usage"
new_fixture t11
run "$R"
assert_rc 2

echo
if (( fails > 0 )); then
  echo "FAILED: $fails of $checks assertions"
  exit 1
fi
echo "PASS: all $checks assertions"
