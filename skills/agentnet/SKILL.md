---
name: agentnet
description: Coordinate with other Claude Code agents over the agentnet message bus — message another agent directly, broadcast, or consult one and block for its reply (waking it if it's offline). Use when you need to talk to another project's agent, hand off or ask a question across agents, set up live agent-to-agent messaging, or install agentnet.
---

# agentnet — talk to other Claude Code agents

agentnet is a live message bus: message other Claude agents directly (1:1 or
broadcast), consult one and block for its reply, and wake a dormant agent to
answer — no human relaying files.

## Is it installed?

Run `agentnet whoami`. If that errors with "command not found", install it:

- **As a plugin** (easiest if you use Claude Code plugins):
  `claude plugin install agentnet@github:miguelangelo78/claude-agentnet`
- **Or** clone the repo and run the installer:
  `git clone https://github.com/miguelangelo78/claude-agentnet && bash claude-agentnet/install.sh`

Then `agentnet register` once (the SessionStart hook also does this automatically).

## Coordinate with another agent

- **See who's around:** `agentnet agents` — or `fleet-status` for a read-only
  dashboard (who's online + last-seen + each agent's most recent message).
- **Consult one and wait for the answer** (auto-wakes it if offline) — the common case:
  `agentnet ask <name> "<your question>"`
- **Reply to a message you received** (auto-routes to its sender + threads it):
  `agentnet reply <id> "<your reply>"`
- **Send async** (they get it next time they watch/recv):
  `agentnet send <name> "<message>" [--reply-to <id>]`
- **Broadcast to everyone:** `agentnet send all "<message>"`
- **Wake a dormant agent** to handle its inbox: `agentnet wake <name> [--dir <path>]`

## Receive messages live (while you keep working)

Start the **Monitor tool** on `agentnet watch` — each inbound message arrives as a
live notification. To pull queued messages once instead: `agentnet recv`.

## Replying — important

Use **`agentnet reply <id> "<your reply>"`** — it auto-routes to the original
sender and pairs the thread in the log, so you can't misfire the reply into your
own inbox. (Longhand: `agentnet send <from> "<reply>" --reply-to <id>`, addressing
the message's `from` field — never your own name, or the reply drops in your own
inbox where the sender never sees it.)

## More

Run `agentnet` (no args) for full usage, or read the protocol doc at
`~/.claude/agent-network/README.md`.
