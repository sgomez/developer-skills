#!/usr/bin/env bash
#
# hc-agent-view.sh <label> <agent transcript> — runs in the terminal that
# hc-agent-terminals.sh opens for a worker: reports `working` to herdr-core and
# prints the worker's messages and tool calls as its transcript grows.

label=$1 file=$2
printf '\033]7501;state=working:app=claude-workflow:msg=%s\033\134' "$(printf %s "$label" | base64 -w0)" >/dev/tty
printf '\033]2;%s\007' "$label" >/dev/tty
echo "── $label ──"
for _ in $(seq 50); do [[ -f $file ]] && break; sleep 0.2; done
tail -n +1 -F "$file" 2>/dev/null | jq --unbuffered -r '
  select(.type == "assistant") | .message.content[]? |
  if .type == "text" then "· " + .text
  elif .type == "tool_use" then "→ " + .name + " " + ((.input.command // .input.description // .input.file_path // .input.pattern // "") | tostring | .[0:200])
  else empty end'
