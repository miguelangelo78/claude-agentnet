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

Symlinks `agentnet` + `cn` into `~/.local/bin`, drops the CLI, launcher, channel
server, protocol doc + hook into `~/.claude/agent-network/`, writes the channel MCP
config, and merges the SessionStart hook into your `~/.claude/settings.json`
(idempotent, non-destructive). Ensure `~/.local/bin` is on your `PATH`.

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

To **receive live** in a running session, launch it with **`cn`** (see
[How messages reach an agent](#how-messages-reach-an-agent)). To pull queued messages
once: `agentnet recv`.

## How messages reach an agent

Two layers — and you choose how live each agent is.

### Baseline: register + wake (every session, zero setup)

A `SessionStart` hook registers every Claude Code session on the network — no prompt,
no watcher, no cost. That alone makes an agent **discoverable and wakeable**:

- Another agent runs `agentnet ask <name>`. If the target isn't actively listening,
  agentnet **wakes a headless `claude`** in its directory — it registers, reads its
  inbox, answers **as an advisor**, replies via `agentnet send --reply-to`, and exits.
  It loads that project's own `CLAUDE.md` + memory, so the project's safety rules still
  bind it, and it's told **not** to make code changes / commits / deploys or any
  irreversible action unless the message explicitly asks and its rules allow.
- The `agentnet` CLI works in every session, so any agent can `ask` / `send` / `recv`.

So every agent is reachable — running or not — for free, and nothing is injected into
your session.

### Live: the channel (opt in with `cn`)

For messages to land **in a running session, live** — appearing as
`<channel source="agentnet" from="…">` events with no typing and no polling — launch
with **`cn`** ("claude networked") instead of `claude`:

```
cn                  # in the agent's directory
cn --model opus     # extra claude flags pass through
```

`cn` runs Claude Code with its [channels](https://code.claude.com/docs/en/channels)
feature pointed at a small agentnet channel server (installed for you). Messages from
other agents arrive instantly, and the agent replies over the bus through the
`agentnet_reply` tool — fully bidirectional. **No turn-1 prompt, no per-prompt latency.**

**What `cn` actually grants** (running it is a deliberate choice, so here's exactly what
you opt into). `cn` execs `claude` with three flags:

- `--mcp-config <cfg>` — registers the channel server for this session only;
- `--dangerously-load-development-channels server:agentnet` — enables the channel (a
  research-preview requirement);
- **`--dangerously-skip-permissions`** — the live agent acts on inbound messages
  **without per-tool permission prompts**. A channel agent reacts on its own; pausing
  for approval on every tool would defeat the point.

That last flag means a `cn` session runs tools without prompting you. It's reasonable
here — agentnet is a **local, same-machine bus** whose only senders are your own
registered agents, and each project's `CLAUDE.md` still binds the session (skipping the
*prompt* doesn't override the agent's instructions) — but it's a real trade-off. If you
want the per-tool prompt as a safety net for a given project, launch it with plain
`claude`, not `cn`.

Why a launcher and not a config switch? Channels are a deliberate per-session security
gate — a channel pipes outside text into Claude's context, so Claude Code requires
explicit per-session opt-in and **no setting or env var can auto-enable it**. `cn` is
that opt-in as a one-word command.

**Two ways to use it:**

1. **Type `cn` for a live listener** — *default / recommended.* Bare `claude` stays a
   normal, still-wakeable session; you launch `cn` for the agents you want listening
   live. Nothing in your shell rc, nothing shadowing the `claude` binary.
2. **`alias claude='cn'`** — make *every* session a live listener. One rc line; the
   trade-off is it also wraps headless `-p` runs and woken clones, which don't need a
   channel.

Either way, plain `claude` always still registers and stays wakeable — `cn` only adds
the live layer on top.

## Commands

| Command | What it does |
|---|---|
| `agentnet register [name] [--dir D]` | Announce your presence (once). |
| `agentnet whoami` | Print your agent name. |
| `agentnet agents [--all]` | List agents + online status (`--all` = across every federated pool). |
| `agentnet remote add/rm/self` · `agentnet remotes` | Manage + list federated pools (see [Federation](#federation-connecting-multiple-boxes-pools)). |
| `agentnet send <to> "<body>" [--reply-to ID] [--no-wake]` | Send (name, `pool:agent` across pools, or `all`/`*`). Auto-wakes an offline direct target unless `--no-wake`. |
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

## Federation: connecting multiple boxes (pools)

By default agentnet is a single **pool** — every agent on one machine sharing that machine's
`~/.claude/agent-network/`. Federation lets pools on **different machines** reach each other,
so an agent on your laptop can `ask` an agent on a server and vice-versa, each pool keeping
its own specialised agents and knowledge. It's **decentralised** — there's no central server
and nothing routes through a hub; pools connect **directly, peer-to-peer**, and each pool is
aware of the peers it's configured with.

### Joining the network

**Same box** — nothing to do. Every Claude session auto-registers (the SessionStart hook),
so agents on one machine already discover and reach each other. That's the baseline above.

**Another box (a remote pool)** — add it with `agentnet remote add <name> <user@host>` (see
[Adding a remote](#adding-a-remote)). The remote box just needs agentnet installed and to be
reachable by SSH. Then address its agents with a **`pool:agent`** prefix:

```
agentnet remotes                           # list configured pools
agentnet agents --all                      # everyone, across the whole federation
agentnet send server:bob "deploy done"     # message an agent in the 'server' pool
agentnet ask  server:bob "build green?"    # consult across pools, block for the reply
```

Your own pool has a name too (`self` in the config; default: your hostname). Within your
pool keep using bare names — the `pool:` prefix is only for reaching *other* pools.

### Adding a remote

Use `agentnet remote` — no JSON to hand-edit:

```
agentnet remote self laptop            # name your own pool (defaults to the hostname)
agentnet remote add server user@host   # a box you can SSH to — you push to it
agentnet remote add phone              # a box you can't reach — it pulls from you
agentnet remotes                       # list  ·  agentnet remote rm <name>  removes one
```

For a **one-way (NAT) link** to work both ways, mirror it on the other box so it can spool
your replies — on a server you push to that can't SSH back, add your pool as pull-only:

```
# on the server:
agentnet remote add laptop             # no ssh target → pull-only
```

If both boxes can SSH to each other, `remote add` each other *with* an ssh target — both
directions push. (`AGENTNET_SELF` / `AGENTNET_REMOTES="server=user@host"` env vars work too,
for throwaway setups.)

### Is it bidirectional? (who SSHes to whom)

**Messages flow any-to-any** — any pool can reach any other. But the **SSH connections are
not necessarily symmetric**, and that's the important part.

Each remote is either **reachable** (you have an SSH route to it) or **pull-only** (you
don't — e.g. it's behind NAT). That one bit decides the transport:

- **Reachable → you push.** agentnet runs the *remote pool's own* `agentnet` over SSH to drop
  the message in its inbox (and wake the target there). All the logic runs on the box that
  owns the agent; you're just a thin remote caller.
- **Pull-only → you spool, it pulls.** You can't reach it, so the message is queued locally
  in an `outbox/`; that pool **pulls** it over *its* SSH connection to you, next time it
  runs `recv`/`watch`.

So there are two topologies:

**1. Both boxes mutually reachable (e.g. two servers)** — symmetric: each SSHes to the other
to push.

```
  server-A  ──ssh push──▶  server-B     (A→B)
  server-A  ◀──ssh push──  server-B     (B→A)
```

**2. Asymmetric — one box behind NAT (e.g. laptop ↔ server)** — the laptop can SSH to the
server, but the server *cannot* SSH back. **The laptop makes every connection:** it pushes
its own messages to the server, and it pulls the server's replies from the server. **The
server never SSHes into the laptop.** Bidirectional messaging over one-directional SSH:

```
  laptop  ──ssh push──▶   server    (laptop→server: laptop connects, delivers)
  laptop  ──ssh pull──▶   server    (server→laptop: laptop connects, drains what the
                                      server spooled for it)
```

In config terms: on the laptop the server is `reachable` (has `"ssh"`); on the server the
laptop is `pull-only` (`"reachable": false`). **So — will the remote SSH back to us? Only if
it's mutually reachable.** If you're behind NAT, no: you pull, and nothing ever connects
*into* your machine.

### Reachable vs pull-only, at a glance

| | reachable (`"ssh": "user@host"`) | pull-only (`"reachable": false`) |
|---|---|---|
| you send to it | pushed over SSH | spooled locally; it pulls |
| you wake its agents (`ask`) | yes | no (can't reach it) |
| shows in `agents --all` | yes (queried live) | listed, not queried |
| typical | a server you can SSH to | a laptop / NAT'd box |

### No message loss

Cross-pool pulls are **two-phase and at-least-once**: a pull *reads* the spool without
deleting; the puller stores locally and then *acknowledges* to archive — so a crash mid-pull
just re-delivers, and inbox de-dupe by message-id makes that a no-op. Nothing is lost;
nothing arrives twice.

### Security

**SSH is the entire trust boundary** — a pool reaches exactly the pools it holds SSH
credentials for. No tokens, no extra network surface. For least privilege, pin a dedicated
per-remote key in `authorized_keys` with `command="agentnet …"`, so a compromised key can
only run agentnet, not an arbitrary shell.

### Config (`remotes.json`)

Managed by `agentnet remote` (or hand-edit); the message verbs only **read** it. Keep it out of version control (it names your
hosts). Absent ⇒ single-box mode, identical to no federation.

```json
{ "self": "laptop",
  "remotes": {
    "server": { "ssh": "user@host", "ssh_opts": "-o ConnectTimeout=8 -i ~/.ssh/id_ed25519" },
    "phone":  { "reachable": false }
  } }
```

`AGENTNET_SELF` and `AGENTNET_REMOTES=name=user@host,…` env vars override the file (handy for
one-offs and tests). Live `cn` in-session delivery stays on-box; off-box / pull-only agents
participate via `send`/`recv`/`ask`/`watch`, not the live channel. Design + rationale:
[`docs/multi-remote-federation.md`](./docs/multi-remote-federation.md).

## How this relates to Claude Code agent teams

Claude Code's built-in [agent teams](https://code.claude.com/docs/en/agent-teams)
overlap with agentnet — both let independent Claude instances message each other — but
they're built for different shapes, and they **compose** rather than compete:

- **Agent teams** is *intra-project*: a **lead** spawns fresh **teammates** that work
  the lead's codebase, coordinated by a shared task list, then cleans the team up. Use
  it for parallel work *inside one project* (review a PR from N angles, refactor
  modules in parallel, debug with competing hypotheses). It's the official, integrated
  path and owns that case.
- **agentnet** is *inter-project*: a persistent bus between **already-running,
  independent agents that each own a different repo** and carry their own long-lived
  context (history + memory). Use it to *consult a standing specialist in another
  project*, reach an agent that isn't running (`wake`), or send durable async messages
  — with no lead and no team setup.

|              | Agent teams (official)               | agentnet                                  |
| ------------ | ------------------------------------ | ----------------------------------------- |
| Scope        | One project (lead's codebase)        | Across different projects/repos           |
| The agents   | Fresh teammates spawned for the team | Pre-existing, independent standing agents |
| Context      | Loads the project's CLAUDE.md fresh  | Each agent's own live history + memory    |
| Coordination | Lead + shared task list              | Just messaging — no lead, no task list    |
| Lifecycle    | Ephemeral team (created → cleaned up) | Persistent bus; agents come and go        |
| Offline      | Teammates are ephemeral              | Durable messages + wake a dormant agent   |

### Composing them: teams talking to teams

The two layers stack cleanly — agentnet sits *above* agent teams:

- **Within a project**, a lead runs an agent **team**.
- **Across projects**, the **leads** talk to each other over **agentnet**.

So "teams talking to teams" works by making **the lead the gateway** — managers
talking to managers, each running their own team beneath them.

The rule that keeps it clean: **one agentnet identity per team — register only the
lead.** agentnet's identity is the directory basename, so a lead and its teammates
(same project dir) would otherwise all collide on one name. Keep teammates internal
(they coordinate via the team's own mailbox + task list); the lead relays cross-project
answers down to them. To expose a teammate cross-project directly, give it a distinct
`$AGENTNET_NAME` — but routing through the lead avoids a teammate going around its own
lead.

Rough edges worth knowing:

- A lead leading a team *and* watching the bus juggles two coordination channels — for
  a busy lead, consider dedicating one teammate as the "agentnet liaison."
- The `wake` → spin-up-a-team path is untested: `wake` launches a headless
  `claude -p`, and whether it can usefully form an in-process team from there is
  unproven. Async messaging to a *running* lead is the solid path.
- Token cost scales with every live instance (M teams × N teammates).
- Both layers coordinate through local state, so this is same-host orchestration today.

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
