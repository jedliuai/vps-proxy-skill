const TOKEN_PATTERN = /^[A-Fa-f0-9]{64}$/;
const NO_CACHE_SECURITY_HEADERS = {
  "cache-control": "no-store, no-cache, must-revalidate, max-age=0",
  pragma: "no-cache",
  expires: "0",
  "x-content-type-options": "nosniff",
  "x-frame-options": "DENY",
  "referrer-policy": "no-referrer",
};

const SUBSCRIPTION_FORMATS = Object.freeze({
  clash: Object.freeze({
    key: "clash-config",
    headers: {
      "content-type": "text/yaml; charset=utf-8",
      "content-disposition": "inline; filename=clash.yaml",
    },
  }),
  v2ray: Object.freeze({
    key: "v2ray-config",
    headers: {
      "content-type": "text/plain; charset=utf-8",
      "content-disposition": "inline; filename=v2ray.txt",
    },
  }),
});

const FIXED_ROUTES = Object.freeze({
  "/clash.yaml": "clash",
  "/v2ray.txt": "v2ray",
});
const V2RAY_USER_AGENT_PATTERN = /\b(?:v2ray(?:ng)?|xray|sing-box|nekoray)\b/i;
const CLASH_USER_AGENT_PATTERN = /^(?:clash(?:(?:[\s._-]+verge(?:[\s._-]+rev)?|forwindows|[\s._-]+for[\s._-]+windows|[\s.-]+meta)(?=[\s/]|$)|\/|$)|mihomo(?:[\s/]|$))/i;

function response(body, status, method, headers = {}) {
  return new Response(method === "HEAD" ? null : body, {
    status,
    headers: { ...NO_CACHE_SECURITY_HEADERS, ...headers },
  });
}

function notFound(method) {
  return response("Not Found", 404, method, { "content-type": "text/plain; charset=utf-8" });
}

function serviceUnavailable(method) {
  return response("Service Unavailable", 503, method, {
    "content-type": "text/plain; charset=utf-8",
    "retry-after": "60",
  });
}

function formatFromUserAgent(userAgent) {
  if (V2RAY_USER_AGENT_PATTERN.test(userAgent)) return "v2ray";
  if (CLASH_USER_AGENT_PATTERN.test(userAgent)) return "clash";
  return "v2ray";
}

function subscriptionFormat(url, request) {
  const targets = url.searchParams.getAll("target");
  if (targets.length === 0) {
    return formatFromUserAgent(request.headers.get("user-agent") ?? "");
  }

  return targets.length === 1 && Object.hasOwn(SUBSCRIPTION_FORMATS, targets[0])
    ? targets[0]
    : null;
}

function routeFormat(url, request, token) {
  const prefix = `/${token}`;
  if (!url.pathname.startsWith(prefix)) return null;

  const route = url.pathname.slice(prefix.length);
  if (Object.hasOwn(FIXED_ROUTES, route)) return FIXED_ROUTES[route];
  if (route === "/subscription") return subscriptionFormat(url, request);
  return null;
}

export default {
  async fetch(request, env) {
    if (request.method !== "GET" && request.method !== "HEAD") return notFound(request.method);

    const token = env.SUB_TOKEN;
    if (typeof token !== "string" || !TOKEN_PATTERN.test(token)) return notFound(request.method);

    const url = new URL(request.url);
    const formatName = routeFormat(url, request, token);
    if (formatName === null) return notFound(request.method);

    const format = SUBSCRIPTION_FORMATS[formatName];
    try {
      const config = await env.SUBSCRIPTIONS.get(format.key, { type: "text" });
      if (config === null) return serviceUnavailable(request.method);
      return response(config, 200, request.method, format.headers);
    } catch {
      return serviceUnavailable(request.method);
    }
  },
};
