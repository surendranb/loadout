#!/usr/bin/env python3
# <xbar.title>AI Usage</xbar.title>
# <xbar.version>1.1</xbar.version>
# <xbar.author>loadout</xbar.author>
# <xbar.desc>Claude Code + Codex + Gemini usage / rate-limits in the menu bar.</xbar.desc>
# <xbar.dependencies>python3</xbar.dependencies>
#
# SwiftBar/xbar plugin. All data is read from LOCAL files — no network calls,
# no credentials. Behaviour is driven by ~/.config/ai-usage-widget/config.json
# (see config.example.json); anything omitted falls back to DEFAULTS below.
#
# What each harness can show (verified):
#   - Claude Code: real 5h / weekly rate-limit % + reset times, from the cache
#     written by the statusLine hook (claude_statusline.py). Fresh only while a
#     Claude session is active.
#   - Codex: token totals (today / window) from ~/.codex/sessions rollout logs.
#     Business/credit plans expose NO 5h/weekly windows, so tokens are the metric.
#   - Gemini: token totals from ~/.gemini/tmp/*/chats/session-*.json. Google
#     exposes NO rate-limit-remaining locally; chat files are save-point
#     snapshots so recent activity can lag (a "last active" hint is shown).
import os
import re
import sys
import json
import glob
import time
import subprocess
import urllib.request
import datetime as dt

HOME = os.path.expanduser("~")
CONFIG_PATH = os.path.join(HOME, ".config", "ai-usage-widget", "config.json")
CLAUDE_CACHE = os.path.join(HOME, ".cache", "ai-usage-widget", "claude.json")
ANTIGRAVITY_CACHE = os.path.join(HOME, ".cache", "ai-usage-widget", "antigravity.json")
CODEX_SESSIONS = os.path.join(HOME, ".codex", "sessions")
GEMINI_CHATS_GLOB = os.path.join(HOME, ".gemini", "tmp", "*", "chats", "session-*.json")

DEFAULTS = {
    "menubar": {"headline": "auto", "label": "AI"},  # headline: auto|claude|<off>
    "thresholds": {"warn": 60, "critical": 85},
    "harnesses": {
        "claude": {"enabled": True, "label": "Claude Code"},
        "antigravity": {"enabled": True, "label": "Antigravity"},
        "codex": {
            "enabled": True,
            "label": "Codex",
            "window_days": 7,
            "show_cost": True,
            "pricing": {
                "_default": {"in": 1.25, "cached": 0.13, "out": 10.0},
                "gpt-5": {"in": 1.25, "cached": 0.13, "out": 10.0},
            },
        },
        "gemini": {
            "enabled": False,  # Gemini CLI deprecated for AI Pro/free since 2026-06-18 → use Antigravity
            "label": "Gemini CLI",
            "window_days": 7,
            "show_cost": True,
            "pricing": {"_default": {"in": 1.25, "cached": 0.31, "out": 10.0}},
        },
    },
    "colors": {"ok": "#34c759", "warn": "#ff9f0a", "critical": "#ff3b30", "dim": "#8e8e93", "fg": "#e5e5ea"},
    "stale_minutes": 20,
}


# ---------------------------------------------------------------------------
# config
# ---------------------------------------------------------------------------
def deep_merge(base, override):
    out = dict(base)
    for k, v in (override or {}).items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = deep_merge(out[k], v)
        else:
            out[k] = v
    return out


def load_config():
    try:
        with open(CONFIG_PATH) as f:
            return deep_merge(DEFAULTS, json.load(f))
    except Exception:
        return DEFAULTS


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
def human_tokens(n):
    n = float(n or 0)
    if n >= 1_000_000:
        return f"{n / 1_000_000:.2f}M"
    if n >= 1_000:
        return f"{n / 1_000:.1f}K"
    return f"{int(n)}"


def bar(pct, width=10):
    pct = max(0.0, min(100.0, float(pct or 0)))
    filled = int(round(pct / 100 * width))
    return "▓" * filled + "░" * (width - filled)


def color_for(pct, C, th):
    if pct is None:
        return C["dim"]
    if pct < th["warn"]:
        return C["ok"]
    if pct < th["critical"]:
        return C["warn"]
    return C["critical"]


def fmt_reset(unix_ts):
    if not unix_ts:
        return ""
    delta = unix_ts - time.time()
    if delta <= 0:
        return "now"
    if delta < 24 * 3600:
        h, m = int(delta // 3600), int((delta % 3600) // 60)
        return f"in {h}h{m:02d}m" if h else f"in {m}m"
    return time.strftime("%a %-I %p", time.localtime(unix_ts))


def ago(unix_ts):
    if not unix_ts:
        return "never"
    d = int(time.time() - unix_ts)
    for size, unit in ((86400, "d"), (3600, "h"), (60, "m")):
        if d >= size:
            return f"{d // size}{unit} ago"
    return f"{d}s ago"


def days_ago_str(date_obj):
    if not date_obj:
        return "never"
    d = (dt.date.today() - date_obj).days
    if d <= 0:
        return "today"
    if d == 1:
        return "yesterday"
    return f"{d}d ago"


def cost_of(row, pricing, model=""):
    price = pricing.get("_default", {"in": 0, "cached": 0, "out": 0})
    for k, v in pricing.items():
        if k != "_default" and model and model.startswith(k):
            price = v
            break
    non_cached_in = max(0, row.get("in", 0) - row.get("cached", 0))
    return (
        non_cached_in / 1e6 * price.get("in", 0)
        + row.get("cached", 0) / 1e6 * price.get("cached", 0)
        + row.get("out", 0) / 1e6 * price.get("out", 0)
    )


def empty_row():
    return {"in": 0, "out": 0, "cached": 0, "total": 0}


# ---------------------------------------------------------------------------
# Claude
# ---------------------------------------------------------------------------
def read_claude():
    try:
        with open(CLAUDE_CACHE) as f:
            return json.load(f)
    except Exception:
        return None


# ---------------------------------------------------------------------------
# Antigravity (agy) — statusline cache, quota as remaining_fraction per bucket
# ---------------------------------------------------------------------------
# agy runs a local Connect/gRPC server (Exa language server) on ephemeral
# loopback ports while running. Its RetrieveUserQuotaSummary RPC returns the
# real 5h/weekly quota — callable over plain HTTP POST + JSON (no auth needed
# for localhost). Port changes per launch, so we discover it via lsof each run
# and cache the last good result for when agy isn't running.
AGY_RPC = "/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary"
AGY_LABELS = {
    "gemini-5h": "Gemini 5h",
    "gemini-weekly": "Gemini wk",
    "3p-5h": "Claude/GPT 5h",
    "3p-weekly": "Claude/GPT wk",
}


def _agy_ports():
    try:
        out = subprocess.run(
            ["lsof", "-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-c", "agy"],
            capture_output=True, text=True, timeout=3,
        ).stdout
    except Exception:
        return []
    ports = {int(m) for m in re.findall(r"127\.0\.0\.1:(\d+)", out)}
    return sorted(ports)


def _fetch_agy_live():
    for port in _agy_ports():
        try:
            req = urllib.request.Request(
                f"http://127.0.0.1:{port}{AGY_RPC}",
                data=b"{}", method="POST",
                headers={"Content-Type": "application/json"},
            )
            with urllib.request.urlopen(req, timeout=2) as r:
                d = json.loads(r.read().decode())
        except Exception:
            continue
        groups = (d.get("response") or {}).get("groups")
        if groups:
            cache = {"captured_at": int(time.time()), "groups": groups}
            try:
                os.makedirs(os.path.dirname(ANTIGRAVITY_CACHE), exist_ok=True)
                tmp = ANTIGRAVITY_CACHE + ".tmp"
                with open(tmp, "w") as f:
                    json.dump(cache, f)
                os.replace(tmp, ANTIGRAVITY_CACHE)
            except Exception:
                pass
            return cache
    return None


def read_antigravity():
    """Live quota if agy is running, else last-cached."""
    live = _fetch_agy_live()
    if live:
        return live
    try:
        with open(ANTIGRAVITY_CACHE) as f:
            return json.load(f)
    except Exception:
        return None


def _iso_to_unix(s):
    if not s:
        return None
    try:
        return dt.datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


def agy_windows(cache):
    """Return [(label, used_pct, resets_at)] from cached agy quota groups."""
    out = []
    for g in (cache or {}).get("groups") or []:
        for b in g.get("buckets") or []:
            rf = b.get("remainingFraction")
            if rf is None:
                continue
            label = AGY_LABELS.get(b.get("bucketId"), b.get("displayName", "?"))
            out.append((label, (1 - rf) * 100, _iso_to_unix(b.get("resetTime"))))
    return out


# ---------------------------------------------------------------------------
# Codex — sum each session's final cumulative total_token_usage
# ---------------------------------------------------------------------------
def _find_rate_limits(o):
    if isinstance(o, dict):
        if o.get("rate_limits"):
            return o["rate_limits"]
        for v in o.values():
            r = _find_rate_limits(v)
            if r:
                return r
    return None


def read_codex(window_days):
    today = dt.date.today()
    cutoff = today - dt.timedelta(days=window_days - 1)
    agg = {"today": empty_row(), "window": empty_row()}
    model_seen = last_active = plan = credits = None

    files = []
    for path in glob.glob(os.path.join(CODEX_SESSIONS, "*", "*", "*", "rollout-*.jsonl")):
        m = re.search(r"/(\d{4})/(\d{2})/(\d{2})/rollout-", path)
        if not m:
            continue
        d = dt.date(int(m.group(1)), int(m.group(2)), int(m.group(3)))
        files.append((d, path))

    for d, path in files:
        if d >= cutoff:
            best, model = None, None
            try:
                with open(path, errors="ignore") as f:
                    for line in f:
                        if '"model"' in line and model is None:
                            mm = re.search(r'"model":"([^"]+)"', line)
                            if mm:
                                model = mm.group(1)
                        if "total_token_usage" not in line:
                            continue
                        try:
                            obj = json.loads(line)
                        except Exception:
                            continue
                        info = (obj.get("payload") or {}).get("info") or obj.get("info") or {}
                        tu = info.get("total_token_usage")
                        if isinstance(tu, dict) and tu.get("total_tokens") is not None:
                            if best is None or tu["total_tokens"] >= best.get("total_tokens", 0):
                                best = tu
            except Exception:
                continue
            if model:
                model_seen = model
            if best:
                row = {
                    "in": best.get("input_tokens", 0) or 0,
                    "out": best.get("output_tokens", 0) or 0,
                    "cached": best.get("cached_input_tokens", 0) or 0,
                    "total": best.get("total_tokens", 0) or 0,
                }
                for k in row:
                    agg["window"][k] += row[k]
                    if d == today:
                        agg["today"][k] += row[k]
                if last_active is None or d > last_active:
                    last_active = d

    for d, path in sorted(files, reverse=True):
        try:
            with open(path, errors="ignore") as f:
                lines = f.readlines()
        except Exception:
            continue
        for line in reversed(lines):
            if '"rate_limits"' not in line:
                continue
            try:
                rl = _find_rate_limits(json.loads(line))
            except Exception:
                rl = None
            if rl:
                plan, credits = rl.get("plan_type"), rl.get("credits")
                break
        if plan:
            break

    return {"agg": agg, "model": model_seen, "plan": plan, "credits": credits, "last_active": last_active}


# ---------------------------------------------------------------------------
# Gemini — sum per-message token fields (each turn re-bills full context)
# ---------------------------------------------------------------------------
def read_gemini(window_days):
    today = dt.date.today()
    cutoff = today - dt.timedelta(days=window_days - 1)
    agg = {"today": empty_row(), "window": empty_row()}
    last_active = None

    for path in glob.glob(GEMINI_CHATS_GLOB):
        try:
            with open(path, errors="ignore") as f:
                d = json.load(f)
        except Exception:
            continue
        ts = d.get("lastUpdated") or d.get("startTime") or ""
        try:
            day = dt.datetime.fromisoformat(ts.replace("Z", "+00:00")).date()
        except Exception:
            continue
        if last_active is None or day > last_active:
            last_active = day
        if day < cutoff:
            continue
        for msg in d.get("messages", []):
            t = msg.get("tokens")
            if not isinstance(t, dict):
                continue
            row = {
                "in": t.get("input", 0) or 0,
                "out": t.get("output", 0) or 0,
                "cached": t.get("cached", 0) or 0,
                "total": t.get("total", 0) or 0,
            }
            for k in row:
                agg["window"][k] += row[k]
                if day == today:
                    agg["today"][k] += row[k]

    return {"agg": agg, "last_active": last_active}


# ---------------------------------------------------------------------------
# render sections
# ---------------------------------------------------------------------------
def claude_pcts(claude):
    if not (claude and claude.get("rate_limits")):
        return None, None
    rl = claude["rate_limits"]
    return (rl.get("five_hour") or {}).get("used_percentage"), (rl.get("seven_day") or {}).get("used_percentage")


def render_claude(cfg, C, th, hconf):
    claude = read_claude()
    print(f"{hconf.get('label', 'Claude Code')} | color={C['fg']}")
    p5, p7 = claude_pcts(claude)
    if p5 is None and p7 is None:
        print(f"Waiting for an active Claude session… | size=12 color={C['dim']}")
        print(f"Numbers appear once a Claude session makes a request. | size=11 color={C['dim']}")
        return
    rl = claude["rate_limits"]
    for key, label in (("five_hour", "5-hour"), ("seven_day", "Weekly")):
        w = rl.get(key) or {}
        p = w.get("used_percentage")
        if p is None:
            continue
        line = f"{label:7s} {bar(p)} {p:4.0f}%   ↻ {fmt_reset(w.get('resets_at'))}"
        print(f"{line} | font=Menlo size=13 color={color_for(p, C, th)}")
    print(f"account-wide, all models · updated {ago(claude.get('rate_limits_at'))} | size=11 color={C['dim']}")


def render_antigravity(cfg, C, th, hconf, cache):
    print(f"{hconf.get('label', 'Antigravity')} | color={C['fg']}")
    wins = agy_windows(cache)
    if not wins:
        print(f"No quota yet — run agy at least once (it must be logged in). | size=12 color={C['dim']}")
        print(f"Live numbers appear while agy is running. | size=11 color={C['dim']}")
        return
    for label, used, resets_at in wins:
        line = f"{label:13s} {bar(used)} {used:4.0f}%   ↻ {fmt_reset(resets_at)}"
        print(f"{line} | font=Menlo size=13 color={color_for(used, C, th)}")
    cap = (cache or {}).get("captured_at")
    fresh = cap and (time.time() - cap) < 60
    print(f"{'live' if fresh else 'last seen ' + ago(cap)} | size=11 color={C['dim']}")


def render_tokens(name, C, hconf, data, note=None):
    label = hconf.get("label", name.title())
    header = f"{label}"
    if name == "codex" and data.get("plan"):
        cr = data.get("credits") or {}
        suffix = " · unlimited credits" if cr.get("unlimited") else (" · has credits" if cr.get("has_credits") else "")
        header = f"{label} · {data['plan']}{suffix}"
    print(f"{header} | color={C['fg']}")

    wd = hconf.get("window_days", 7)
    t, w = data["agg"]["today"], data["agg"]["window"]
    print(f"Today   {human_tokens(t['total']):>7s} tok | font=Menlo size=13")
    print(f"{wd}d     {human_tokens(w['total']):>7s} tok | font=Menlo size=13")
    print(
        f"        in {human_tokens(w['in'])} · out {human_tokens(w['out'])} · cached {human_tokens(w['cached'])}"
        f" | font=Menlo size=11 color={C['dim']}"
    )
    if hconf.get("show_cost", True):
        c = cost_of(w, hconf.get("pricing", {}), data.get("model", ""))
        print(f"est. {wd}d cost ~${c:.2f}  (approx) | size=11 color={C['dim']}")
    la = data.get("last_active")
    if not w["total"] and la:
        print(f"last active {days_ago_str(la)} | size=11 color={C['dim']}")
    if note:
        print(f"{note} | size=11 color={C['dim']}")


# ---------------------------------------------------------------------------
def main():
    cfg = load_config()
    C = cfg["colors"]
    th = cfg["thresholds"]
    H = cfg["harnesses"]

    # headline: highest live window % across statusline-based harnesses.
    claude = read_claude()
    headline = None
    newest_at = 0
    if H.get("claude", {}).get("enabled", True):
        p5, p7 = claude_pcts(claude)
        for p in (p5, p7):
            if p is not None:
                headline = p if headline is None else max(headline, p)
        if claude and claude.get("rate_limits_at"):
            newest_at = max(newest_at, claude["rate_limits_at"])
    agy = None
    if H.get("antigravity", {}).get("enabled", True):
        agy = read_antigravity()
        for _, used, _ in agy_windows(agy):
            headline = used if headline is None else max(headline, used)
        if agy and agy.get("captured_at"):
            newest_at = max(newest_at, agy["captured_at"])

    stale = newest_at and (time.time() - newest_at) > cfg["stale_minutes"] * 60
    if headline is not None:
        col = C["dim"] if stale else color_for(headline, C, th)
        print(f"{cfg['menubar'].get('label', 'AI')} {headline:.0f}% | color={col}")
    else:
        print(f"{cfg['menubar'].get('label', 'AI')} — | color={C['dim']}")

    print("---")

    first = True
    if H.get("claude", {}).get("enabled", True) and os.path.isdir(os.path.join(HOME, ".claude")):
        render_claude(cfg, C, th, H["claude"])
        first = False

    if H.get("antigravity", {}).get("enabled", True):
        if not first:
            print("---")
        render_antigravity(cfg, C, th, H["antigravity"], agy)
        first = False

    if H.get("codex", {}).get("enabled", True) and os.path.isdir(CODEX_SESSIONS):
        if not first:
            print("---")
        cx = read_codex(H["codex"].get("window_days", 7))
        render_tokens("codex", C, H["codex"], cx, note="No 5h/weekly limits on this plan (credit-based)")
        first = False

    if H.get("gemini", {}).get("enabled", True) and glob.glob(GEMINI_CHATS_GLOB):
        if not first:
            print("---")
        gm = read_gemini(H["gemini"].get("window_days", 7))
        render_tokens("gemini", C, H["gemini"], gm, note="No rate-limit remaining exposed by Google")
        first = False

    print("---")
    print(f"Edit config | bash=open param1={CONFIG_PATH} terminal=false")
    print("Refresh | refresh=true")
    print("Claude usage docs | href=https://code.claude.com/docs/en/costs")


def run_statusline():
    """`aiusage.py --statusline`: Claude Code invokes this on each status-line
    refresh with a JSON blob on stdin. We cache its rate_limits for the widget,
    then print a short status line (chaining any pre-existing command)."""
    raw = sys.stdin.read()
    try:
        d = json.loads(raw)
    except Exception:
        print("")
        return
    rl = d.get("rate_limits")
    try:
        prev = {}
        if os.path.exists(CLAUDE_CACHE):
            with open(CLAUDE_CACHE) as f:
                prev = json.load(f)
        now = int(time.time())
        out = {
            "captured_at": now,
            "rate_limits": rl if rl else prev.get("rate_limits"),
            "rate_limits_at": now if rl else prev.get("rate_limits_at"),
            "model": (d.get("model") or {}).get("display_name") or prev.get("model"),
        }
        os.makedirs(os.path.dirname(CLAUDE_CACHE), exist_ok=True)
        tmp = CLAUDE_CACHE + ".tmp"
        with open(tmp, "w") as f:
            json.dump(out, f)
        os.replace(tmp, CLAUDE_CACHE)
    except Exception:
        pass
    # chain a pre-existing statusLine command, if the installer recorded one
    try:
        with open(CONFIG_PATH) as f:
            chain = ((json.load(f).get("harnesses") or {}).get("claude") or {}).get("chain_command")
    except Exception:
        chain = None
    if chain:
        try:
            r = subprocess.run(chain, shell=True, input=raw, capture_output=True, text=True, timeout=5)
            print(r.stdout.rstrip("\n"))
            return
        except Exception:
            pass
    model = (d.get("model") or {}).get("display_name") or "Claude"
    seg = []
    for key, label in (("five_hour", "5h"), ("seven_day", "7d")):
        p = ((rl or {}).get(key) or {}).get("used_percentage")
        if p is not None:
            seg.append(f"{label} {p:.0f}%")
    print(f"⚙ {model}" + ("   · " + "  ".join(seg) if seg else ""))


if __name__ == "__main__":
    if "--statusline" in sys.argv:
        run_statusline()
    else:
        main()
