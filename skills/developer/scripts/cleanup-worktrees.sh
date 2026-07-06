#!/usr/bin/env bash
# cleanup-worktrees.sh — remove linked worktrees and local branches left
# behind by /developer worker jobs.
#
# Deterministic by design: the orchestrator calls this script instead of
# improvising `git worktree remove` / `git branch -D` from prose.
#
# Usage:
#   cleanup-worktrees.sh --branch <glob> [--branch <glob>]... [--sha <sha>]...
#   cleanup-worktrees.sh --sweep [--sha <sha>]...
#
#   --branch  remove linked worktrees whose checked-out branch matches the
#             glob, and delete matching local branches (repeatable)
#   --sha     remove linked worktrees detached at this commit — the
#             diff-reviewer case (repeatable, full SHA)
#   --sweep   shorthand adding the worker patterns agent/* and fix/pr-*;
#             for the final wrap-up pass
#
# Guarantees:
#   - never touches the primary checkout (first entry of `git worktree list`)
#   - never deletes main/master, nor a branch still checked out somewhere
#   - if the primary checkout is in detached HEAD it prints a WARN line and
#     leaves it alone — that is the symptom of a worker having escaped its
#     worktree, and it is for a human to look at
set -euo pipefail

usage() { grep '^# ' "$0" | sed 's/^# //' >&2; exit 2; }

patterns=() shas=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch) [[ $# -ge 2 ]] || usage; patterns+=("$2"); shift 2 ;;
    --sha)    [[ $# -ge 2 ]] || usage; shas+=("$2");     shift 2 ;;
    --sweep)  patterns+=("agent/*" "fix/pr-*");          shift ;;
    *) usage ;;
  esac
done
(( ${#patterns[@]} + ${#shas[@]} > 0 )) || usage

# --- parse `git worktree list --porcelain` ---------------------------------
primary="" primary_head="" primary_on_branch=0
wt_path=() wt_branch=() wt_head=()

path="" branch="" head=""
flush() {
  [[ -n "$path" ]] || return 0
  if [[ -z "$primary" ]]; then
    primary="$path" primary_head="$head"
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

# --- remove matching linked worktrees ---------------------------------------
removed=0
for i in "${!wt_path[@]}"; do
  match=""
  if [[ -n "${wt_branch[i]}" ]]; then
    for p in "${patterns[@]}"; do
      # shellcheck disable=SC2053  # glob match is intentional
      [[ "${wt_branch[i]}" == $p ]] && { match="branch ${wt_branch[i]}"; break; }
    done
  else
    for s in "${shas[@]}"; do
      [[ "${wt_head[i]}" == "$s" ]] && { match="detached ${wt_head[i]:0:12}"; break; }
    done
  fi
  [[ -n "$match" ]] || continue
  [[ "${wt_path[i]}" == "$primary" ]] && continue        # paranoia guard
  [[ "${wt_branch[i]}" == main || "${wt_branch[i]}" == master ]] && continue
  git worktree remove --force "${wt_path[i]}"
  echo "REMOVED worktree ${wt_path[i]} ($match)"
  removed=$((removed + 1))
done

# --- delete matching local branches (skipped if still checked out) ----------
deleted=0
while IFS= read -r b; do
  [[ "$b" == main || "$b" == master ]] && continue
  for p in "${patterns[@]}"; do
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

git worktree prune

if (( ! primary_on_branch )); then
  echo "WARN primary checkout $primary is in detached HEAD (${primary_head:0:12}) — a worker likely ran git outside its worktree. Left untouched; restore with: git -C '$primary' checkout main"
fi
echo "OK removed=$removed branches_deleted=$deleted"
