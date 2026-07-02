# Design notes: multi-remote federation

How agentnet lets **pools on different machines reach each other** — peer-to-peer, with no
central node — while staying byte-for-byte identical to single-box behaviour when unused.

## Model

- A **pool** is one machine's agentnet (its `~/.claude/agent-network/`). Federation links
  pools; it does **not** introduce a server every pool routes through. Each pool keeps its
  own bus, and cross-pool links are **direct, pool-to-pool**. The network is
  **decentralised**: every pool is an equal peer.
- **Qualified names.** Within a pool, agents are addressed **bare** (`alice`). Across pools,
  **`pool:agent`** (`server:alice`). `slug()` runs per-part so the single `:` survives.
- A cross-pool message stamps `from` as **`<self>:<me>`** so the recipient can reply straight
  back to the right pool.

### Reachability is a per-link property (not a hierarchy)

The only asymmetry is transport-level and **per directed link**: *can pool A open a
connection to pool B?*

- **Reachable** (A has an SSH route to B) → A **pushes**: it runs B's own `agentnet` over
  SSH to drop the message in B's inbox (and wake the target there). All logic runs on the
  box that owns the agent.
- **Not reachable** (e.g. B is behind NAT and only makes *outbound* connections) → A
  **spools** the message in its local `outbox/<B>/`; B **pulls** it — over B's own SSH
  connection to A — on its next `recv`/`watch`.

Neither case routes through a third party: a message from A to B lives only on A and B. When
two pools are mutually reachable you get a full mesh (each pushes to the other). A pool that
only makes outbound connections still reaches its peers directly, by pulling from them.
(The one case needing more is *two* pools that can neither push nor pull to each other —
both purely inbound-unreachable; a relay for that is deferred, see Phasing.)

Wake falls out for free: you can only wake a pool you can reach, so an unreachable pool is
never woken — its agents see spooled messages when they next pull.

## Transport: SSH pass-through

Reaching a peer = running **its own `agentnet`** over SSH, so 100% of the existing logic
runs on the box that owns the agent; the caller is a thin router. Each remote invocation
carries `AGENTNET_NAME=<self>:<me>` so `from` is stamped correctly on the far side:

```
ssh <peer> 'AGENTNET_NAME=<self>:<me> agentnet <verb> <args…>'
```

## Config

`~/.claude/agent-network/remotes.json` — **human-authored**; the CLI only ever **reads** it
(keep it out of version control; it names your hosts). Absent ⇒ single-box mode.

```json
{ "self": "laptop",
  "remotes": {
    "server": { "ssh": "user@host" },     // reachable: push over ssh
    "phone":  { "reachable": false }       // inbound-unreachable: spool; it pulls
  } }
```

`AGENTNET_SELF` / `AGENTNET_REMOTES="name=user@host,…"` env vars override the file.
Presence of `ssh` ⇒ reachable; its absence (or `"reachable": false`) ⇒ the peer pulls.

## Routing per verb

- **send** — local (bare / `self:x`) unchanged; reachable `pool:agent` → ssh-push (far-side
  auto-wake applies); unreachable `pool:agent` → spool to `outbox/<pool>/`.
- **recv / watch** — first drain each reachable peer's outbox *for this pool* (deposit each
  message into its target agent's local inbox, deduped by id), then read local as usual.
- **agents `--all`** — local agents (prefixed `self:`) plus each reachable peer queried live
  (prefixed `<peer>:`) — the federation from your vantage.

## No message loss — two-phase, at-least-once

A one-shot "drain removes, caller stores" is lossy (crash after remove, before store → gone).
So the pull is two-phase:

- outbox writes are atomic (`tmp → rename`) with monotonic `{ts_ms}_{id}` names.
- **`__drain-outbox <pool>`** snapshots the outbox under an exclusive lock and **prints
  without removing**.
- The caller deposits locally, **idempotent by message id** (skips ids already in its inbox
  or `.read/`).
- **`__ack-drain <pool> <ids…>`** then archives exactly those ids to `.drained/`.

A crash between phases just re-delivers on the next drain; inbox de-dupe makes that a no-op.
At-least-once + de-dupe ⇒ nothing lost, nothing duplicated. (`__`-prefixed verbs are internal
transport, documented as such in PROTOCOL.md.)

## Security

**SSH is the entire trust boundary** — a pool reaches exactly the pools it holds SSH
credentials for; no tokens, no new network surface. For least privilege, pin a per-remote key
in `authorized_keys` with `command="agentnet …"`, so a compromised key can only run agentnet,
not an arbitrary shell.

## Backwards compatibility

No `remotes.json` and no federation env ⇒ every code path is today's behaviour. Federation is
a routing check at the top of send/recv/watch/agents that no-ops when nothing is configured.

## Testing

The suite runs the real CLI in isolated `$HOME`s with a **stub `ssh`** that executes the far
command under a *second* isolated `$HOME` — push / spool / drain routing exercised
deterministically, no network, mirroring the stub-`claude` approach. It asserts the load-
bearing bits directly: `pool:agent` survives slugging, `AGENTNET_NAME=self:me` propagates
*through* the ssh hop, the full pull round-trip (spool → pull → no re-deliver after ack), and
correct fan-out to each target agent.

## Phasing

- **Now:** qualified addressing, `remotes.json`, send routing (push + spool), two-phase pull
  in recv/watch, `agents --all`. Purely additive.
- **Later:** direct-peer optimisations, cross-pool broadcast, peer auto-discovery (so pools
  learn each other's peers instead of static config), and a relay mode for the edge case of
  two mutually-inbound-unreachable pools.
