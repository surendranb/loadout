# AI Usage — menu-bar widget

A [SwiftBar](https://swiftbar.app) / [xbar](https://xbarapp.com) plugin that shows your AI coding-agent usage in the macOS menu bar: **Claude Code**, **Antigravity** (`agy`), and **Codex**.

All data is read from **local files only** — no network calls, no credentials, no tokens leave your machine.

```
AI 24%                          ← headline: most-constrained live window
─────────────────────────────
Claude Code · Opus 4.8
5-hour  ▓▓░░░░░░░░  15%  ↻ in 1h02m
Weekly  ▓▓░░░░░░░░  24%  ↻ Sat 7 PM
─────────────────────────────
Antigravity
Gemini 5h      ▓░░░░░░░░░  12%  ↻ in 36m
Gemini wk      ▓▓▓▓░░░░░░  38%  ↻ Sun 7 PM
Claude/GPT wk  ▓▓▓░░░░░░░  34%  ↻ Mon 5 PM     live
─────────────────────────────
Codex · business
Today   1.2M tok
7d      5.78M tok
─────────────────────────────
Edit config · Refresh
```

## What each harness can show (and why they differ)

Different tools expose very different things locally. This widget shows the most accurate metric each one actually provides — verified, not assumed.

| Harness | Metric | Source | Notes |
|---|---|---|---|
| **Claude Code** | Real 5h + weekly **% used** + reset times | `statusLine` stdin `rate_limits` (v2.1.80+) | Fresh only while a Claude session is running |
| **Antigravity** (`agy`) | Real 5h + weekly **% used** (Gemini + Claude/GPT groups) | `agy` local loopback RPC `RetrieveUserQuotaSummary` | Live while `agy` runs; shows last-seen otherwise. Undocumented, localhost-only |
| **Codex** | **Token counts** (today / window) + est. cost | `~/.codex/sessions/**/rollout-*.jsonl` | Business/credit plans expose **no** 5h/weekly windows, so tokens are the metric |
| **Gemini CLI** | Token counts (disabled by default) | `~/.gemini/tmp/*/chats/session-*.json` | **Deprecated** — Google stopped serving AI Pro/free on 2026-06-18. Use Antigravity instead |

There is no single universal "% of limit" — only Claude and Antigravity expose rolling windows. Codex (on business/credit plans) and the retired Gemini CLI only expose token consumption.

## Install

```bash
git clone https://github.com/surendranb/loadout
cd loadout/ai-usage-widget
./install.sh
```

The installer: offers to `brew install --cask swiftbar` if needed, copies the plugin + hooks to `~/.config/ai-usage-widget/`, creates `config.json`, and wires Claude Code's `statusLine` (chaining any existing one so nothing is lost). Re-runnable.

Refresh interval defaults to 30s; override with `AIUSAGE_REFRESH=60s ./install.sh`.

## Configure

Edit `~/.config/ai-usage-widget/config.json` (or click **Edit config** in the menu). Anything omitted falls back to built-in defaults.

- `harnesses.<name>.enabled` — turn a harness on/off.
- `harnesses.<name>.label` — display name.
- `harnesses.codex|gemini.window_days` — token window (default 7).
- `harnesses.codex|gemini.pricing` — `$/1M tokens` for the cost estimate (edit per model prefix).
- `thresholds.warn` / `.critical` — % at which bars turn amber / red.
- `colors`, `stale_minutes`, `menubar.label`.

## Antigravity (`agy`) — how it works

Antigravity replaced Gemini CLI. `agy` doesn't write quota to a file, but while it's running it hosts a local [Connect](https://connectrpc.com) server (the Exa language server) on an **ephemeral loopback port**, and its `RetrieveUserQuotaSummary` RPC returns the real 5h + weekly quota for both Gemini and third-party (Claude/GPT) model groups.

The widget calls it directly each refresh:
- Discovers `agy`'s current port via `lsof` (it changes each launch).
- `POST http://127.0.0.1:<port>/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary` with `{}` and `Content-Type: application/json` (localhost, no auth header needed).
- Parses `response.groups[].buckets[]` → `remainingFraction` (→ % used) + `resetTime`.
- Caches the last good result, so the row still shows "last seen …" when `agy` isn't running.

No credentials are read or sent; the call stays on `127.0.0.1`. This is undocumented and may change with `agy` updates — if the numbers stop appearing, re-check the port/route against a running `agy`.

## Security

- No network calls. No credential files are read. Nothing is transmitted.
- The Claude statusLine hook only *reads* the JSON Claude Code hands it and writes the `rate_limits` block to a local cache.
- Your Anthropic/OpenAI/Google credentials are never touched.

## Uninstall

```bash
./uninstall.sh            # removes plugin + scripts, keeps config.json
./uninstall.sh --purge    # also removes config + cache
```

## License

MIT
