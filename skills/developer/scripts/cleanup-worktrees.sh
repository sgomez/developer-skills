#!/usr/bin/env bash
# cleanup-worktrees.sh — remove linked worktrees and local branches left
# behind by /developer worker jobs.
#
# Deterministic by design: the orchestrator calls this script instead of
# improvising `git worktree remove` / `git branch -D` from prose. And
# loss-proof by construction: it refuses to destroy the only copy of
# anything — a worktree with uncommitted changes is kept, and a branch is
# deleted only when its tip is contained in a remote-tracking ref, so every
# branch it deletes is restorable with `git branch <name> <remote>/<name>`.
#
# Usage:
#   cleanup-worktrees.sh --branch <glob> [--branch <glob>]... [--sha <sha>]... [--keep-branches] [--max-branches <n>]
#   cleanup-worktrees.sh --sweep [--branch <glob>]... [--sha <sha>]... [--keep-branches] [--max-branches <n>]
#
#   --branch  remove linked worktrees whose checked-out branch matches the
#             glob, and delete matching local branches (repeatable). An
#             explicit --branch glob is caller-scoped, so it targets matching
#             branches repo-wide, worktree or not — pass names narrowed to the
#             run (e.g. agent/issue-<subissue>-*), never a bare agent/*.
#   --sha     remove linked worktrees detached at this commit — the
#             diff-reviewer case (repeatable, full SHA)
#   --sweep   the final wrap-up pass: removes every linked worktree under the
#             primary checkout's .claude/worktrees/ — branch or detached, any
#             name. That path holds only harness-created worker worktrees; the
#             sweep assumes no other agent session is live on this repo. It
#             matches by path ONLY: a worktree elsewhere is reached only by an
#             explicit --branch/--sha, and a branch that had no worktree in
#             this pass is never deleted (those belong to other runs).
#   --keep-branches
#             remove only the worktrees; never delete local branches. For
#             local code hosts, where the branch is the only copy of the work
#             (with no remote-tracking refs the containment gate below keeps
#             every branch anyway — the flag states the intent outright).
#   --max-branches <n>
#             safety cap: if a single invocation would delete more than <n>
#             local branches (counting only those that passed the containment
#             gate), delete none of them, print a WOULD-DELETE line per
#             candidate and an ABORT line, and exit 3 — the worktrees are
#             already removed (non-destructive) but the branches are left for
#             a human to look at. Default 20; 0 disables the cap.
#
# Output contract:
#   REMOVED / DELETED / KEPT / FAILED lines as work happens — every KEPT
#   carries its reason (dirty worktree; branch tip not on any remote; branch
#   checked out elsewhere); with --sweep, a LEFTOVER line per worker worktree
#   still present after the pass; WARN if the primary checkout is in detached
#   HEAD or on a worker branch; on a cap trip, WOULD-DELETE lines then an
#   ABORT line (exit 3); final line
#   `OK removed=<n> branches_deleted=<n> kept=<n> leftover=<n>`.
#
# Guarantees:
#   - never touches the primary checkout (first entry of `git worktree list`)
#   - never removes a worktree with uncommitted changes — staged, unstaged,
#     or untracked files are grounds to keep it and say why
#   - never deletes main/master, a branch still checked out somewhere, or a
#     branch whose tip is not contained in a remote-tracking ref — anything
#     it deletes is restorable from the remote
#   - never deletes more than --max-branches branches in one invocation
#   - the sweep never deletes a branch that had no worktree in this pass, and
#     never matches a worktree outside .claude/worktrees/ by name
#   - if the primary checkout is in detached HEAD or checked out on a worker
#     branch (agent/*, fix/pr-*, worktree-agent-*) it prints a WARN line and
#     leaves it alone — that is the symptom of a worker having escaped its
#     worktree, and it is for a human to look at
set -euo pipefail

usage() { grep '^# ' "$0" | sed 's/^# //' >&2; exit 2; }

# user_patterns come from explicit --branch flags (caller-scoped, applied
# repo-wide); --sweep adds no name patterns — it matches worker worktrees by
# path alone, further down.
user_patterns=() shas=() keep_branches=0 sweep=0 max_branches=20
while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch) [[ $# -ge 2 ]] || usage; user_patterns+=("$2"); shift 2 ;;
    --sha)    [[ $# -ge 2 ]] || usage; shas+=("$2");          shift 2 ;;
    --sweep)  sweep=1;                                        shift ;;
    --keep-branches) keep_branches=1;                         shift ;;
    --max-branches) [[ $# -ge 2 && "$2" =~ ^[0-9]+$ ]] || usage; max_branches="$2"; shift 2 ;;
    *) usage ;;
  esac
done
(( ${#user_patterns[@]} + ${#shas[@]} + sweep > 0 )) || usage

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

# Uncommitted-path count: staged, unstaged, and untracked (non-ignored) files
# all count. If git cannot answer (broken worktree link) this reports 0 and
# the `git worktree remove` below decides.
dirty_count() { git -C "$1" status --porcelain 2>/dev/null | awk 'END { print NR }' || true; }

# The containment gate: a branch may be deleted only when its tip is
# contained in at least one remote-tracking ref — the commits provably exist
# outside refs/heads, and `git branch <name> <remote>/<name>` restores the
# ref itself. No remotes (local code host) means nothing ever passes.
on_remote() { [[ -n "$(git branch -r --contains "refs/heads/$1" 2>/dev/null)" ]]; }

# --- remove matching linked worktrees ---------------------------------------
# removed_branches collects the branch of every worktree actually removed —
# these are this pass's own branches, the only ones the sweep may reap
# (unless --keep-branches). Branch reaping never guesses beyond them plus
# explicit --branch globs, and the containment gate below vets every one.
removed=0 failed=0 kept=0
removed_branches=()
for i in ${wt_path[@]+"${!wt_path[@]}"}; do
  match=""
  if [[ -n "${wt_branch[i]}" ]]; then
    for p in ${user_patterns[@]+"${user_patterns[@]}"}; do
      # shellcheck disable=SC2053  # glob match is intentional
      [[ "${wt_branch[i]}" == $p ]] && { match="branch ${wt_branch[i]}"; break; }
    done
  else
    for s in ${shas[@]+"${shas[@]}"}; do
      [[ "${wt_head[i]}" == "$s" ]] && { match="detached ${wt_head[i]:0:12}"; break; }
    done
  fi
  # The sweep matches by path, and by path only: every worker worktree under
  # .claude/worktrees/, branch or detached, improvised name or not. A
  # worktree outside that directory is never the sweep's to take, whatever
  # its branch is called.
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
  dirty=$(dirty_count "${wt_path[i]}")
  if [[ "$dirty" != 0 ]]; then
    echo "KEPT worktree ${wt_path[i]} ($match; dirty — $dirty uncommitted path(s); inspect and remove by hand)"
    kept=$((kept + 1))
    continue
  fi
  if git worktree remove --force "${wt_path[i]}"; then
    echo "REMOVED worktree ${wt_path[i]} ($match)"
    removed=$((removed + 1))
    [[ -n "${wt_branch[i]}" ]] && removed_branches+=("${wt_branch[i]}")
  else
    echo "FAILED worktree ${wt_path[i]} ($match)"
    failed=$((failed + 1))
  fi
done

# --- delete local branches ---------------------------------------------------
# Candidates come from two sources, both narrow by construction:
#   1. the branches of the worktrees just removed (this pass's own work);
#   2. branches matching an explicit --branch glob (caller-scoped to the run).
# Every candidate must then pass the containment gate — a tip no remote-
# tracking ref contains is (or may be) the only copy of its commits, and is
# kept no matter what matched it.
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

  deletable=()
  for b in ${candidates[@]+"${candidates[@]}"}; do
    if on_remote "$b"; then
      deletable+=("$b")
    else
      echo "KEPT branch $b (tip not on any remote — possibly the only copy of its commits; push or delete it yourself)"
      kept=$((kept + 1))
    fi
  done

  if (( max_branches > 0 && ${#deletable[@]} > max_branches )); then
    for b in "${deletable[@]}"; do echo "WOULD-DELETE branch $b"; done
    echo "ABORT ${#deletable[@]} branches exceed --max-branches=$max_branches; deleted none. Worktrees are already removed, and every branch listed above is on the remote. Re-run with --max-branches <n> once you have confirmed the list, or delete them by hand."
    exit 3
  fi

  for b in ${deletable[@]+"${deletable[@]}"}; do
    if git branch -D "$b" >/dev/null 2>&1; then
      echo "DELETED branch $b"
      deleted=$((deleted + 1))
    else
      echo "KEPT branch $b (still checked out elsewhere)"
      kept=$((kept + 1))
    fi
  done
fi

git worktree prune

# --- leftover report ---------------------------------------------------------
# The sweep re-checks the filesystem after the prune — not git: a failed
# removal can leave a directory on disk that the prune has already dropped
# from git's metadata, and that dir must not be reported as swept. A KEPT
# (dirty) worker worktree shows up here too — the LEFTOVER line is the
# wrap-up's contract, the KEPT line above it is the reason.
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
echo "OK removed=$removed branches_deleted=$deleted kept=$kept leftover=$leftover"
