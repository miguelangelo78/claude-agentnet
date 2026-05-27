#!/usr/bin/env bash
# Claude agent-network — SessionStart hook.
# On every session start: register this session as a network agent (so it's
# discoverable + wakeable), surface any pending messages, and tell the agent how
# to go live. Best-effort — must NEVER block or fail a session start.
set -u

AGENTNET="$(command -v agentnet 2>/dev/null || true)"
[ -n "$AGENTNET" ] || AGENTNET="$HOME/.local/bin/agentnet"
[ -x "$AGENTNET" ] || AGENTNET="$HOME/.claude/agent-network/agentnet"
[ -x "$AGENTNET" ] || exit 0   # network not installed here — no-op

name="$("$AGENTNET" whoami 2>/dev/null)" || exit 0
[ -z "$name" ] && exit 0
"$AGENTNET" register >/dev/null 2>&1 || true   # announce presence (discoverable/wakeable)

# Count pending messages WITHOUT consuming them (so the agent can recv them itself).
count="$("$AGENTNET" recv --peek --json 2>/dev/null | python3 -c 'import sys,json
try: print(len(json.load(sys.stdin)))
except Exception: print(0)' 2>/dev/null)"
[ -z "$count" ] && count=0

if [ "$count" -gt 0 ]; then
  pend="You have ${count} pending message(s) waiting — run \`agentnet recv\` NOW to read them, then reply with \`agentnet send <from> \"...\" --reply-to <id>\`. "
  live="And start the Monitor tool on \`agentnet watch\` so further messages arrive live."
else
  pend="No messages waiting. "
  live="To be reachable LIVE this session, start the Monitor tool on \`agentnet watch\` (each inbound message becomes a live notification while you work)."
fi

ctx="[agent-network] You are agent '${name}' on the live Claude agent network (the \`agentnet\` CLI — full protocol at ~/.claude/agent-network/README.md). Other Claude agents can reach you directly, with no human relaying files. ${pend}${live} To consult another agent yourself: \`agentnet ask <name> \"<question>\"\` (it auto-wakes a dormant agent and blocks for the reply)."

# SessionStart hooks inject context via hookSpecificOutput.additionalContext.
python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":sys.argv[1]}}))' "$ctx"
exit 0
