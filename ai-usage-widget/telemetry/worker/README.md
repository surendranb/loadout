# ai-usage-widget telemetry gateway

A tiny Cloudflare Worker with two jobs, forwarding to **PostHog**:

- `GET /install.sh` → serves the installer (relayed from GitHub) and logs an
  **`install_intent`** at the edge, by default, with the raw request metadata
  Cloudflare provides (geo, ASN, TLS, user-agent). This is the human-vs-bot
  signal. Raw IP is never stored. Users who want zero edge logging install from
  GitHub raw instead.
- `POST /telemetry` → the **`install`** completion event, sent only after the
  installer asks and the user says yes. Coarse geo only — matches the prompt.

Why a Worker: strips the sender IP, adds geo from Cloudflare, honors
`DNT`/`Sec-GPC`, and decouples clients from the backend.

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
