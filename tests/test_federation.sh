#!/usr/bin/env bash
#
# Federation tests for agentnet (multi-remote pools). Runs the REAL CLI in isolated
# $HOMEs with a stub `ssh` that executes the far command under a SECOND isolated $HOME
# (the "remote pool") — so push / spool / drain routing is exercised with NO network,
# mirroring the stub-`claude` approach in test_agentnet.sh.
#
#   bash tests/test_federation.sh
#
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENTNET="$REPO/bin/agentnet"
[ -x "$AGENTNET" ] || { echo "✗ agentnet not found/executable at $AGENTNET"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "✗ python3 is required"; exit 1; }

# --- isolated environment -----------------------------------------------------
BASE="$(mktemp -d)"
trap 'rm -rf "$BASE"' EXIT
export STUB_SSH_ROOT="$BASE/remotes"        # each ssh target gets $STUB_SSH_ROOT/<target>
STUB_DIR="$BASE/stub"; mkdir -p "$STUB_DIR"

# `agentnet` on PATH for both local and stub-ssh'd remote invocations.
ln -sf "$AGENTNET" "$STUB_DIR/agentnet"

# stub `claude` (wake path) — records calls, never really runs.
cat > "$STUB_DIR/claude" <<'STUB'
#!/usr/bin/env bash
echo "STUB_CLAUDE cwd=$PWD args=$*" >> "${STUB_LOG:-/dev/null}"
STUB
chmod +x "$STUB_DIR/claude"

# stub `ssh`: `ssh [opts] <target> <cmd...>` → run <cmd> under a per-target isolated HOME.
# Skips -o/-i option pairs and other flags; first bare arg is the target; the rest is the
# remote command string (a shell snippet like `AGENTNET_NAME=x agentnet send ...`).
cat > "$STUB_DIR/ssh" <<'STUB'
#!/usr/bin/env bash
target=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o|-i|-p|-l) shift 2; continue;;
    -*) shift; continue;;
    *) target="$1"; shift; break;;
  esac
done
cmd="$*"
slug="$(printf '%s' "$target" | tr -c 'a-zA-Z0-9_-' '-')"
rhome="$STUB_SSH_ROOT/$slug"; mkdir -p "$rhome"
# Remote pool runs with its OWN $HOME (own agent-network) + agentnet on PATH.
HOME="$rhome" PATH="$STUB_AGENTNET_DIR:$PATH" bash -c "$cmd"
STUB
chmod +x "$STUB_DIR/ssh"
export STUB_AGENTNET_DIR="$STUB_DIR"
export PATH="$STUB_DIR:$PATH"

# Local pool HOME (the "laptop").
export HOME="$BASE/local"; mkdir -p "$HOME/.local/bin"
export STUB_LOG="$BASE/claude_calls.log"; : > "$STUB_LOG"

an() { "$AGENTNET" "$@"; }
# run agentnet as a specific remote pool's HOME (for asserting far-side inbox state)
an_at() { local h="$STUB_SSH_ROOT/$1"; shift; HOME="$h" "$AGENTNET" "$@"; }

pass=0; fail=0
ok() { pass=$((pass+1)); echo "  ✓ $1"; }
no() { fail=$((fail+1)); echo "  ✗ $1"; }
has()   { if printf '%s' "$2" | grep -qF -- "$3"; then ok "$1"; else no "$1 — expected [$3] in: $2"; fi; }
hasnt() { if printf '%s' "$2" | grep -qF -- "$3"; then no "$1 — should NOT contain [$3]"; else ok "$1"; fi; }
eq()    { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 — expected [$3], got [$2]"; fi; }

echo "agentnet federation tests (BASE=$BASE)"

# ── FED-2: identity preserves the pool:agent qualifier (colon survives slugging) ──
eq "whoami preserves pool:agent"       "$(AGENTNET_NAME=laptop:alice an whoami)" "laptop:alice"
eq "whoami still slugs a bare name"    "$(AGENTNET_NAME='My Agent' an whoami)" "my-agent"
eq "whoami slugs each qualified part"  "$(AGENTNET_NAME='VPS:Were Gild' an whoami)" "vps:were-gild"

# ── FED-1: config loader via `agentnet remotes` ──
# no config → legacy: a self pool, no remotes.
out="$(AGENTNET_SELF=laptop an remotes)"
has "remotes shows self"               "$out" "laptop"
has "remotes: none configured"         "$out" "(no remotes"

# remotes.json (human-authored): vps reachable (has ssh), laptop pull-only (no ssh).
mkdir -p "$HOME/.claude/agent-network"
cat > "$HOME/.claude/agent-network/remotes.json" <<JSON
{ "self": "laptop",
  "remotes": {
    "vps":    { "ssh": "user@server" },
    "backup": { "reachable": false }
  } }
JSON
out="$(an remotes)"
has "remotes lists self from file"     "$out" "laptop"
has "remotes lists a reachable remote" "$out" "vps"
has "reachable remote shows its ssh"   "$out" "user@server"
has "remotes lists a pull-only remote" "$out" "backup"
has "pull-only remote is marked"       "$out" "pull-only"

# env override wins / augments with zero files.
out="$(AGENTNET_SELF=box2 AGENTNET_REMOTES='vps=user@server,other=me@h2' an remotes 2>/dev/null)"
has "env self override"                "$out" "box2"
has "env remote 1"                     "$out" "vps"
has "env remote 2"                     "$out" "other"

# ── FED-3: send routing (local / push / spool) — HOME=local has remotes.json {vps ssh, backup pull-only} ──
# cross-pool PUSH to a reachable remote: the far CLI runs over (stub) ssh and stamps
# from=<self>:<me>. Assert the env propagates THROUGH ssh (the load-bearing reply bit).
AGENTNET_NAME=alice an send vps:bob "hello bob" --no-wake >/dev/null 2>&1
far="$(HOME="$STUB_SSH_ROOT/user-server" AGENTNET_NAME=bob "$AGENTNET" recv)"
has "push: delivered to far pool inbox"        "$far" "hello bob"
has "push: from is qualified self:me thru ssh" "$far" "laptop:alice"

# cross-pool to a PULL-ONLY remote → spooled locally (no ssh, no wake).
AGENTNET_NAME=alice an send backup:someone "spooled hello" >/dev/null 2>&1
spoolf="$(cat "$HOME/.claude/agent-network/outbox/backup/"*.json 2>/dev/null)"
has "spool: pull-only target queued to outbox" "$spoolf" "spooled hello"
has "spool: from qualified with own pool"      "$spoolf" "laptop:alice"
has "spool: to preserves the dest pool"        "$spoolf" "backup:someone"

# self:agent routes LOCALLY (self prefix stripped); bare from.
AGENTNET_NAME=alice an send laptop:bob "self-pool local" --no-wake >/dev/null 2>&1
has "self:agent routes locally"                "$(AGENTNET_NAME=bob an recv)" "self-pool local"

# unknown pool → clear error.
err="$(AGENTNET_NAME=x an send nosuch:agent "x" 2>&1 >/dev/null)"
has "unknown pool errors clearly"              "$err" "unknown remote pool"

# ── FED-4: two-phase drain — __drain-outbox prints WITHOUT removing; __ack-drain archives ──
AGENTNET_NAME=alice an send backup:another "second spooled" >/dev/null 2>&1
drained="$(an __drain-outbox backup)"
has "drain prints spooled msg 1"                 "$drained" "spooled hello"
has "drain prints spooled msg 2"                 "$drained" "second spooled"
has "drain is non-destructive (re-drain sees it)" "$(an __drain-outbox backup)" "spooled hello"
id1="$(printf '%s\n' "$drained" | head -1 | python3 -c 'import sys,json;print(json.loads(sys.stdin.readline())["id"])')"
an __ack-drain backup "$id1" >/dev/null
after="$(an __drain-outbox backup)"
hasnt "acked message removed from outbox"        "$after" "spooled hello"
has "un-acked message still present"             "$after" "second spooled"

# ── FED-5: full NAT reply round-trip — bob (vps) can't reach laptop → spools on vps;
#           laptop PULLS via recv (drains the vps outbox, deposits to the target agent). ──
VPS="$STUB_SSH_ROOT/user-server"; mkdir -p "$VPS/.claude/agent-network"
cat > "$VPS/.claude/agent-network/remotes.json" <<JSON
{ "self": "vps", "remotes": { "laptop": { "reachable": false } } }
JSON
HOME="$VPS" AGENTNET_NAME=bob "$AGENTNET" send laptop:alice "reply from bob" >/dev/null 2>&1
rr="$(AGENTNET_NAME=alice an recv)"
has  "recv pulls the spooled cross-pool reply"  "$rr" "reply from bob"
has  "pulled reply is from vps:bob"        "$rr" "vps:bob"
hasnt "second recv does NOT re-deliver (acked)" "$(AGENTNET_NAME=alice an recv)" "reply from bob"

# fan-out: a spooled message for a DIFFERENT local agent lands in THAT agent's inbox, not
# in whoever triggered the drain.
HOME="$VPS" AGENTNET_NAME=bob "$AGENTNET" send laptop:bob "for bob only" >/dev/null 2>&1
AGENTNET_NAME=alice an recv >/dev/null 2>&1        # alice drains → fans out
hasnt "drain did NOT misroute bob's msg to me"  "$(AGENTNET_NAME=alice an recv)" "for bob only"
has   "bob receives his own pulled message"     "$(AGENTNET_NAME=bob an recv)" "for bob only"

# agents --all aggregates the federation view.
HOME="$VPS" AGENTNET_NAME=bob "$AGENTNET" register --dir /tmp/w >/dev/null 2>&1
AGENTNET_NAME=alice an register --dir /tmp/al >/dev/null 2>&1
alls="$(an agents --all 2>/dev/null)"
has "agents --all shows local agent as self:"   "$alls" "laptop:alice"
has "agents --all shows remote agent as vps:"    "$alls" "vps:bob"

# ── `remote` command: manage remotes.json without hand-editing ──
export HOME="$BASE/rmcmd"; mkdir -p "$HOME/.local/bin"
an remote self mybox >/dev/null
eq   "remote self sets the pool name"       "$(an remote self)" "mybox"
an remote add server user@host >/dev/null
an remote add phone >/dev/null
out="$(an remotes)"
has  "remote add <ssh> → reachable"         "$out" "user@host"
has  "remote add <no ssh> → pull-only"      "$out" "pull-only"
has  "list shows self"                      "$out" "mybox"
has  "reachable remote listed"              "$out" "server"
has  "pull-only remote listed"              "$out" "phone"
an remote rm server >/dev/null
hasnt "remote rm removes it"                "$(an remotes)" "user@host"
has  "remote rm keeps the other remote"     "$(an remotes)" "phone"
# a CLI-authored remotes.json drives real routing: send to the pull-only pool spools.
AGENTNET_NAME=me an send phone:someone "hi phone" >/dev/null 2>&1
has  "CLI-authored config routes (spool)"   "$(cat "$HOME/.claude/agent-network/outbox/phone/"*.json 2>/dev/null)" "hi phone"
export HOME="$BASE/local"

# ── backwards-compat: with no federation config, core verbs behave exactly as before ──
export HOME="$BASE/legacy"; mkdir -p "$HOME/.local/bin"
AGENTNET_NAME=alice an register --dir /tmp/alice >/dev/null
AGENTNET_NAME=alice an send bob "hi bob" --no-wake >/dev/null
has "legacy send/recv unaffected"      "$(AGENTNET_NAME=bob an recv)" "hi bob"
export HOME="$BASE/local"

echo ""
echo "federation: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
