/**
 * Install + telemetry gateway for ai-usage-widget (PostHog backend).
 *
 * Two signals, mirroring the GA4-MCP pattern:
 *   GET  /install.sh  → serve the installer (relayed from GitHub) AND log an
 *                       `install_intent` event at the edge — captures everyone
 *                       who STARTED, before any client-side opt-out.
 *   POST /telemetry   → `install` completion event from the installer itself,
 *                       which respects DO_NOT_TRACK / AIUSAGE_NO_TELEMETRY.
 *
 * install_intent count vs install count = opt-out / drop-off rate.
 *
 * The PostHog project key is write-only and safe to expose (wrangler [vars]).
 * No IP stored; only coarse geo from Cloudflare.
 */

const GATEWAY_VERSION = "2";
const PRODUCT = "ai-usage-widget";
const MAX_PROPS_BYTES = 900000;
const INSTALL_SH_URL =
  "https://raw.githubusercontent.com/surendranb/loadout/main/ai-usage-widget/install.sh";
const REPO_URL = "https://github.com/surendranb/loadout";

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

    // ── Edge signal: serve the installer + log intent ─────────────────────
    if (request.method === "GET" && (pathname === "/install.sh" || pathname === "/install")) {
      const p = parseUA(ua);
      if (!dnt) {
        ctx.waitUntil(
          sendPostHogEvent(env, {
            event: "install_intent",
            distinct_id: `anon_${crypto.randomUUID()}`,
            properties: withEdge(
              {
                user_agent: ua.slice(0, 200),
                is_curl: p.tool === "curl" || p.tool === "wget",
                client_tool: p.tool,
                os_family: p.os,
                arch_family: p.arch,
                is_ai_agent_ua: p.ai,
                referer: (request.headers.get("referer") || "direct").slice(0, 200),
                src: (url.searchParams.get("src") || "direct").slice(0, 64),
              },
              request
            ),
          })
        );
      }
      // Relay the current installer from GitHub (single source of truth).
      try {
        const upstream = await fetch(INSTALL_SH_URL, {
          cf: { cacheTtl: 300, cacheEverything: true },
        });
        if (!upstream.ok) return new Response("# installer fetch failed\n", { status: 502 });
        return new Response(upstream.body, {
          headers: {
            "content-type": "text/plain; charset=utf-8",
            "cache-control": "no-cache",
          },
        });
      } catch {
        return new Response("# installer unavailable\n", { status: 502 });
      }
    }

    // ── Completion signal: install-time ping from the installer ───────────
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

// Capture EVERYTHING the edge hands us — the whole request.cf object plus all
// request headers — so nothing is dropped and any field Cloudflare adds later
// is picked up automatically. The one deliberate exclusion is the raw client IP
// (and IP-bearing headers): $ip is nulled and $geoip_disable stops PostHog's own
// IP lookup; we feed $geoip_* from CF instead so the PostHog map still works.
const DROP_HEADERS = new Set([
  "cookie", "authorization", "cf-connecting-ip", "x-forwarded-for",
  "x-real-ip", "true-client-ip", "forwarded",
]);

function withEdge(props, request) {
  const cf = request.cf || {};

  // Whole cf object, flattened (nested objects stringified so nothing is lost).
  const cfProps = {};
  for (const [k, v] of Object.entries(cf)) {
    cfProps[`cf_${k}`] = v && typeof v === "object" ? JSON.stringify(v) : v;
  }

  // All request headers except IP-bearing / secret ones.
  const headerProps = {};
  for (const [k, v] of request.headers) {
    if (!DROP_HEADERS.has(k.toLowerCase())) {
      headerProps[`h_${k.toLowerCase()}`] = String(v).slice(0, 256);
    }
  }

  return {
    ...props,
    ...cfProps,
    ...headerProps,
    product: PRODUCT,
    via_gateway: true,
    gateway_version: GATEWAY_VERSION,
    $ip: null,
    $geoip_disable: true,
    // PostHog geo props from CF (not from an IP lookup) so its map works.
    $geoip_country_name: cf.country || "unknown",
    $geoip_country_code: cf.country || "unknown",
    $geoip_city_name: cf.city || "unknown",
    $geoip_subdivision_1_name: cf.region || "unknown",
    $geoip_continent_name: cf.continent || "unknown",
    $geoip_time_zone: cf.timezone || "unknown",
  };
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
