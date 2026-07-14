#!/usr/bin/env bash
# One-step installer for the AI Usage menu-bar widget.
# Local only; the sole network step is an optional Homebrew install of SwiftBar.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HOME/.config/ai-usage-widget"
PLUGINS="$HOME/Library/Application Support/SwiftBar/Plugins"
REFRESH="${AIUSAGE_REFRESH:-30s}"
# Raw source used only when running standalone (installer downloaded on its own,
# not from a full clone). Lets people install just this widget, not all of loadout.
RAW_BASE="${AIUSAGE_RAW_BASE:-https://raw.githubusercontent.com/surendranb/loadout/main/ai-usage-widget}"

command -v python3 >/dev/null || { echo "python3 is required."; exit 1; }

# 1. SwiftBar (the menu-bar host)
if [ ! -d "/Applications/SwiftBar.app" ]; then
  if command -v brew >/dev/null; then
    echo "Installing SwiftBar…"; brew install --cask swiftbar
  else
    echo "Install SwiftBar from https://swiftbar.app, then re-run this script."; exit 1
  fi
fi

# 2. Drop the single self-contained plugin file (from the clone, or fetch it)
mkdir -p "$DEST" "$PLUGINS"
if [ -f "$REPO/plugin/aiusage.30s.py" ]; then
  cp "$REPO/plugin/aiusage.30s.py" "$DEST/aiusage.py"
else
  echo "Fetching plugin…"; curl -fsSL "$RAW_BASE/plugin/aiusage.30s.py" -o "$DEST/aiusage.py"
fi
chmod +x "$DEST/aiusage.py"
ln -sf "$DEST/aiusage.py" "$PLUGINS/aiusage.$REFRESH.py"

# 3. Point SwiftBar at the plugin folder
BID="$(defaults read /Applications/SwiftBar.app/Contents/Info.plist CFBundleIdentifier 2>/dev/null || echo com.ameba.SwiftBar)"
defaults write "$BID" PluginDirectory -string "$PLUGINS" || true

# 4. Wire Claude Code's statusLine to the plugin (chaining any existing one)
if [ -d "$HOME/.claude" ]; then
  S="$HOME/.claude/settings.json"
  cp "$S" "$S.bak.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
  HOOK="python3 $DEST/aiusage.py --statusline" python3 - "$S" "$DEST/config.json" <<'PY'
import json, os, sys
s_path, c_path = sys.argv[1], sys.argv[2]
hook = os.environ["HOOK"]
try:
    s = json.load(open(s_path))
except Exception:
    s = {}
ex = s.get("statusLine")
if isinstance(ex, dict) and ex.get("command") and "ai-usage-widget" not in ex["command"]:
    try: c = json.load(open(c_path))
    except Exception: c = {}
    c.setdefault("harnesses", {}).setdefault("claude", {})["chain_command"] = ex["command"]
    json.dump(c, open(c_path, "w"), indent=2)
    print("  (kept your existing statusLine, now chained)")
s["statusLine"] = {"type": "command", "command": hook, "padding": 0}
json.dump(s, open(s_path, "w"), indent=2)
PY
fi

open -a SwiftBar 2>/dev/null || true
echo "Done — look for the widget in your menu bar (e.g. \"AI 24%\")."
echo "Customize (optional): create $DEST/config.json — see config.example.json."
