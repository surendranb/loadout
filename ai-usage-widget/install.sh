#!/usr/bin/env bash
# Install the AI Usage menu-bar widget (SwiftBar plugin + statusline hooks).
# Idempotent: safe to re-run. Everything it does is local; no network calls
# except an optional Homebrew install of SwiftBar (asked first).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$HOME/.config/ai-usage-widget"
CACHE_DIR="$HOME/.cache/ai-usage-widget"
PLUGIN_DIR="$HOME/Library/Application Support/SwiftBar/Plugins"
REFRESH="${AIUSAGE_REFRESH:-30s}"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"

say() { printf '\033[1;36m▸ %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m! %s\033[0m\n' "$*"; }

# --- prerequisites -----------------------------------------------------------
command -v python3 >/dev/null || { echo "python3 is required."; exit 1; }

if [ ! -d "/Applications/SwiftBar.app" ]; then
  if command -v brew >/dev/null; then
    read -r -p "SwiftBar is not installed. Install it with Homebrew now? [y/N] " a
    [[ "$a" =~ ^[Yy]$ ]] && brew install --cask swiftbar || warn "Skipping SwiftBar install — the plugin won't show until you install it."
  else
    warn "SwiftBar not found and Homebrew unavailable. Install SwiftBar from https://swiftbar.app then re-run."
  fi
fi

# --- lay down files ----------------------------------------------------------
say "Installing scripts to $CONFIG_DIR"
mkdir -p "$CONFIG_DIR" "$CACHE_DIR" "$PLUGIN_DIR"
cp "$REPO/hooks/claude_statusline.py" "$CONFIG_DIR/"
cp "$REPO/plugin/aiusage.30s.py" "$CONFIG_DIR/aiusage.py"
chmod +x "$CONFIG_DIR"/*.py

if [ ! -f "$CONFIG_DIR/config.json" ]; then
  cp "$REPO/config.example.json" "$CONFIG_DIR/config.json"
  say "Created default config: $CONFIG_DIR/config.json"
else
  say "Keeping existing config: $CONFIG_DIR/config.json"
fi

# SwiftBar plugin: named aiusage.<refresh>.py so SwiftBar picks the interval.
ln -sf "$CONFIG_DIR/aiusage.py" "$PLUGIN_DIR/aiusage.$REFRESH.py"

# --- point SwiftBar at the plugin dir ---------------------------------------
BID="$(defaults read /Applications/SwiftBar.app/Contents/Info.plist CFBundleIdentifier 2>/dev/null || echo com.ameba.SwiftBar)"
defaults write "$BID" PluginDirectory -string "$PLUGIN_DIR" || true

# --- wire the Claude statusLine (preserving any existing one) ----------------
if [ -d "$HOME/.claude" ]; then
  say "Wiring Claude Code statusLine hook"
  cp "$CLAUDE_SETTINGS" "$CLAUDE_SETTINGS.bak.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
  HOOK="$CONFIG_DIR/claude_statusline.py" python3 - "$CLAUDE_SETTINGS" "$CONFIG_DIR/config.json" <<'PY'
import json, os, sys
settings_path, config_path = sys.argv[1], sys.argv[2]
hook = os.environ["HOOK"]
try:
    with open(settings_path) as f: s = json.load(f)
except Exception:
    s = {}
existing = s.get("statusLine")
# If a different statusLine command exists, chain it so we don't lose it.
if isinstance(existing, dict) and existing.get("command") and existing["command"] != hook:
    try:
        with open(config_path) as f: c = json.load(f)
    except Exception:
        c = {}
    c.setdefault("harnesses", {}).setdefault("claude", {})["chain_command"] = existing["command"]
    with open(config_path, "w") as f: json.dump(c, f, indent=2)
    print(f"  chained your existing statusLine: {existing['command']}")
s["statusLine"] = {"type": "command", "command": hook, "padding": 0}
with open(settings_path, "w") as f: json.dump(s, f, indent=2)
PY
else
  warn "~/.claude not found — skipping Claude statusLine wiring."
fi

# --- launch ------------------------------------------------------------------
open -a SwiftBar 2>/dev/null || true
say "Done. Look for the widget in your menu bar."
echo "   Config:  $CONFIG_DIR/config.json  (menu bar → Edit config)"
echo "   Antigravity: once you install 'agy' and log in, see README to activate."
