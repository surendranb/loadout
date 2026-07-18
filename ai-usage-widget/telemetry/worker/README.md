# ai-usage-widget telemetry sink

A tiny Cloudflare Worker that receives the **opt-in** install ping from
`install.sh` and forwards it to **PostHog**. The installer asks the user first,
so this Worker only ever gets a ping when they said yes.

Why a Worker (not a direct PostHog call): it strips the sender IP, adds coarse
geo from Cloudflare, honors `DNT`/`Sec-GPC`, and decouples clients from the
backend — swap PostHog projects without anyone re-installing.

## No secrets

The PostHog project key is **write-only and safe to expose**, so it lives in
`wrangler.toml` `[vars]` (`POSTHOG_API_KEY`, `POSTHOG_HOST`). Nothing to
`wrangler secret put`. To use a different PostHog project, edit those vars.

## What it forwards

Event `install` (property `product: "ai-usage-widget"`), `distinct_id` = the
random `inst_<uuid>` the installer mints. Properties: `widget_version`,
`os_name`/`os_version`, `arch`, `harnesses_detected`, plus edge-added coarse geo
(country/city/region). IP is nulled. This matches exactly what the installer's
prompt tells the user — capture never exceeds the disclosure.

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
# expect: {"recorded":true}. Confirm in PostHog → the `install` event.
```
