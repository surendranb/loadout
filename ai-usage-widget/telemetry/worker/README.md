# ai-usage-widget telemetry relay

A tiny Cloudflare Worker that receives the **one-time anonymous install ping**
from `install.sh` and forwards it to GA4 via the Measurement Protocol.

Why a Worker: the GA4 **API secret stays here** (a Worker secret), never in the
public installer. The Worker also adds coarse country (from Cloudflare) and
enforces an allow-list so only known fields ever reach GA.

## What it sends to GA4

Event `install` with params: `os`, `arch`, `widget_version`, `harnesses`
(comma-separated: which of claude/codex/opencode/gemini/agy/rtk were detected),
`swiftbar`, `country`. `client_id` is a random per-install UUID.

No IP, hostname, username, or paths. Users opt out with `DO_NOT_TRACK=1` or
`AIUSAGE_NO_TELEMETRY=1` (the ping is simply never sent).

## Deploy

```bash
cd telemetry/worker
npx wrangler deploy
```

## Configure the two GA secrets (never committed)

Create these in GA4 Admin → Data Streams → your stream → **Measurement
Protocol API secrets**, then:

```bash
npx wrangler secret put GA_MEASUREMENT_ID   # e.g. G-XXXXXXXXXX
npx wrangler secret put GA_API_SECRET       # the Measurement Protocol secret
```

Until both are set, the Worker accepts pings and drops them (installs never
break).

## Test

```bash
curl -s -X POST https://<your-worker-url> \
  -H 'content-type: application/json' \
  -d '{"client_id":"test-uuid","os":"macOS 15.6","arch":"arm64",
       "widget_version":"1.1","harnesses":["claude","opencode"],"swiftbar":true}'
# expect: HTTP 204. Confirm in GA4 Admin → DebugView / Realtime.
```
