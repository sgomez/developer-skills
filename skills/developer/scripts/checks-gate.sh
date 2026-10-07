#!/usr/bin/env bash
# checks-gate.sh — the /developer Merge step's checks gate on GitHub, as one
# command with a one-line verdict.
#
# The orchestrator used to run this gate as a sequence of probes — mergeable
# state, wait for checks to register, wait for them to finish, read the
# failures, wait for the run, classify it — each one a turn that re-read the
# orchestrator's whole context. This script does the sequence in one call and
# prints only the verdict, so the gate costs one turn whatever CI does. It can
# wait a long time, so the orchestrator runs it as a background Bash call and
# picks the verdict up from the completion notification. That notification
# carries the exit code but not the output, so the exit code is the verdict:
# on GREEN — the usual case — the orchestrator merges without a turn spent
# reading the output, and only a red needs its line.
#
# Read-only: it never updates, re-runs or merges anything. Those are code-host
# writes, and the orchestrator runs them as bare commands of their own (the
# permission rules and the merge hook match the bare command). It never reads
# job logs either — the classification below is the whole diagnosis the
# orchestrator is allowed; the fixer reads the logs from the job URL.
#
# GitHub only (gh). Other hosts gate per their docs/agents/code-host-ci.md.
# Only for repos with CI on PRs: a repo whose code-host doc says `CI: none`
# skips the gate altogether.
#
# Usage:
#   checks-gate.sh <PR> [--max-wait <seconds>]
#
# --max-wait caps the wait the way CHECKS_GATE_MAX_WAIT does: a caller that
# cannot wait an hour in one call (a foreground Bash call is capped at ten
# minutes) passes a shorter cap and re-runs the gate on PENDING. A flag, not
# the variable, so the call keeps the bare `bash …/checks-gate.sh` shape the
# permission rule matches.
#
# Verdicts (one line on stdout; the exit code names it too):
#   GREEN                  (0) every check settled as success/neutral/skipped.
#   DIRTY                 (10) conflicts with the base; GitHub runs no checks on
#                              it. The conflict path, never a red.
#   BEHIND                (11) mergeable but stale, and still so after a short
#                              settle (GitHub can report the old state for a
#                              moment after an update-branch): update the
#                              branch, then gate again.
#   PENDING               (12) checks still running when the wait ran out.
#   NO_CHECKS             (13) nothing registered on the head after the wait,
#                              on a repo that has CI: infra-red.
#   RED code run=<id> url=<job-url>                                     (20)
#                              a failed job executed steps: the change was
#                              exercised and failed.
#   RED code url=<link>   (20) a failing check that is not a GitHub Actions run
#                              (an external status): unclassifiable, and
#                              there is no run to retry.
#   RED infra run=<id> reason=<why>                                     (21)
#                              nothing failed after executing (every failed job
#                              at zero steps, or startup_failure): the code was
#                              never exercised.
#   RED infra reason=never-picked-up                                    (21)
#                              checks still queued and none running after the
#                              queue wait: no runner is taking jobs.
# A run that failed, was re-run and is now green re-gates once instead of
# reporting a red that no longer exists. Code-red wins over infra-red when
# several runs fail.
# Errors: `ERROR <what>` on stdout, exit 1. Usage error: exit 2.
#
# Tunables (seconds / tries; the tests shrink them):
#   CHECKS_GATE_POLL           sleep between probes              (default 15)
#   CHECKS_GATE_STATE_TRIES    probes while mergeable is UNKNOWN (default 8)
#   CHECKS_GATE_BEHIND_TRIES   probes a BEHIND must persist      (default 3)
#   CHECKS_GATE_REGISTER_TRIES probes waiting for a first check  (default 20)
#   CHECKS_GATE_QUEUE_WAIT     cap on checks queued, none running (default 1200)
#   CHECKS_GATE_MAX_WAIT       cap on waiting for checks/runs    (default 3600)
set -uo pipefail

usage() { echo "usage: checks-gate.sh <PR> [--max-wait <seconds>]" >&2; exit 2; }
pr="${1:-}"
[[ "$pr" =~ ^[0-9]+$ ]] || usage
if [[ $# -gt 1 ]]; then
  [[ "$2" == "--max-wait" && "${3:-}" =~ ^[0-9]+$ && $# -eq 3 ]] || usage
  CHECKS_GATE_MAX_WAIT="$3"
fi

POLL="${CHECKS_GATE_POLL:-15}"
STATE_TRIES="${CHECKS_GATE_STATE_TRIES:-8}"
BEHIND_TRIES="${CHECKS_GATE_BEHIND_TRIES:-3}"
REGISTER_TRIES="${CHECKS_GATE_REGISTER_TRIES:-20}"
QUEUE_WAIT="${CHECKS_GATE_QUEUE_WAIT:-1200}"
MAX_WAIT="${CHECKS_GATE_MAX_WAIT:-3600}"

die() { echo "ERROR $*"; exit 1; }
# verdict <line> — print it and exit with the code that names it.
verdict() {
  echo "$1"
  case "$1" in
    GREEN) exit 0 ;; DIRTY) exit 10 ;; BEHIND) exit 11 ;; PENDING) exit 12 ;;
    NO_CHECKS) exit 13 ;; "RED code"*) exit 20 ;; "RED infra"*) exit 21 ;;
  esac
  exit 1
}
nap() { sleep "$POLL"; }

merge_state() {
  gh pr view "$pr" --json mergeStateStatus --jq .mergeStateStatus 2>/dev/null
}

# statusCheckRollup mixes check runs (status/conclusion/detailsUrl) and commit
# statuses (state/targetUrl). Normalise each entry to "<STATE>\t<url>", where
# STATE is the settled outcome, RUNNING, or QUEUED (a check run nobody has
# started). A pending commit status cannot tell the two apart: RUNNING.
checks() {
  gh pr view "$pr" --json statusCheckRollup --jq '
    .statusCheckRollup // [] | .[] |
    (if .__typename == "StatusContext" or (.state != null and .status == null)
       then ((.state // "") | ascii_upcase
             | if . == "PENDING" or . == "EXPECTED" or . == "" then "RUNNING" else . end)
       else ((.status // "") | ascii_upcase) as $s
            | if $s == "COMPLETED" then ((.conclusion // "") | ascii_upcase)
              elif $s == "IN_PROGRESS" then "RUNNING"
              else "QUEUED" end
     end) + "\t" + (.detailsUrl // .targetUrl // "")' 2>/dev/null
}

states() { printf '%s\n' "$lines" | cut -f1; }

# 0. Is the branch mergeable at all? A conflicting PR never gets a check, so
#    waiting on one would only time out and read as infra-red.
state=""
for ((i = 0; i < STATE_TRIES; i++)); do
  state="$(merge_state)" || die "gh pr view $pr failed"
  [[ "$state" != "UNKNOWN" && -n "$state" ]] && break
  nap
done
[[ "$state" == "DIRTY" ]] && verdict "DIRTY"
if [[ "$state" == "BEHIND" ]]; then
  for ((i = 1; i < BEHIND_TRIES; i++)); do
    nap
    state="$(merge_state)" || die "gh pr view $pr failed"
    [[ "$state" == "BEHIND" ]] || break
  done
  [[ "$state" == "BEHIND" ]] && verdict "BEHIND"
  [[ "$state" == "DIRTY" ]] && verdict "DIRTY"
fi

# 1. Wait until CI has attached at least one check to the head. `gh pr update-
#    branch` moves the head, and CI takes a moment to register on the new one.
lines=""
for ((i = 0; i < REGISTER_TRIES; i++)); do
  lines="$(checks)" || die "gh pr view $pr failed"
  [[ -n "$lines" ]] && break
  nap
done
[[ -n "$lines" ]] || verdict "NO_CHECKS"

# 2. Wait for every check to settle. Checks left queued with none running are
#    a CI that cannot start, not a slow one.
waited=0
while states | grep -qxE 'RUNNING|QUEUED'; do
  if (( waited >= QUEUE_WAIT )) && ! states | grep -qx RUNNING; then
    verdict "RED infra reason=never-picked-up"
  fi
  (( waited >= MAX_WAIT )) && verdict "PENDING"
  nap; waited=$((waited + POLL))
  lines="$(checks)" || die "gh pr view $pr failed"
done

failing="$(printf '%s\n' "$lines" | awk -F'\t' '$1 != "SUCCESS" && $1 != "NEUTRAL" && $1 != "SKIPPED"')"
[[ -z "$failing" ]] && verdict "GREEN"

# 3. Classify every failing Actions run; an external failing status is
#    code-red with nothing to retry.
runs=() external=""
while IFS=$'\t' read -r _ url; do
  if [[ "$url" =~ /actions/runs/([0-9]+) ]]; then
    [[ " ${runs[*]} " == *" ${BASH_REMATCH[1]} "* ]] || runs+=("${BASH_REMATCH[1]}")
  elif [[ -z "$external" ]]; then
    external="${url:-unknown}"
  fi
done <<<"$failing"

code="" infra="" stale=0
for run in "${runs[@]}"; do
  # A run can report a failed job while others still run; classify the whole
  # run — and a rerun in flight is waited for, not judged by its old attempt.
  waited=0
  until [[ "$(gh run view "$run" --json status --jq .status 2>/dev/null)" == "completed" ]]; do
    (( waited >= MAX_WAIT )) && verdict "PENDING"
    nap; waited=$((waited + POLL))
  done
  v="$(gh run view "$run" --json conclusion,jobs --jq '
    [.jobs[] | select(.conclusion != "success" and .conclusion != "skipped")] as $failed |
    ($failed | map(select((.steps | length) > 0))) as $ran |
    if .conclusion == "success" then "stale"
    elif .conclusion == "startup_failure" then "infra reason=startup_failure"
    elif ($ran | length) > 0 then "code url=" + ($ran[0].url // "")
    elif ($failed | length) > 0 then "infra reason=no-steps-executed"
    else "code url=" end' 2>/dev/null)" || die "gh run view $run failed"
  case "$v" in
    stale) stale=$((stale + 1)) ;;
    infra*) [[ -n "$infra" ]] || infra="RED infra run=$run ${v#infra }" ;;
    *) [[ -n "$code" ]] || code="RED code run=$run ${v#code }" ;;
  esac
done

if [[ -n "$code" ]]; then verdict "$code"
elif [[ -n "$external" ]]; then verdict "RED code url=$external"
elif [[ -n "$infra" ]]; then verdict "$infra"
elif [[ -z "${CHECKS_GATE_REGATED:-}" ]]; then
  # Every failing run is green now (re-run since the rollup was read): the
  # rollup was stale. Gate once more from the top.
  CHECKS_GATE_REGATED=1 CHECKS_GATE_MAX_WAIT="$MAX_WAIT" exec bash "$0" "$pr"
else
  verdict "PENDING"
fi
