#!/usr/bin/env bash
#
# hc-agent-view.sh <label> <agent transcript> <workflow journal> <agent id> —
# runs in the terminal that hc-agent-terminals.sh opens for a worker: prints
# the worker's messages and tool calls as its transcript grows, reports each
# step to herdr-core as `working`, and the journal's result as `done` or `error`.
#
# A finished terminal loses its status, so the final one lingers
# HC_AGENT_LINGER seconds. A line on stdin (`hc send <t> stop`, from
# SubagentStop) means the worker ended: no result within 5 s is an error.

label=$1 file=$2 journal=$3 id=$4
stty -echo 2>/dev/null
status() { printf '\033]7501;state=%s:app=claude-workflow:msg=%s\033\134' "$1" "$(printf %s "$2" | base64 -w0)"; }
status working "$label"
printf '\033]2;%s\007' "$label"
echo "── $label ──"
for _ in $(seq 50); do [[ -f $file ]] && break; sleep 0.2; done
tail -n +1 -F "$file" 2>/dev/null | jq --unbuffered -j '
  def osc($m): "\u001b]7501;state=working:app=claude-workflow:msg=\($m | @base64)\u001b\\";
  select(.type == "assistant") | .message.content[]? |
  if .type == "text" then "· " + .text + "\n"
  elif .type == "tool_use" then
    (.name + " " + ((.input.command // .input.description // .input.file_path // .input.pattern // "") | tostring) | .[0:200]) as $s
    | "→ \($s)\n" + osc($s | gsub("\\s+"; " ") | .[0:80])
  else empty end' &

deadline=
until result="$(jq -c --arg id "$id" 'select(.type == "result" and .agentId == $id) | .result' "$journal" 2>/dev/null | head -1)"; [[ -n $result ]]; do
  [[ -n $deadline ]] && ((SECONDS >= deadline)) && break
  if read -r -t 1 _; then deadline=$((SECONDS + 5)); elif (($? < 128)); then sleep 1; fi
done
sleep 0.5
pkill -P $$ 2>/dev/null

IFS=$'\t' read -r state msg < <(jq -r '
  if . == null then ["error", "stopped without a result"]
  elif type != "object" then ["done", tostring]
  else ([.status, .verdict, .outcome] | map(select(. != null))[0] // "done") as $v
    | if ($v | ascii_downcase) | IN("blocked", "escalate") then ["error", .reason // $v]
      elif .pr then ["done", "PR #\(.pr)"]
      elif $v == "pr" then ["done", .url // "pushed"]
      elif (.fixes // 0) > 0 then ["done", "\($v) (\(.fixes) fixes)"]
      else ["done", $v] end
  end | .[1] |= (tostring | gsub("\\s+"; " ") | .[0:80]) | @tsv' <<<"${result:-null}")
status "$state" "$msg"
[[ $state == done ]] && echo "✓ $msg" || echo "✗ $msg"
sleep "${HC_AGENT_LINGER:-60}"
