#!/usr/bin/env bash
# Claude agent-network — SessionStart hook.
# On every session start: register this session as a network agent (so it's
# discoverable + WAKEABLE) and surface any messages already waiting. Best-effort —
# must NEVER block or fail a session start.
#
# It deliberately does NOT start a watcher and does NOT nudge the agent to: an agent
# stays reachable via `agentnet ask`/`wake` (which auto-wakes it) without watching, so
# the default is zero-cost and never hijacks a turn. Watching is opt-in (launch `cn`).
set -u

AGENTNET="$(command -v agentnet 2>/dev/null || true)"
[ -n "$AGENTNET" ] || AGENTNET="$HOME/.local/bin/agentnet"
[ -x "$AGENTNET" ] || AGENTNET="$HOME/.claude/agent-network/agentnet"
[ -x "$AGENTNET" ] || exit 0   # network not installed here — no-op

name="$("$AGENTNET" whoami 2>/dev/null)" || exit 0
[ -z "$name" ] && exit 0
"$AGENTNET" register >/dev/null 2>&1 || true   # announce presence (discoverable + wakeable)

# Count pending messages WITHOUT consuming them (so the agent can recv them itself).
count="$("$AGENTNET" recv --peek --json 2>/dev/null | python3 -c 'import sys,json
try: print(len(json.load(sys.stdin)))
except Exception: print(0)' 2>/dev/null)"
[ -z "$count" ] && count=0

if [ "$count" -gt 0 ]; then
  pend="You have ${count} message(s) waiting — run \`agentnet recv\` to read them, then reply with \`agentnet send <from> \"...\" --reply-to <id>\`. "
else
  pend="No messages waiting. "
fi

ctx="[agent-network] You are agent '${name}' on the Claude agent network — registered, so other agents can reach you any time with \`agentnet ask\`/\`agentnet wake\` even while you're not watching (a consult auto-wakes you). ${pend}To consult another agent yourself: \`agentnet ask <name> \"<question>\"\`. Protocol: ~/.claude/agent-network/README.md. (Optional, only if you want to monitor the bus live: run the Monitor tool on \`agentnet watch\` — not needed for others to reach you.)"

python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":sys.argv[1]}}))' "$ctx"
exit 0
