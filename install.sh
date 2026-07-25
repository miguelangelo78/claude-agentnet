#!/usr/bin/env bash
#
# claude-agentnet installer — sets up the Claude agent network on this machine.
#   - installs the `agentnet` CLI + `cn` launcher onto your PATH (~/.local/bin)
#   - drops the CLI, launcher, channel server, protocol doc + SessionStart hook into ~/.claude/agent-network/
#   - merges a SessionStart hook into ~/.claude/settings.json (auto-registers every session)
#   - writes the channel MCP config so `cn` can push live messages into a running session
#
# Idempotent + non-destructive — re-run any time to update.
# Works from a clone (bash install.sh) or piped (curl -fsSL .../install.sh | bash).
#
set -euo pipefail

REPO_URL="https://github.com/miguelangelo78/claude-agentnet"
NET_DIR="$HOME/.claude/agent-network"
BIN_DIR="$HOME/.local/bin"
SETTINGS="$HOME/.claude/settings.json"

# Locate source files: next to this script (clone), else clone to a temp dir (curl|bash).
SRC="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
if [ -z "${SRC:-}" ] || [ ! -f "$SRC/bin/agentnet" ]; then
  command -v git >/dev/null 2>&1 || { echo "✗ need git to fetch the source (or run from a clone)" >&2; exit 1; }
  TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
  echo "→ fetching $REPO_URL ..."
  git clone --depth 1 "$REPO_URL" "$TMP/claude-agentnet" >/dev/null 2>&1
  SRC="$TMP/claude-agentnet"
fi
[ -f "$SRC/bin/agentnet" ] || { echo "✗ could not locate agentnet source files" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "✗ python3 is required (the CLI + hook use it)" >&2; exit 1; }

echo "→ installing into $NET_DIR and $BIN_DIR ..."
mkdir -p "$NET_DIR" "$BIN_DIR" "$(dirname "$SETTINGS")"

cp "$SRC/bin/agentnet"                "$NET_DIR/agentnet"
cp "$SRC/bin/fleet-status"            "$NET_DIR/fleet-status"
cp "$SRC/bin/cn"                      "$NET_DIR/cn"
cp "$SRC/bin/agentnet-channel"        "$NET_DIR/agentnet-channel"
cp "$SRC/hooks/session-start-hook.sh" "$NET_DIR/session-start-hook.sh"
cp "$SRC/PROTOCOL.md"                 "$NET_DIR/README.md"
chmod +x "$NET_DIR/agentnet" "$NET_DIR/fleet-status" "$NET_DIR/cn" "$NET_DIR/agentnet-channel" "$NET_DIR/session-start-hook.sh"

# Seed an empty decisions ledger (never clobber an existing one — it accumulates real content).
[ -f "$NET_DIR/DECISIONS.md" ] || cp "$SRC/DECISIONS.md.example" "$NET_DIR/DECISIONS.md"

ln -sf "$NET_DIR/agentnet" "$BIN_DIR/agentnet"
ln -sf "$NET_DIR/cn"       "$BIN_DIR/cn"

# Channel MCP config — `cn` passes this via --mcp-config so the live channel server is
# pulled in ONLY for cn-launched sessions; a bare `claude` never loads it (so it can
# never drain an inbox). See "How messages reach an agent" in the README.
cat > "$NET_DIR/channel-mcp.json" <<JSON
{
  "mcpServers": {
    "agentnet": { "command": "python3", "args": ["$NET_DIR/agentnet-channel"] }
  }
}
JSON

# Merge the SessionStart hook into settings.json (idempotent; preserves everything else).
python3 - "$SETTINGS" "$NET_DIR/session-start-hook.sh" <<'PY'
import json, sys
path, cmd = sys.argv[1], sys.argv[2]
try:
    with open(path) as f: s = json.load(f)
except FileNotFoundError:
    s = {}
except json.JSONDecodeError:
    print("  ⚠ settings.json isn't valid JSON — skipping hook install; add it manually (see README)."); sys.exit(0)
ss = s.setdefault("hooks", {}).setdefault("SessionStart", [])
if any(h.get("command") == cmd for g in ss for h in g.get("hooks", [])):
    print("  · SessionStart hook already present")
else:
    ss.append({"hooks": [{"type": "command", "command": cmd, "timeout": 15, "statusMessage": "Joining agent network..."}]})
    with open(path, "w") as f: json.dump(s, f, indent=2)
    print("  + SessionStart hook added to settings.json")
PY

echo
if "$NET_DIR/agentnet" whoami >/dev/null 2>&1; then
  echo "✓ claude-agentnet installed — you are agent: $("$NET_DIR/agentnet" whoami)"
else
  echo "✗ install verification failed (is python3 on PATH? is $NET_DIR/agentnet executable?)" >&2; exit 1
fi
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "  ⚠ $BIN_DIR is not on your PATH — add it, e.g.:"
     echo "      echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc && exec \"\$SHELL\"" ;;
esac
echo
echo "Next:"
echo "  agentnet agents               # see who's on the network"
echo "  agentnet ask <name> \"...\"      # consult another agent (blocks for a reply)"
echo "  Live in-session messages:     launch 'cn' instead of 'claude' (channels — no prompt)"
echo "                                or 'alias claude=cn' to make every session live"
echo "  Pull queued messages anytime: agentnet recv"
