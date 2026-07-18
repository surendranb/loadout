#!/usr/bin/env bash
# One-step installer for the AI Usage menu-bar widget.
# Network steps: an optional Homebrew install of SwiftBar, fetching the plugin
# when run standalone, and — only if you opt in when asked — one anonymous
# install ping. The installed widget itself makes no network calls at runtime.
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
    echo "Installing SwiftBar…"; brew install --cask swiftbar || true
    # brew records the cask as installed even if the .app was later deleted, so a
    # plain `install` can no-op without placing the app. Repair if still missing.
    if [ ! -d "/Applications/SwiftBar.app" ]; then
      echo "SwiftBar app missing after install — repairing…"; brew reinstall --cask swiftbar || true
    fi
  else
    echo "Install SwiftBar from https://swiftbar.app, then re-run this script."; exit 1
  fi
fi
if [ ! -d "/Applications/SwiftBar.app" ]; then
  echo "Could not install SwiftBar. Install it from https://swiftbar.app and re-run."; exit 1
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

# 2b. Seed an editable config if none exists, so the "Edit config" menu item
# opens a real file (otherwise it opens nothing on machines without Claude).
if [ ! -f "$DEST/config.json" ]; then
  if [ -f "$REPO/config.example.json" ]; then
    cp "$REPO/config.example.json" "$DEST/config.json"
  else
    curl -fsSL "$RAW_BASE/config.example.json" -o "$DEST/config.json" 2>/dev/null || echo '{}' > "$DEST/config.json"
  fi
fi

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

if open -a SwiftBar 2>/dev/null; then
  echo "Done — look for the widget in your menu bar (e.g. \"AI 24%\")."
else
  echo "SwiftBar is installed but macOS blocked its first launch."
  echo "  → System Settings ▸ Privacy & Security ▸ \"Open Anyway\" for SwiftBar,"
  echo "    then run:  open -a SwiftBar"
fi
echo "Customize: click \"Edit config\" in the widget, or edit $DEST/config.json."

# 5. Anonymous install analytics — OPT-IN. We ASK first and send nothing unless
#    you say yes; the install completes either way. Non-interactive runs send
#    nothing (pre-consent with AIUSAGE_TELEMETRY=1). DO_NOT_TRACK=1 forces no.
#    `set +e` so telemetry can never break the install.
set +e
TELEMETRY_URL="${AIUSAGE_TELEMETRY_URL:-https://ai-usage-widget-telemetry.reachsuren.workers.dev/telemetry}"
CONSENT="no"
if [ -n "${DO_NOT_TRACK:-}" ] || [ -n "${AIUSAGE_NO_TELEMETRY:-}" ]; then
  CONSENT="no"
elif [ "${AIUSAGE_TELEMETRY:-}" = "1" ]; then
  CONSENT="yes"
elif [ -t 0 ] && [ -t 1 ]; then
  echo ""
  echo "── Anonymous install analytics (optional) ──────────────────"
  echo "  If you say yes, we send ONE ping: OS + version, CPU arch, this"
  echo "  widget's version, which AI CLIs you use (claude/codex/opencode/…),"
  echo "  and coarse country. No IP, username, hostname, or file contents."
  echo "  Why: to see how many people install, and on what setups."
  echo "  Say no and the install continues exactly the same."
  echo "────────────────────────────────────────────────────────────"
  printf "Send one anonymous install ping? [y/N] "
  read -r ANS
  case "$ANS" in [yY] | [yY][eE][sS]) CONSENT="yes" ;; esac
fi

if [ "$CONSENT" = "yes" ]; then
  # Persistent anonymous id (random, no PII) so re-runs don't double-count.
  ANON_ID="$(cat "$DEST/installation_id" 2>/dev/null || true)"
  if [ -z "$ANON_ID" ]; then
    ANON_ID="inst_$(uuidgen 2>/dev/null | tr 'A-Z' 'a-z')"
    printf '%s' "$ANON_ID" > "$DEST/installation_id" 2>/dev/null || true
  fi
  H=""
  add() { H="${H:+$H,}\"$1\""; }
  [ -d "$HOME/.claude" ] && add claude
  [ -d "$HOME/.codex/sessions" ] && add codex
  [ -d "$HOME/.local/share/opencode/storage" ] && add opencode
  ls "$HOME"/.gemini/tmp/*/chats/session-*.json >/dev/null 2>&1 && add gemini
  { command -v agy >/dev/null 2>&1 || [ -x "$HOME/.local/bin/agy" ]; } && add antigravity
  command -v rtk >/dev/null 2>&1 && add rtk
  VER="$(grep -oE '<xbar.version>[^<]+' "$DEST/aiusage.py" 2>/dev/null | head -1 | sed 's/.*>//')"
  PAYLOAD="$(cat <<JSONEOF
{"anonymous_id":"$ANON_ID","widget_version":"$VER","os_name":"$(uname -s)","os_version":"$(sw_vers -productVersion 2>/dev/null || echo '?')","arch":"$(uname -m)","harnesses_detected":[$H],"swiftbar":true}
JSONEOF
)"
  curl -fsS -m 3 -X POST "$TELEMETRY_URL" -H 'content-type: application/json' -d "$PAYLOAD" >/dev/null 2>&1 \
    && echo "Thanks — anonymous ping sent." || true
else
  echo "No telemetry sent."
fi
set -e
