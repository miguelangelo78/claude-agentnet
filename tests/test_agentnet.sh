#!/usr/bin/env bash
#
# Tests for agentnet. Runs the REAL CLI in an isolated $HOME (never touches your
# real ~/.claude) with a stub `claude` on PATH so the headless `wake` path can be
# tested without the real binary. No test framework — just bash assertions.
#
#   bash tests/test_agentnet.sh
#
set -u

AGENTNET="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/agentnet"
[ -x "$AGENTNET" ] || { echo "✗ agentnet not found/executable at $AGENTNET"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "✗ python3 is required"; exit 1; }

# --- isolated environment -----------------------------------------------------
export HOME="$(mktemp -d)"
STUB_DIR="$(mktemp -d)"
trap 'rm -rf "$HOME" "$STUB_DIR"' EXIT
mkdir -p "$HOME/.local/bin"

# stub `claude` so `wake` has something to spawn; it records how it was called
export STUB_LOG="$STUB_DIR/calls.log"; : > "$STUB_LOG"
cat > "$STUB_DIR/claude" <<'STUB'
#!/usr/bin/env bash
echo "STUB_CLAUDE_CALLED cwd=$PWD args=$*" >> "$STUB_LOG"
STUB
chmod +x "$STUB_DIR/claude"
export PATH="$STUB_DIR:$PATH"

an() { "$AGENTNET" "$@"; }

pass=0; fail=0
ok() { pass=$((pass+1)); echo "  ✓ $1"; }
no() { fail=$((fail+1)); echo "  ✗ $1"; }
has() { if printf '%s' "$2" | grep -qF -- "$3"; then ok "$1"; else no "$1 — expected to contain [$3], got: $2"; fi; }
hasnt() { if printf '%s' "$2" | grep -qF -- "$3"; then no "$1 — should NOT contain [$3]"; else ok "$1"; fi; }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 — expected [$3], got [$2]"; fi; }

echo "agentnet tests (isolated HOME=$HOME)"

# 1. identity
eq   "whoami honors AGENTNET_NAME"            "$(AGENTNET_NAME=alice an whoami)" "alice"
eq   "whoami defaults to cwd basename slug"   "$(cd /tmp && AGENTNET_NAME= an whoami)" "tmp"

# 2. register + agents
AGENTNET_NAME=alice an register --dir /tmp/alice >/dev/null
has  "agents lists a registered agent"        "$(an agents)" "alice"

# 3. send + recv (durable, cross-agent)
AGENTNET_NAME=alice an send bob "hi bob" --no-wake >/dev/null
out="$(AGENTNET_NAME=bob an recv)"
has  "recv delivers the body"                 "$out" "hi bob"
has  "recv shows the sender"                  "$out" "alice"
has  "recv consumes (empty afterwards)"       "$(AGENTNET_NAME=bob an recv)" "no new messages"

# 4. peek does not consume
AGENTNET_NAME=alice an send bob "peek me" --no-wake >/dev/null
AGENTNET_NAME=bob an recv --peek >/dev/null
has  "peek leaves the message in the queue"   "$(AGENTNET_NAME=bob an recv --peek)" "peek me"
AGENTNET_NAME=bob an recv >/dev/null

# 5. broadcast reaches others, excludes self
AGENTNET_NAME=bob an register >/dev/null
AGENTNET_NAME=carol an register >/dev/null
AGENTNET_NAME=alice an send all "hello all" --no-wake >/dev/null
has  "broadcast reaches bob"                  "$(AGENTNET_NAME=bob an recv)"   "hello all"
has  "broadcast reaches carol"                "$(AGENTNET_NAME=carol an recv)" "hello all"
has  "broadcast excludes the sender"          "$(AGENTNET_NAME=alice an recv)" "no new messages"

# 6. self-send guard warns (on stderr) but still delivers
err="$(AGENTNET_NAME=alice an send alice "oops" --no-wake 2>&1 >/dev/null)"
has  "self-send warns loudly"                 "$err" "YOURSELF"

# 7. durable queue for an offline agent
AGENTNET_NAME=alice an send dave "for later" --no-wake >/dev/null
has  "offline agent gets queued msg later"    "$(AGENTNET_NAME=dave an recv)" "for later"

# 8. HEADLESS: wake spawns claude in the target dir with the right flags
AGENTNET_NAME=alice an wake bob --dir "$STUB_DIR" >/dev/null 2>&1
sleep 0.5
calls="$(cat "$STUB_LOG")"
has  "wake invokes claude"                    "$calls" "STUB_CLAUDE_CALLED"
has  "wake runs claude in the target dir"     "$calls" "cwd=$STUB_DIR"
has  "wake passes -p (headless prompt)"        "$calls" "-p"
has  "wake passes bypassPermissions"          "$calls" "bypassPermissions"

# 9. ACTIVE: watch emits one line per inbound message, live
wlog="$STUB_DIR/watch.out"
AGENTNET_NAME=eve an watch --interval 0.2 > "$wlog" 2>&1 &
wpid=$!
sleep 0.4
AGENTNET_NAME=alice an send eve "live message" --no-wake >/dev/null
sleep 1.0
kill "$wpid" 2>/dev/null; wait "$wpid" 2>/dev/null
has  "watch delivers messages live"           "$(cat "$wlog")" "live message"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
