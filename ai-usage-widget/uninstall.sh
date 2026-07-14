#!/usr/bin/env bash
# Remove the AI Usage widget. Leaves your config.json in place unless --purge.
set -euo pipefail

CONFIG_DIR="$HOME/.config/ai-usage-widget"
CACHE_DIR="$HOME/.cache/ai-usage-widget"
PLUGIN_DIR="$HOME/Library/Application Support/SwiftBar/Plugins"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"

echo "▸ Removing SwiftBar plugin symlinks"
rm -f "$PLUGIN_DIR"/aiusage.*.py

echo "▸ Restoring Claude statusLine (removing our hook / restoring any chained command)"
if [ -f "$CLAUDE_SETTINGS" ]; then
  cp "$CLAUDE_SETTINGS" "$CLAUDE_SETTINGS.bak.$(date +%Y%m%d-%H%M%S)" || true
  python3 - "$CLAUDE_SETTINGS" "$CONFIG_DIR/config.json" <<'PY'
import json, sys
settings_path, config_path = sys.argv[1], sys.argv[2]
try:
    with open(settings_path) as f: s = json.load(f)
except Exception:
    s = {}
sl = s.get("statusLine") or {}
if isinstance(sl, dict) and "ai-usage-widget" in (sl.get("command") or ""):
    chained = None
    try:
        with open(config_path) as f:
            chained = ((json.load(f).get("harnesses") or {}).get("claude") or {}).get("chain_command")
    except Exception:
        pass
    if chained:
        s["statusLine"] = {"type": "command", "command": chained, "padding": 0}
    else:
        s.pop("statusLine", None)
    with open(settings_path, "w") as f: json.dump(s, f, indent=2)
PY
fi

if [ "${1:-}" = "--purge" ]; then
  echo "▸ Purging config + cache"
  rm -rf "$CONFIG_DIR" "$CACHE_DIR"
else
  echo "▸ Removing scripts + cache (keeping config.json; pass --purge to remove it too)"
  rm -f "$CONFIG_DIR"/*.py
  rm -rf "$CACHE_DIR"
fi

echo "▸ Done. You may also remove SwiftBar itself: brew uninstall --cask swiftbar"
