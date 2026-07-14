#!/usr/bin/env python3
"""Claude Code statusLine hook for the AI-usage menu-bar widget.

Claude Code invokes this on every status-line refresh, passing a JSON blob on
stdin. Pro/Max subscribers (v2.1.80+) get a `rate_limits` object with the real
5-hour and weekly window percentages + reset times shown by `/usage`. We persist
that to a cache the widget reads, then render a compact status line.

If you already had a statusLine command, the installer records it in config as
harnesses.claude.chain_command; we run it (same stdin) and print its output
instead of our default line, so nothing you had is lost.

No network calls, no credentials.
"""
import sys
import os
import json
import time
import subprocess

HOME = os.path.expanduser("~")
CONFIG = os.path.join(HOME, ".config", "ai-usage-widget", "config.json")
CACHE = os.path.join(HOME, ".cache", "ai-usage-widget", "claude.json")


def cache_rate_limits(d):
    rl = d.get("rate_limits")
    try:
        prev = {}
        if os.path.exists(CACHE):
            with open(CACHE) as f:
                prev = json.load(f)
        now = int(time.time())
        out = {
            "captured_at": now,
            "rate_limits": rl if rl else prev.get("rate_limits"),
            "rate_limits_at": now if rl else prev.get("rate_limits_at"),
            "model": (d.get("model") or {}).get("display_name") or prev.get("model"),
            "version": d.get("version"),
        }
        os.makedirs(os.path.dirname(CACHE), exist_ok=True)
        tmp = CACHE + ".tmp"
        with open(tmp, "w") as f:
            json.dump(out, f)
        os.replace(tmp, CACHE)
    except Exception:
        pass  # best-effort


def chain_command(raw):
    """Run a pre-existing statusLine command with the same stdin, if configured."""
    try:
        with open(CONFIG) as f:
            cmd = ((json.load(f).get("harnesses") or {}).get("claude") or {}).get("chain_command")
    except Exception:
        cmd = None
    if not cmd:
        return None
    try:
        r = subprocess.run(cmd, shell=True, input=raw, capture_output=True, text=True, timeout=5)
        return r.stdout.rstrip("\n")
    except Exception:
        return None


def default_line(d):
    parts = [f"⚙ {(d.get('model') or {}).get('display_name') or 'Claude'}"]
    wd = (d.get("workspace") or {}).get("current_dir") or ""
    if wd:
        parts.append(f"\U0001F4C1 {os.path.basename(wd.rstrip('/'))}")
    rl = d.get("rate_limits") or {}
    seg = []
    for key, label in (("five_hour", "5h"), ("seven_day", "7d")):
        p = (rl.get(key) or {}).get("used_percentage")
        if p is not None:
            seg.append(f"{label} {p:.0f}%")
    if seg:
        parts.append("· " + "  ".join(seg))
    return "   ".join(parts)


def main():
    raw = sys.stdin.read()
    try:
        d = json.loads(raw)
    except Exception:
        print("")
        return
    cache_rate_limits(d)
    chained = chain_command(raw)
    print(chained if chained is not None else default_line(d))


if __name__ == "__main__":
    main()
