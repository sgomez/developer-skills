#!/usr/bin/env bash
# spec-plan.sh — the /developer workflow's planning read on GitHub, as one
# command that prints one JSON object.
#
# The workflow script has no shell of its own: every read is an agent's. This
# script keeps that agent trivial — run one command, hand back its JSON — so
# mode detection, the blocker check and the per-sub-issue resume probe (open
# PR, unresolved threads) cost one small agent instead of a conversation.
#
# Read-only. GitHub only (gh + jq); other trackers produce the same object by
# following docs/agents/issue-tracker.md.
#
# Usage:
#   spec-plan.sh <issue>                 # spec mode, or single mode when the
#                                        # issue has no sub-issues
#   spec-plan.sh <spec> <subissue>       # just that sub-issue
#
# Output (stdout, one line):
#   {"mode":"spec"|"single"|"sub","spec":N,"tickets":[
#     {"number":N,"title":"…","labels":["…"],"complex":bool,
#      "blockers":[open blocker numbers, native links and `Blocked by` body
#                  section together],
#      "prs":[{"number":N,"isDraft":bool,"unresolved":N}]}]}
#   Only OPEN sub-issues are listed. On failure: {"error":"…"} and exit 1.
set -uo pipefail

spec="${1:-}" sub="${2:-}"
[[ "$spec" =~ ^[0-9]+$ ]] || { echo "usage: spec-plan.sh <issue> [<subissue>]" >&2; exit 2; }
[[ -z "$sub" || "$sub" =~ ^[0-9]+$ ]] || { echo "usage: spec-plan.sh <issue> [<subissue>]" >&2; exit 2; }

die() { jq -cn --arg e "$*" '{error: $e}'; exit 1; }

repo="$(gh repo view --json owner,name --jq '.owner.login + "/" + .name' 2>/dev/null)" \
  || die "gh repo view failed"
owner="${repo%/*}" name="${repo#*/}"

# section <body> <heading-regex> — the lines under a `## <heading>` section.
section() {
  printf '%s\n' "$1" | awk -v h="$2" '
    $0 ~ "^##[#]* *" h { f = 1; next }
    /^#/ { f = 0 }
    f'
}

issue_state() { gh issue view "$1" --json state --jq .state 2>/dev/null; }

# ticket <N> — one sub-issue as a JSON object.
ticket() {
  local n="$1" info body complex native refs blockers b prs pr unresolved
  info="$(gh issue view "$n" --json title,labels,body 2>/dev/null)" || die "gh issue view $n failed"
  body="$(jq -r '.body // ""' <<<"$info")"

  complex=false
  section "$body" '[Cc]omplexity' | head -3 | grep -qiE '^[[:space:]]*[*_`]*complex' && complex=true

  # Native dependency links (open ones only); an endpoint the repo lacks reads as none.
  native="$(gh api "repos/$repo/issues/$n/dependencies/blocked_by" \
    --jq '[.[] | select(.state == "open") | .number] | .[]' 2>/dev/null || true)"
  # The body fallback: every #ref in the `Blocked by` section that is still open.
  refs="$(section "$body" '[Bb]locked by' | grep -oE '#[0-9]+' | tr -d '#' | sort -un)"
  blockers="$native"
  for b in $refs; do
    [[ "$(issue_state "$b")" == "OPEN" ]] && blockers+=$'\n'"$b"
  done

  prs="[]"
  for pr in $(gh pr list --state open --search "\"Closes #$n\" in:body" --json number --jq '.[].number' 2>/dev/null); do
    unresolved="$(gh api graphql -f query="
      { repository(owner:\"$owner\", name:\"$name\") { pullRequest(number: $pr) {
          isDraft reviewThreads(first: 100) { nodes { isResolved } } } } }" \
      --jq '.data.repository.pullRequest | {isDraft, unresolved: ([.reviewThreads.nodes[] | select(.isResolved == false)] | length)}' \
      2>/dev/null)" || die "reading review threads of PR $pr failed"
    prs="$(jq -c --argjson p "$pr" --argjson u "$unresolved" '. + [{number: $p} + $u]' <<<"$prs")"
  done

  jq -c --argjson n "$n" --argjson complex "$complex" --argjson prs "$prs" \
    --arg blockers "$blockers" '{
      number: $n, title: .title, labels: [.labels[].name], complex: $complex,
      blockers: ($blockers | split("\n") | map(select(. != "") | tonumber) | unique),
      prs: $prs }' <<<"$info"
}

if [[ -n "$sub" ]]; then
  [[ "$(issue_state "$sub")" == "OPEN" ]] || { jq -cn --argjson s "$spec" '{mode: "sub", spec: $s, tickets: []}'; exit 0; }
  t="$(ticket "$sub")" || { echo "$t"; exit 1; }
  jq -cn --argjson s "$spec" --argjson t "$t" '{mode: "sub", spec: $s, tickets: [$t]}'
  exit 0
fi

children="$(gh api graphql -f query="
  { repository(owner:\"$owner\", name:\"$name\") { issue(number: $spec) {
      state subIssues(first: 50) { pageInfo { hasNextPage } nodes { number state } } } } }" \
  --jq '.data.repository.issue' 2>/dev/null)" || die "listing the sub-issues of #$spec failed"
[[ "$(jq -r '.subIssues.pageInfo.hasNextPage' <<<"$children")" == "true" ]] \
  && die "more than 50 sub-issues: split the spec"

if [[ "$(jq '.subIssues.nodes | length' <<<"$children")" -eq 0 ]]; then
  # Single mode: the issue is its own spec.
  [[ "$(jq -r .state <<<"$children")" == "OPEN" ]] || { jq -cn --argjson s "$spec" '{mode: "single", spec: $s, tickets: []}'; exit 0; }
  t="$(ticket "$spec")" || { echo "$t"; exit 1; }
  jq -cn --argjson s "$spec" --argjson t "$t" '{mode: "single", spec: $s, tickets: [$t]}'
  exit 0
fi

tickets="[]"
for n in $(jq -r '.subIssues.nodes[] | select(.state == "OPEN") | .number' <<<"$children" | sort -n); do
  t="$(ticket "$n")" || { echo "$t"; exit 1; }
  tickets="$(jq -c --argjson t "$t" '. + [$t]' <<<"$tickets")"
done
jq -cn --argjson s "$spec" --argjson t "$tickets" '{mode: "spec", spec: $s, tickets: $t}'
