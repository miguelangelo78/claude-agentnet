#!/usr/bin/env bash
#
# claude-agentnet uninstaller. Removes the CLI/launcher/hook + the SessionStart hook
# entry from settings.json. PRESERVES your message history + registry by default —
# pass --purge to delete those too.
#
set -euo pipefail
NET_DIR="$HOME/.claude/agent-network"
BIN_DIR="$HOME/.local/bin"
SETTINGS="$HOME/.claude/settings.json"

rm -f "$BIN_DIR/agentnet" "$BIN_DIR/cn"
echo "→ removed PATH symlinks"

if [ -f "$SETTINGS" ]; then
  python3 - "$SETTINGS" "$NET_DIR/session-start-hook.sh" <<'PY'
import json, sys
path, cmd = sys.argv[1], sys.argv[2]
try:
    with open(path) as f: s = json.load(f)
except Exception: sys.exit(0)
ss = s.get("hooks", {}).get("SessionStart", [])
new = [g for g in ss if not any(h.get("command") == cmd for h in g.get("hooks", []))]
if new != ss:
    s.setdefault("hooks", {})["SessionStart"] = new
    with open(path, "w") as f: json.dump(s, f, indent=2)
    print("  - removed SessionStart hook from settings.json")
else:
    print("  · no SessionStart hook to remove")
PY
fi

if [ "${1:-}" = "--purge" ]; then
  rm -rf "$NET_DIR"
  echo "→ purged $NET_DIR (message history + registry deleted)"
else
  rm -f "$NET_DIR/agentnet" "$NET_DIR/cn" "$NET_DIR/session-start-hook.sh" "$NET_DIR/README.md"
  echo "→ removed program files; kept your message history + registry in $NET_DIR"
  echo "  (run './uninstall.sh --purge' to delete those too)"
fi
echo "✓ uninstalled."
