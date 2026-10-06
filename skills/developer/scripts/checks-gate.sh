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
# picks the verdict up from the completion notification.
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
#   checks-gate.sh <PR>
#
# Verdicts (one line on stdout, exit 0):
#   DIRTY                      conflicts with the base; GitHub runs no checks on
#                              it. The conflict path, never a red.
#   BEHIND                     mergeable but stale, and still so after a short
#                              settle (GitHub can report the old state for a
#                              moment after an update-branch): update the
#                              branch, then gate again.
#   NO_CHECKS                  nothing registered on the head after the wait,
#                              on a repo that has CI: infra-red.
#   GREEN                      every check settled as success/neutral/skipped.
#   PENDING                    checks still running when the wait ran out.
#   RED code run=<id> url=<job-url>
#                              a failed job executed steps: the change was
#                              exercised and failed.
#   RED code url=<link>        a failing check that is not a GitHub Actions run
#                              (an external status): unclassifiable, and
#                              there is no run to retry.
#   RED infra run=<id> reason=<why>
#                              nothing failed after executing (every failed job
#                              at zero steps, or startup_failure): the code was
#                              never exercised.
#   RED infra reason=never-picked-up
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

pr="${1:-}"
[[ "$pr" =~ ^[0-9]+$ ]] || { echo "usage: checks-gate.sh <PR>" >&2; exit 2; }

POLL="${CHECKS_GATE_POLL:-15}"
STATE_TRIES="${CHECKS_GATE_STATE_TRIES:-8}"
BEHIND_TRIES="${CHECKS_GATE_BEHIND_TRIES:-3}"
REGISTER_TRIES="${CHECKS_GATE_REGISTER_TRIES:-20}"
QUEUE_WAIT="${CHECKS_GATE_QUEUE_WAIT:-1200}"
MAX_WAIT="${CHECKS_GATE_MAX_WAIT:-3600}"

die() { echo "ERROR $*"; exit 1; }
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
[[ "$state" == "DIRTY" ]] && { echo "DIRTY"; exit 0; }
if [[ "$state" == "BEHIND" ]]; then
  for ((i = 1; i < BEHIND_TRIES; i++)); do
    nap
    state="$(merge_state)" || die "gh pr view $pr failed"
    [[ "$state" == "BEHIND" ]] || break
  done
  [[ "$state" == "BEHIND" ]] && { echo "BEHIND"; exit 0; }
  [[ "$state" == "DIRTY" ]] && { echo "DIRTY"; exit 0; }
fi

# 1. Wait until CI has attached at least one check to the head. `gh pr update-
#    branch` moves the head, and CI takes a moment to register on the new one.
lines=""
for ((i = 0; i < REGISTER_TRIES; i++)); do
  lines="$(checks)" || die "gh pr view $pr failed"
  [[ -n "$lines" ]] && break
  nap
done
[[ -n "$lines" ]] || { echo "NO_CHECKS"; exit 0; }

# 2. Wait for every check to settle. Checks left queued with none running are
#    a CI that cannot start, not a slow one.
waited=0
while states | grep -qxE 'RUNNING|QUEUED'; do
  if (( waited >= QUEUE_WAIT )) && ! states | grep -qx RUNNING; then
    echo "RED infra reason=never-picked-up"; exit 0
  fi
  (( waited >= MAX_WAIT )) && { echo "PENDING"; exit 0; }
  nap; waited=$((waited + POLL))
  lines="$(checks)" || die "gh pr view $pr failed"
done

failing="$(printf '%s\n' "$lines" | awk -F'\t' '$1 != "SUCCESS" && $1 != "NEUTRAL" && $1 != "SKIPPED"')"
[[ -z "$failing" ]] && { echo "GREEN"; exit 0; }

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
    (( waited >= MAX_WAIT )) && { echo "PENDING"; exit 0; }
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

if [[ -n "$code" ]]; then echo "$code"
elif [[ -n "$external" ]]; then echo "RED code url=$external"
elif [[ -n "$infra" ]]; then echo "$infra"
elif [[ -z "${CHECKS_GATE_REGATED:-}" ]]; then
  # Every failing run is green now (re-run since the rollup was read): the
  # rollup was stale. Gate once more from the top.
  CHECKS_GATE_REGATED=1 exec bash "$0" "$pr"
else
  echo "PENDING"
fi
