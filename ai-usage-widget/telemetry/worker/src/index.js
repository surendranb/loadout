/**
 * Install + telemetry gateway for ai-usage-widget (PostHog backend).
 *
 * Two layers, deliberately different:
 *
 *   GET  /install.sh  → serve the installer (relayed from GitHub) AND log an
 *                       `install_intent` event at the edge, BY DEFAULT, with
 *                       everything Cloudflare hands us, RAW and unfiltered.
 *                       This is a request log — it's what tells real installs
 *                       from bots/crawlers. Disclosed in the README, and anyone
 *                       can avoid it by installing from GitHub raw instead.
 *
 *   POST /telemetry   → the `install` completion event, sent ONLY after the
 *                       installer asks and the user says yes. Coarse geo only —
 *                       capture matches exactly what the prompt promised.
 *
 * Raw client IP is never stored ($ip:null); all other edge signal is kept.
 * PostHog project key is write-only and safe to expose (wrangler [vars]).
 */

const GATEWAY_VERSION = "4";
const PRODUCT = "ai-usage-widget";
const MAX_PROPS_BYTES = 900000;
const INSTALL_SH_URL =
  "https://raw.githubusercontent.com/surendranb/loadout/main/ai-usage-widget/install.sh";
const REPO_URL = "https://github.com/surendranb/loadout";

// Excluded from the raw capture: raw-IP-bearing and secret headers only.
const DROP_HEADERS = new Set([
  "cookie", "authorization", "cf-connecting-ip", "x-forwarded-for",
  "x-real-ip", "true-client-ip", "forwarded",
]);

const json = (obj, status = 200) =>
  new Response(JSON.stringify(obj), {
    status,
    headers: { "content-type": "application/json" },
  });

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const pathname = url.pathname.toLowerCase();
    const ua = request.headers.get("user-agent") || "";
    const dnt =
      request.headers.get("dnt") === "1" ||
      request.headers.get("sec-gpc") === "1";

    // ── install_intent: default, raw, at the edge ─────────────────────────
    if (request.method === "GET" && (pathname === "/install.sh" || pathname === "/install")) {
      if (!dnt) {
        const p = parseUA(ua);
        ctx.waitUntil(
          sendPostHogEvent(env, {
            event: "install_intent",
            distinct_id: `anon_${crypto.randomUUID()}`,
            properties: edgeRaw(
              {
                client_tool: p.tool,
                os_family: p.os,
                arch_family: p.arch,
                is_ai_agent_ua: p.ai,
                src: (url.searchParams.get("src") || "direct").slice(0, 64),
              },
              request
            ),
          })
        );
      }
      try {
        const upstream = await fetch(INSTALL_SH_URL, {
          cf: { cacheTtl: 300, cacheEverything: true },
        });
        if (!upstream.ok) return new Response("# installer fetch failed\n", { status: 502 });
        return new Response(upstream.body, {
          headers: { "content-type": "text/plain; charset=utf-8", "cache-control": "no-cache" },
        });
      } catch {
        return new Response("# installer unavailable\n", { status: 502 });
      }
    }

    // ── install completion: opt-in, coarse ────────────────────────────────
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
          properties: edgeCoarse(props, request),
        })
      );
      return json({ recorded: true });
    }

    return Response.redirect(REPO_URL, 302);
  },
};

// install_intent: the whole request.cf object + all headers (minus raw-IP /
// secret ones), nothing categorised — future cf fields captured automatically.
function edgeRaw(props, request) {
  const cf = request.cf || {};
  const out = {
    ...props,
    product: PRODUCT,
    via_gateway: true,
    gateway_version: GATEWAY_VERSION,
    $ip: null,
    $geoip_disable: true,
  };
  for (const [k, v] of Object.entries(cf)) {
    out[`cf_${k}`] = v && typeof v === "object" ? JSON.stringify(v) : v;
  }
  for (const [k, v] of request.headers) {
    if (!DROP_HEADERS.has(k.toLowerCase())) out[`h_${k.toLowerCase()}`] = String(v).slice(0, 256);
  }
  return withPostHogGeo(out, cf);
}

// install completion: coarse geo only — matches the installer's prompt exactly.
function edgeCoarse(props, request) {
  const cf = request.cf || {};
  return withPostHogGeo(
    {
      ...props,
      product: PRODUCT,
      via_gateway: true,
      gateway_version: GATEWAY_VERSION,
      $ip: null,
      $geoip_disable: true,
      cf_country: cf.country || "unknown",
      cf_city: cf.city || "unknown",
      cf_region: cf.region || "unknown",
      cf_continent: cf.continent || "unknown",
      cf_timezone: cf.timezone || "unknown",
    },
    cf
  );
}

// Feed PostHog's geo props from CF (not an IP lookup) so its map works.
function withPostHogGeo(out, cf) {
  out.$geoip_country_name = cf.country || "unknown";
  out.$geoip_country_code = cf.country || "unknown";
  out.$geoip_city_name = cf.city || "unknown";
  out.$geoip_subdivision_1_name = cf.region || "unknown";
  out.$geoip_continent_name = cf.continent || "unknown";
  out.$geoip_time_zone = cf.timezone || "unknown";
  return out;
}

function parseUA(ua) {
  const l = (ua || "").toLowerCase();
  let os = "unknown", arch = "unknown", tool = "other", ai = false;
  if (l.includes("darwin") || l.includes("mac")) os = "macOS";
  else if (l.includes("linux")) os = "Linux";
  else if (l.includes("windows")) os = "Windows";
  if (l.includes("arm64") || l.includes("aarch64")) arch = "arm64";
  else if (l.includes("x86_64") || l.includes("amd64")) arch = "x86_64";
  if (l.includes("curl")) tool = "curl";
  else if (l.includes("wget")) tool = "wget";
  else if (l.includes("python")) tool = "python";
  else if (l.includes("mozilla")) tool = "browser";
  if (/claude|cursor|antigravity|gpt|codex|\bai\b/.test(l)) ai = true;
  return { os, arch, tool, ai };
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
