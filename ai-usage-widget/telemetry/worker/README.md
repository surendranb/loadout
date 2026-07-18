# ai-usage-widget telemetry relay

A tiny Cloudflare Worker that receives the **one-time anonymous install ping**
from `install.sh` and forwards it to **PostHog**. Same pattern as the GA4-MCP
telemetry worker.

Why a Worker (not a direct PostHog call): it strips the sender IP, stamps coarse
geo (from Cloudflare), honors `DNT`/`Sec-GPC`, and decouples installed clients
from the backend — swap PostHog projects without anyone re-installing.

## No secrets

The PostHog project key is **write-only and safe to expose**, so it lives in
`wrangler.toml` `[vars]` (`POSTHOG_API_KEY`, `POSTHOG_HOST`). Nothing to
`wrangler secret put`. To use a different PostHog project, edit those vars.

## What it sends

Event `install` (property `product: "ai-usage-widget"`), `distinct_id` = the
persistent random `inst_<uuid>` the installer mints. Properties: `widget_version`,
`os_name`/`os_version`, `arch`, `shell_type`, `terminal_app`, `execution_mode`
(human vs headless agent), `harnesses_detected`, plus edge-added coarse geo.
IP is dropped. Opt out with `DO_NOT_TRACK=1` / `AIUSAGE_NO_TELEMETRY=1`.

## Deploy

```bash
cd telemetry/worker
npx wrangler deploy
```

## Test

```bash
curl -s -X POST https://<your-worker-url>/telemetry \
  -H 'content-type: application/json' \
  -d '{"anonymous_id":"inst_test","widget_version":"1.1","os_name":"Darwin",
       "arch":"arm64","harnesses_detected":["claude","opencode"],"swiftbar":true}'
# expect: {"recorded":true}. Confirm in PostHog → Activity / the `install` event.
```
