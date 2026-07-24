#!/usr/bin/env bash
# cleanup-worktrees.sh — remove linked worktrees and local branches left
# behind by /developer worker jobs.
#
# Deterministic by design: the orchestrator calls this script instead of
# improvising `git worktree remove` / `git branch -D` from prose.
#
# Usage:
#   cleanup-worktrees.sh --branch <glob> [--branch <glob>]... [--sha <sha>]... [--keep-branches] [--max-branches <n>]
#   cleanup-worktrees.sh --sweep [--sha <sha>]... [--keep-branches] [--max-branches <n>]
#
#   --branch  remove linked worktrees whose checked-out branch matches the
#             glob, and delete matching local branches (repeatable). An
#             explicit --branch glob is caller-scoped, so it deletes matching
#             branches repo-wide, worktree or not — pass names narrowed to the
#             run (e.g. agent/issue-<subissue>-*), never a bare agent/*.
#   --sha     remove linked worktrees detached at this commit — the
#             diff-reviewer case (repeatable, full SHA)
#   --sweep   the final wrap-up pass: adds the worker patterns agent/*,
#             fix/pr-* and worktree-agent-* (the harness's own worktree
#             branches), and additionally removes every linked worktree under
#             the primary checkout's .claude/worktrees/ — branch or detached.
#             The sweep deletes ONLY the branches of the worktrees it removes
#             in this pass; it never reaps a worker-named branch that has no
#             worktree (those belong to other runs — target them with an
#             explicit --branch). That path holds only harness-created worker
#             worktrees; the sweep assumes no other agent session is live on
#             this repo.
#   --keep-branches
#             remove only the worktrees; never delete local branches. For
#             local code hosts, where the branch is the only copy of the work
#   --max-branches <n>
#             safety cap: if a single invocation would delete more than <n>
#             local branches, delete none of them, print a WOULD-DELETE line
#             per candidate and an ABORT line, and exit 3 — the worktrees are
#             already removed (non-destructive) but the branches are left for
#             a human to look at. Default 20; 0 disables the cap.
#
# Output contract:
#   REMOVED / DELETED / KEPT / FAILED lines as work happens; with --sweep, a
#   LEFTOVER line per worker worktree still present after the pass; WARN if
#   the primary checkout is in detached HEAD or on a worker branch; on a cap
#   trip, WOULD-DELETE lines then an ABORT line (exit 3); final line
#   `OK removed=<n> branches_deleted=<n> leftover=<n>`.
#
# Guarantees:
#   - never touches the primary checkout (first entry of `git worktree list`)
#   - never deletes main/master, nor a branch still checked out somewhere
#   - never deletes more than --max-branches branches in one invocation
#   - the sweep never deletes a branch that had no worktree in this pass
#   - if the primary checkout is in detached HEAD or checked out on a worker
#     branch (agent/*, fix/pr-*, worktree-agent-*) it prints a WARN line and
#     leaves it alone — that is the symptom of a worker having escaped its
#     worktree, and it is for a human to look at
set -euo pipefail

usage() { grep '^# ' "$0" | sed 's/^# //' >&2; exit 2; }

# user_patterns come from explicit --branch flags (caller-scoped, reaped
# repo-wide); sweep_patterns are the broad worker globs --sweep adds, used
# only to match worktrees for removal — never to reap branches on their own.
user_patterns=() sweep_patterns=() shas=() keep_branches=0 sweep=0 max_branches=20
while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch) [[ $# -ge 2 ]] || usage; user_patterns+=("$2"); shift 2 ;;
    --sha)    [[ $# -ge 2 ]] || usage; shas+=("$2");          shift 2 ;;
    --sweep)  sweep=1; sweep_patterns+=("agent/*" "fix/pr-*" "worktree-agent-*"); shift ;;
    --keep-branches) keep_branches=1;                         shift ;;
    --max-branches) [[ $# -ge 2 && "$2" =~ ^[0-9]+$ ]] || usage; max_branches="$2"; shift 2 ;;
    *) usage ;;
  esac
done
# Patterns that match a worktree for removal: both the explicit and the sweep
# globs. Branch reaping (below) uses only user_patterns.
patterns=(${user_patterns[@]+"${user_patterns[@]}"} ${sweep_patterns[@]+"${sweep_patterns[@]}"})
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
# removed_branches collects the branch of every worktree actually removed —
# these are this pass's own branches, always safe to reap (unless
# --keep-branches). Branch reaping never guesses beyond them plus explicit
# --branch globs.
removed=0 failed=0
removed_branches=()
for i in "${!wt_path[@]}"; do
  match=""
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
    [[ -n "${wt_branch[i]}" ]] && removed_branches+=("${wt_branch[i]}")
  else
    echo "FAILED worktree ${wt_path[i]} ($match)"
    failed=$((failed + 1))
  fi
done

# --- delete local branches (skipped if still checked out) -------------------
# Candidates come from two sources, both narrow by construction:
#   1. the branches of the worktrees just removed (this pass's own work);
#   2. branches matching an explicit --branch glob (caller-scoped to the run).
# The sweep's broad worker globs are NOT reaped repo-wide — that is what let a
# forgotten --keep-branches take out unrelated branches from other runs. A
# --max-branches cap then refuses any mass deletion before it happens.
deleted=0
if (( ! keep_branches )); then
  candidates=()
  seen_branch=""
  add_candidate() {
    local b="$1"
    [[ "$b" == main || "$b" == master ]] && return
    git show-ref --verify --quiet "refs/heads/$b" || return   # already gone
    case " $seen_branch " in *" $b "*) return ;; esac
    seen_branch+=" $b"
    candidates+=("$b")
  }
  for b in ${removed_branches[@]+"${removed_branches[@]}"}; do add_candidate "$b"; done
  if (( ${#user_patterns[@]} > 0 )); then
    while IFS= read -r b; do
      for p in "${user_patterns[@]}"; do
        # shellcheck disable=SC2053
        [[ "$b" == $p ]] && { add_candidate "$b"; break; }
      done
    done < <(git for-each-ref --format='%(refname:short)' refs/heads)
  fi

  if (( max_branches > 0 && ${#candidates[@]} > max_branches )); then
    for b in "${candidates[@]}"; do echo "WOULD-DELETE branch $b"; done
    echo "ABORT ${#candidates[@]} branches exceed --max-branches=$max_branches; deleted none. Worktrees are already removed. Re-run with --max-branches <n> once you have confirmed the list above, or delete them by hand."
    exit 3
  fi

  for b in ${candidates[@]+"${candidates[@]}"}; do
    if git branch -D "$b" >/dev/null 2>&1; then
      echo "DELETED branch $b"
      deleted=$((deleted + 1))
    else
      echo "KEPT branch $b (still checked out elsewhere)"
    fi
  done
fi

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
