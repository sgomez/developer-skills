#!/usr/bin/env bash
#
# SubagentStart / SubagentStop hook: in herdr-core, each /developer worker
# (build, fix, merge-fix, review) gets a child terminal of the Claude terminal,
# named after the workflow label (build-387), that follows the worker's
# transcript (hc-agent-view.sh). It is killed when the worker stops.
#
# The herdr app lists terminals, not OSC 7501 sub-records, so a terminal per
# worker is what makes the workers visible there. Short mechanical agents
# (cleanup, gate…) get none: their agent_type is not a worker's. A no-op
# outside herdr-core, outside a workflow, and without jq or hc.
#
# The payload has no label: it comes from the workflow journal, which holds the
# agent's `started` line when SubagentStart fires. --no-notify keeps the core
# from typing notes about the child into Claude's prompt.

[[ -n ${HC_TERMINAL_ID:-} ]] || exit 0
command -v jq >/dev/null 2>&1 && command -v hc >/dev/null 2>&1 || exit 0

IFS=$'\t' read -r type id event transcript < <(jq -r '[.agent_type // "", .agent_id // "", .hook_event_name // "", .transcript_path // ""] | @tsv' 2>/dev/null) || exit 0
[[ $id =~ ^[A-Za-z0-9_-]+$ ]] || exit 0
case "${type##*:}" in
  code-author | diff-reviewer) ;;
  *) exit 0 ;;
esac
journal="$(grep -l "\"agentId\":\"$id\"" "${transcript%.jsonl}"/subagents/workflows/*/journal.jsonl 2>/dev/null | head -1)"
[[ -n $journal ]] || exit 0

if [[ $event == SubagentStop ]]; then
  hc ls --json 2>/dev/null | jq -r --arg id "$id" '.terminals[] | select(.labels["claude.agent"] == $id) | .address' |
    while read -r t; do hc kill "$t" >/dev/null 2>&1; done
  exit 0
fi
[[ $event == SubagentStart ]] || exit 0

label="$(grep "\"agentId\":\"$id\"" "$journal" | jq -r 'select(.type == "started") | .label // empty' 2>/dev/null | head -1)"
label=${label:-agent}

# hc names: 1-32 of a-z 0-9 - _ ., not shaped like an id (t7), unique among live terminals.
name="$(printf %s "$label" | tr 'A-Z' 'a-z' | tr -cs 'a-z0-9._' '-' | sed 's/^[-._]*//; s/-*$//' | cut -c1-25)"
[[ -n $name && ! $name =~ ^t[0-9] ]] || name="agent-$name"
name=${name%-}
for n in "$name" "$name-${id:0:6}"; do
  hc run --bg --no-notify --rm --name "$n" --label "claude.agent=$id" \
    "$(dirname "$0")/hc-agent-view.sh" "$label" "$(dirname "$journal")/agent-$id.jsonl" >/dev/null 2>&1 && break
done
exit 0
