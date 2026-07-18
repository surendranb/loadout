// Anonymous install-ping relay for ai-usage-widget.
//
// Receives one small JSON ping from install.sh and forwards it to GA4 via the
// Measurement Protocol. The GA API secret lives ONLY here (as a Worker secret),
// never in the public installer or the repo.
//
// Privacy: no PII. We never store IP, hostname, username, or file paths. The
// client_id is a random per-install UUID, not a device fingerprint. Fields are
// an explicit allow-list — arbitrary input is never forwarded to GA.

const GA_ENDPOINT = "https://www.google-analytics.com/mp/collect";
const MAX_BODY = 2048;

// Coerce to a bounded string; drops anything unexpected.
const str = (v, max = 64) =>
  (v === undefined || v === null ? "" : String(v)).slice(0, max);

export default {
  async fetch(request, env) {
    if (request.method !== "POST") {
      return new Response("ai-usage-widget telemetry relay", { status: 405 });
    }

    // Accept (and drop) silently until secrets are configured, so a fresh
    // deploy never breaks installs.
    if (!env.GA_MEASUREMENT_ID || !env.GA_API_SECRET) {
      return new Response(null, { status: 204 });
    }

    let body = {};
    try {
      const raw = (await request.text()).slice(0, MAX_BODY);
      body = raw ? JSON.parse(raw) : {};
    } catch {
      return new Response(null, { status: 204 });
    }

    const harnesses = Array.isArray(body.harnesses)
      ? body.harnesses.map((h) => str(h, 16)).slice(0, 10).join(",")
      : str(body.harnesses, 128);

    // Explicit allow-list — never forward arbitrary keys to GA.
    const params = {
      os: str(body.os, 32),
      arch: str(body.arch, 16),
      widget_version: str(body.widget_version, 16),
      harnesses,
      swiftbar: body.swiftbar ? "1" : "0",
      country: str(request.cf && request.cf.country, 4),
      engagement_time_msec: "1",
    };

    const payload = {
      client_id: str(body.client_id, 64) || crypto.randomUUID(),
      events: [{ name: "install", params }],
    };

    const url =
      `${GA_ENDPOINT}?measurement_id=${encodeURIComponent(env.GA_MEASUREMENT_ID)}` +
      `&api_secret=${encodeURIComponent(env.GA_API_SECRET)}`;

    try {
      await fetch(url, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(payload),
      });
    } catch {
      // Telemetry must never surface errors to the client.
    }

    return new Response(null, { status: 204 });
  },
};
