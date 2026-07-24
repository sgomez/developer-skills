#!/usr/bin/env bash
# cleanup-worktrees.sh — remove linked worktrees and local branches left
# behind by /developer worker jobs.
#
# Deterministic by design: the orchestrator calls this script instead of
# improvising `git worktree remove` / `git branch -D` from prose.
#
# Usage:
#   cleanup-worktrees.sh --branch <glob> [--branch <glob>]... [--sha <sha>]... [--keep-branches]
#   cleanup-worktrees.sh --sweep [--sha <sha>]... [--keep-branches]
#
#   --branch  remove linked worktrees whose checked-out branch matches the
#             glob, and delete matching local branches (repeatable)
#   --sha     remove linked worktrees detached at this commit — the
#             diff-reviewer case (repeatable, full SHA)
#   --sweep   the final wrap-up pass: adds the worker patterns agent/*,
#             fix/pr-* and worktree-agent-* (the harness's own worktree
#             branches), and additionally removes every linked worktree under
#             the primary checkout's .claude/worktrees/ — branch or detached —
#             deleting its branch too. That path holds only harness-created
#             worker worktrees; the sweep assumes no other agent session is
#             live on this repo.
#   --keep-branches
#             remove only the worktrees; never delete local branches. For
#             local code hosts, where the branch is the only copy of the work
#
# Output contract:
#   REMOVED / DELETED / KEPT / FAILED lines as work happens; with --sweep, a
#   LEFTOVER line per worker worktree still present after the pass; WARN if
#   the primary checkout is in detached HEAD or on a worker branch; final line
#   `OK removed=<n> branches_deleted=<n> leftover=<n>`.
#
# Guarantees:
#   - never touches the primary checkout (first entry of `git worktree list`)
#   - never deletes main/master, nor a branch still checked out somewhere
#   - if the primary checkout is in detached HEAD or checked out on a worker
#     branch (agent/*, fix/pr-*, worktree-agent-*) it prints a WARN line and
#     leaves it alone — that is the symptom of a worker having escaped its
#     worktree, and it is for a human to look at
set -euo pipefail

usage() { grep '^# ' "$0" | sed 's/^# //' >&2; exit 2; }

patterns=() shas=() keep_branches=0 sweep=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch) [[ $# -ge 2 ]] || usage; patterns+=("$2"); shift 2 ;;
    --sha)    [[ $# -ge 2 ]] || usage; shas+=("$2");     shift 2 ;;
    --sweep)  sweep=1; patterns+=("agent/*" "fix/pr-*" "worktree-agent-*"); shift ;;
    --keep-branches) keep_branches=1;                    shift ;;
    *) usage ;;
  esac
done
(( ${#patterns[@]} + ${#shas[@]} > 0 )) || usage

# --- parse `git worktree list --porcelain` ---------------------------------
primary="" primary_head="" primary_branch="" primary_on_branch=0
wt_path=() wt_branch=() wt_head=()

path="" branch="" head=""
flush() {
  [[ -n "$path" ]] || return 0
  if [[ -z "$primary" ]]; then
    primary="$path" primary_head="$head" primary_branch="$branch"
    [[ -n "$branch" ]] && primary_on_branch=1
  else
    wt_path+=("$path") wt_branch+=("$branch") wt_head+=("$head")
  fi
  path="" branch="" head=""
}
while IFS= read -r line; do
  case "$line" in
    "worktree "*)          path="${line#worktree }" ;;
    "HEAD "*)              head="${line#HEAD }" ;;
    "branch refs/heads/"*) branch="${line#branch refs/heads/}" ;;
    "")                    flush ;;
  esac
done < <(git worktree list --porcelain)
flush

# Operate from the primary checkout: if this script was launched from a
# worktree it is about to remove, every later git call would lose its cwd.
cd "$primary"
worker_dir="$primary/.claude/worktrees/"

# --- remove matching linked worktrees ---------------------------------------
removed=0 failed=0
extra_branches=()
for i in "${!wt_path[@]}"; do
  match="" by_path=0
  if [[ -n "${wt_branch[i]}" ]]; then
    for p in ${patterns[@]+"${patterns[@]}"}; do
      # shellcheck disable=SC2053  # glob match is intentional
      [[ "${wt_branch[i]}" == $p ]] && { match="branch ${wt_branch[i]}"; break; }
    done
  else
    for s in ${shas[@]+"${shas[@]}"}; do
      [[ "${wt_head[i]}" == "$s" ]] && { match="detached ${wt_head[i]:0:12}"; break; }
    done
  fi
  # The sweep also matches by path: worker worktrees whose branch fits no
  # glob (an improvised name) or whose detached sha was superseded by later
  # pushes (a reviewer from before a fix cycle).
  if [[ -z "$match" && $sweep -eq 1 && "${wt_path[i]}" == "$worker_dir"* ]]; then
    by_path=1
    if [[ -n "${wt_branch[i]}" ]]; then
      match="worker path, branch ${wt_branch[i]}"
    else
      match="worker path, detached ${wt_head[i]:0:12}"
    fi
  fi
  [[ -n "$match" ]] || continue
  [[ "${wt_path[i]}" == "$primary" ]] && continue        # paranoia guard
  [[ "${wt_branch[i]}" == main || "${wt_branch[i]}" == master ]] && continue
  if git worktree remove --force "${wt_path[i]}"; then
    echo "REMOVED worktree ${wt_path[i]} ($match)"
    removed=$((removed + 1))
    (( by_path )) && [[ -n "${wt_branch[i]}" ]] && extra_branches+=("${wt_branch[i]}")
  else
    echo "FAILED worktree ${wt_path[i]} ($match)"
    failed=$((failed + 1))
  fi
done

# --- delete matching local branches (skipped if still checked out) ----------
deleted=0
(( keep_branches )) && { patterns=(); extra_branches=(); }
while IFS= read -r b; do
  [[ "$b" == main || "$b" == master ]] && continue
  for p in ${patterns[@]+"${patterns[@]}"}; do
    # shellcheck disable=SC2053
    if [[ "$b" == $p ]]; then
      if git branch -D "$b" >/dev/null 2>&1; then
        echo "DELETED branch $b"
        deleted=$((deleted + 1))
      else
        echo "KEPT branch $b (still checked out elsewhere)"
      fi
      break
    fi
  done
done < <(git for-each-ref --format='%(refname:short)' refs/heads)

# Branches freed by a path-matched removal (improvised names no glob covers).
for b in ${extra_branches[@]+"${extra_branches[@]}"}; do
  [[ "$b" == main || "$b" == master ]] && continue
  git show-ref --verify --quiet "refs/heads/$b" || continue   # already gone
  if git branch -D "$b" >/dev/null 2>&1; then
    echo "DELETED branch $b"
    deleted=$((deleted + 1))
  else
    echo "KEPT branch $b (still checked out elsewhere)"
  fi
done

git worktree prune

# --- leftover report ---------------------------------------------------------
# The sweep re-checks the filesystem after the prune — not git: a failed
# removal can leave a directory on disk that the prune has already dropped
# from git's metadata, and that dir must not be reported as swept.
leftover=$failed
if (( sweep )); then
  leftover=0
  for d in "$worker_dir"*; do
    [[ -e "$d" ]] || continue
    echo "LEFTOVER worktree $d"
    leftover=$((leftover + 1))
  done
fi

if (( ! primary_on_branch )); then
  echo "WARN primary checkout $primary is in detached HEAD (${primary_head:0:12}) — a worker likely ran git outside its worktree. Left untouched; restore with: git -C '$primary' checkout main"
elif [[ "$primary_branch" == agent/* || "$primary_branch" == fix/pr-* || "$primary_branch" == worktree-agent-* ]]; then
  echo "WARN primary checkout $primary is on worker branch $primary_branch — a worker likely ran git outside its worktree. Left untouched; restore with: git -C '$primary' checkout main"
fi
echo "OK removed=$removed branches_deleted=$deleted leftover=$leftover"
