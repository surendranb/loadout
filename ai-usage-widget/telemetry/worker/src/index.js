/**
 * Anonymous install-telemetry sink for ai-usage-widget (opt-in).
 *
 * The installer ASKS the user before sending anything, so this Worker only ever
 * receives a ping when the user said yes. It strips the sender IP and adds
 * coarse geo (country/city/region) — matching exactly what the installer's
 * prompt promises — then forwards to PostHog. The PostHog project key is
 * write-only and safe to expose, so it lives in wrangler [vars]; no secrets.
 */

const GATEWAY_VERSION = "3";
const PRODUCT = "ai-usage-widget";
const MAX_PROPS_BYTES = 900000;
const REPO_URL = "https://github.com/surendranb/loadout";

const json = (obj, status = 200) =>
  new Response(JSON.stringify(obj), {
    status,
    headers: { "content-type": "application/json" },
  });

export default {
  async fetch(request, env, ctx) {
    const pathname = new URL(request.url).pathname.toLowerCase();
    const dnt =
      request.headers.get("dnt") === "1" ||
      request.headers.get("sec-gpc") === "1";

    if (request.method === "POST" && (pathname === "/telemetry" || pathname === "/")) {
      if (dnt) return json({ recorded: false, reason: "dnt" });
      let body;
      try {
        body = await request.json();
      } catch {
        return json({ recorded: false, reason: "invalid_json" }, 400);
      }
      let props = body && typeof body === "object" ? { ...body } : {};
      delete props.anonymous_id;
      if (JSON.stringify(props).length > MAX_PROPS_BYTES) props = { payload_truncated: true };
      ctx.waitUntil(
        sendPostHogEvent(env, {
          event: "install",
          distinct_id: String(body.anonymous_id || `anon_${crypto.randomUUID()}`).slice(0, 200),
          properties: withEdge(props, request),
        })
      );
      return json({ recorded: true });
    }

    return Response.redirect(REPO_URL, 302);
  },
};

// Consented event → product tag + coarse geo from Cloudflare. Never the raw IP;
// $geoip_disable stops PostHog's own IP lookup, and we feed $geoip_* from CF so
// its map still works.
function withEdge(props, request) {
  const cf = request.cf || {};
  return {
    ...props,
    product: PRODUCT,
    via_gateway: true,
    gateway_version: GATEWAY_VERSION,
    $ip: null,
    $geoip_disable: true,
    $geoip_country_name: cf.country || "unknown",
    $geoip_country_code: cf.country || "unknown",
    $geoip_city_name: cf.city || "unknown",
    $geoip_subdivision_1_name: cf.region || "unknown",
    $geoip_continent_name: cf.continent || "unknown",
    $geoip_time_zone: cf.timezone || "unknown",
    cf_country: cf.country || "unknown",
    cf_city: cf.city || "unknown",
    cf_region: cf.region || "unknown",
    cf_continent: cf.continent || "unknown",
    cf_timezone: cf.timezone || "unknown",
  };
}

async function sendPostHogEvent(env, payload) {
  if (!env.POSTHOG_API_KEY || !env.POSTHOG_HOST) return;
  try {
    await fetch(`${env.POSTHOG_HOST}/capture/`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        api_key: env.POSTHOG_API_KEY,
        event: payload.event,
        distinct_id: payload.distinct_id,
        properties: payload.properties,
        timestamp: new Date().toISOString(),
      }),
    });
  } catch {
    // Telemetry must never surface errors.
  }
}
