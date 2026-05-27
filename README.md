# claude-agentnet

A tiny **live message bus for Claude Code agents** — so agents working in different
projects (or different terminals) can talk **directly to each other**: send 1:1 or
broadcast, **consult one and block for its reply**, and even **wake a dormant agent**
to answer — all with **no human relaying files**.

Pure Python **stdlib**. No server, no daemon, no dependencies — just a shared
directory under `~/.claude/agent-network/` and the `claude` you already have.

```
agentnet ask backend-api "Does the worker pool share the DB connection, or open its own?"
# → wakes backend-api if it's offline, blocks until it answers, prints the reply.
```

## Why

If you run more than one Claude Code agent, you've probably *been* the message bus:
copying a question from one terminal into another, pasting the answer back. agentnet
removes you from that loop. Agents discover each other, message each other, and one
agent can **wake another headlessly** to get an answer — while everyone keeps working.

## Install

Pick whichever is easiest — all three end up at the same place.

### A. Claude Code plugin (one command)

```
claude plugin install agentnet@github:miguelangelo78/claude-agentnet
```

Installs the `agentnet` CLI (on PATH while the plugin is enabled), the **SessionStart
hook** (auto-registers every session), and the **`agentnet` skill** (so Claude knows
how to use it). Requires Claude Code with plugin support (v2.1.130+).

### B. Universal installer (works anywhere)

```
git clone https://github.com/miguelangelo78/claude-agentnet
bash claude-agentnet/install.sh
```

or piped:

```
curl -fsSL https://raw.githubusercontent.com/miguelangelo78/claude-agentnet/main/install.sh | bash
```

Symlinks `agentnet` + `cn` into `~/.local/bin`, drops the protocol doc + hook into
`~/.claude/agent-network/`, and merges the SessionStart hook into your
`~/.claude/settings.json` (idempotent, non-destructive). Ensure `~/.local/bin` is on
your `PATH`.

### C. Just ask Claude

With the skill installed (via A, or by dropping `skills/agentnet/` into your skills),
tell Claude *"set up agentnet"* or *"message the backend agent"* — the skill guides it
through install + usage.

> Requires `python3` (used by the CLI and the hook), and `git` for the piped install.

## Quickstart

```
agentnet register                  # announce yourself (also automatic via the hook)
agentnet agents                    # who's on the network + who's online
agentnet ask web-app "is the build green?"      # consult + wait for a reply
agentnet send web-app "fyi: deploying in 5"     # fire-and-forget
agentnet send all "heads up: migrating the DB"  # broadcast
```

To **receive live** while you work, run the **Monitor tool** on `agentnet watch` (each
inbound message becomes a notification). To pull queued messages once: `agentnet recv`.

## Active vs. headless agents

Both keep working exactly as designed:

- **Active agent (live receive).** Run the Monitor tool on `agentnet watch` — every
  message another agent sends you arrives as a live notification, no polling. To come
  up *already listening* on boot, launch with **`cn`** ("claude networked") instead of
  bare `claude` (or `alias claude='cn'`). `cn` hands the session a turn-1
  "register + watch + recv" prompt, then drops you into a normal, now-live session.

- **Headless agent (woken on demand).** `agentnet wake <name>` — or `agentnet ask`
  against an offline target — spawns a **headless `claude -p`** in that agent's
  directory. It registers, reads its inbox, answers **as an advisor**, replies via
  `agentnet send --reply-to`, then exits. It loads that project's own `CLAUDE.md` +
  memory, so the project's safety rules still bind it, and it's told **not** to make
  code changes / commits / deploys or any irreversible action unless the message
  explicitly asks and its rules allow — when unsure it replies asking first.

A `SessionStart` hook auto-**registers** every session so it's discoverable and
wakeable. (A hook can't make an *idle* interactive session start watching — that's why
`cn` exists — but it makes every session reachable on demand.)

## Commands

| Command | What it does |
|---|---|
| `agentnet register [name] [--dir D]` | Announce your presence (once). |
| `agentnet whoami` | Print your agent name. |
| `agentnet agents` | List agents + online status. |
| `agentnet send <to> "<body>" [--reply-to ID] [--no-wake]` | Send (name, or `all`/`*`). Auto-wakes an offline direct target unless `--no-wake`. |
| `agentnet recv [--json] [--peek]` | Pull your messages (`--peek` = don't consume). |
| `agentnet watch [--interval S]` | Stream inbound messages (run under the Monitor tool). |
| `agentnet ask <to> "<q>" [--timeout S] [--wake]` | Ask + block for a reply; wakes the target if offline. |
| `agentnet wake <name\|--dir D> ["msg"] [--listen]` | Spawn a headless `claude` in that dir to handle its inbox. |

Identity defaults to a slug of your working directory's basename; override with
`agentnet register <name>` or `$AGENTNET_NAME`. Full protocol:
[`PROTOCOL.md`](./PROTOCOL.md) (also installed to `~/.claude/agent-network/README.md`
for woken agents to read).

## How it works

- **Transport** is a shared directory (`~/.claude/agent-network/`): a per-agent inbox
  queue, an `agents.json` registry, and an append-only `log.jsonl` audit. File locks
  keep concurrent writes safe. No process needs to be running for a message to be
  delivered — it's durable; the recipient gets it next time it watches or `recv`s.
- **Online** = an agent that refreshed its heartbeat within 90s (i.e. is actively
  watching). `send` to an offline agent auto-wakes it (debounced) so the message
  isn't just left unread.
- **`$AGENTNET_WAKE_MODEL`** (optional) sets the model for woken agents, e.g.
  `export AGENTNET_WAKE_MODEL=sonnet` for cheaper/faster wakes.

## Tests

```
bash tests/test_agentnet.sh
```

Runs the real CLI in an isolated `$HOME` (never touches your `~/.claude`) with a stub
`claude` on `PATH`, covering register / send / recv / broadcast / peek / durable
queue / self-send guard, plus the headless `wake` path and the active `watch` path.

## Uninstall

```
bash uninstall.sh            # remove CLI + hook, keep your message history
bash uninstall.sh --purge    # remove everything, including history + registry
```

## License

[MIT](./LICENSE).
