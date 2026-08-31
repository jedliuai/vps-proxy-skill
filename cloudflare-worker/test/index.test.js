import assert from "node:assert/strict";
import test from "node:test";

import worker from "../src/index.js";

const TOKEN = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

function createEnvironment({ values = {}, error } = {}) {
  return {
    SUB_TOKEN: TOKEN,
    SUBSCRIPTIONS: {
      async get(key) {
        if (error) throw error;
        return values[key] ?? null;
      },
    },
  };
}

async function fetchSubscription(path, { method = "GET", headers, env } = {}) {
  const request = new Request(`https://sub.example${path}`, { method, headers });
  return worker.fetch(request, env ?? createEnvironment({
    values: { "clash-config": "clash-content", "v2ray-config": "dm1lc3M6Ly9leGFtcGxl" },
  }));
}

function assertNoCacheSecurityHeaders(response) {
  assert.match(response.headers.get("cache-control"), /no-store/);
  assert.match(response.headers.get("cache-control"), /no-cache/);
  assert.equal(response.headers.get("pragma"), "no-cache");
  assert.equal(response.headers.get("expires"), "0");
  assert.equal(response.headers.get("x-content-type-options"), "nosniff");
  assert.equal(response.headers.get("x-frame-options"), "DENY");
  assert.equal(response.headers.get("referrer-policy"), "no-referrer");
}

test("returns the fixed Clash KV value for the exact YAML route", async () => {
  const response = await fetchSubscription(`/${TOKEN}/clash.yaml`);

  assert.equal(response.status, 200);
  assert.equal(response.headers.get("content-type"), "text/yaml; charset=utf-8");
  assert.equal(await response.text(), "clash-content");
  assertNoCacheSecurityHeaders(response);
});

test("returns the fixed V2Ray KV value for the exact text route", async () => {
  const response = await fetchSubscription(`/${TOKEN}/v2ray.txt`);

  assert.equal(response.status, 200);
  assert.equal(response.headers.get("content-type"), "text/plain; charset=utf-8");
  assert.equal(await response.text(), "dm1lc3M6Ly9leGFtcGxl");
  assertNoCacheSecurityHeaders(response);
});

test("subscription query target explicitly chooses the requested format", async () => {
  const clash = await fetchSubscription(`/${TOKEN}/subscription?target=clash`, {
    headers: { "user-agent": "v2rayNG" },
  });
  const v2ray = await fetchSubscription(`/${TOKEN}/subscription?target=v2ray`, {
    headers: { "user-agent": "Clash Verge" },
  });

  assert.equal(await clash.text(), "clash-content");
  assert.equal(clash.headers.get("content-type"), "text/yaml; charset=utf-8");
  assert.equal(await v2ray.text(), "dm1lc3M6Ly9leGFtcGxl");
  assert.equal(v2ray.headers.get("content-type"), "text/plain; charset=utf-8");
});

test("subscription detects common Clash clients as YAML", async () => {
  for (const userAgent of ["Clash", "Mihomo/1.0", "Clash Verge Rev/2.0", "Clash for Windows/0.20.39"]) {
    const response = await fetchSubscription(`/${TOKEN}/subscription`, { headers: { "user-agent": userAgent } });
    assert.equal(await response.text(), "clash-content", userAgent);
  }
});

test("subscription detects V2Ray clients and defaults unknown clients to Base64", async () => {
  for (const userAgent of ["v2rayNG", "Xray-core", "sing-box", "NekoRay", "", "curl/8.0"]) {
    const response = await fetchSubscription(`/${TOKEN}/subscription`, { headers: { "user-agent": userAgent } });
    assert.equal(await response.text(), "dm1lc3M6Ly9leGFtcGxl", userAgent || "empty user agent");
  }
});

test("subscription gives explicit V2Ray client markers precedence over Clash-looking details", async () => {
  const response = await fetchSubscription(`/${TOKEN}/subscription`, {
    headers: { "user-agent": "v2rayNG/1.0 (clash-compatible)" },
  });

  assert.equal(response.status, 200);
  assert.equal(await response.text(), "dm1lc3M6Ly9leGFtcGxl");
});

test("subscription defaults unrecognised User-Agents containing a clash substring to Base64", async () => {
  const response = await fetchSubscription(`/${TOKEN}/subscription`, {
    headers: { "user-agent": "ExampleClashCompatible/1.0" },
  });

  assert.equal(response.status, 200);
  assert.equal(await response.text(), "dm1lc3M6Ly9leGFtcGxl");
});

test("HEAD preserves GET headers while omitting the body", async () => {
  const getResponse = await fetchSubscription(`/${TOKEN}/v2ray.txt`);
  const headResponse = await fetchSubscription(`/${TOKEN}/v2ray.txt`, { method: "HEAD" });

  assert.equal(headResponse.status, 200);
  assert.deepEqual(Object.fromEntries(headResponse.headers), Object.fromEntries(getResponse.headers));
  assert.equal(await headResponse.text(), "");
});

test("rejects invalid tokens, non-exact paths, bad targets, and disallowed methods", async () => {
  const cases = [
    [`/${"a".repeat(63)}/clash.yaml`, "GET"],
    [`/${"b".repeat(64)}/clash.yaml`, "GET"],
    [`/${TOKEN}/clash.yaml/extra`, "GET"],
    [`/${TOKEN}/subscription?target=ss`, "GET"],
    [`/${TOKEN}/v2ray.txt`, "POST"],
  ];

  for (const [path, method] of cases) {
    const response = await fetchSubscription(path, { method });
    assert.equal(response.status, 404, `${method} ${path}`);
    assert.equal(await response.text(), "Not Found");
    assertNoCacheSecurityHeaders(response);
  }
});

test("rejects repeated and non-lowercase target overrides", async () => {
  for (const target of ["clash&target=v2ray", "Clash", "V2RAY"]) {
    const response = await fetchSubscription(`/${TOKEN}/subscription?target=${target}`);
    assert.equal(response.status, 404, target);
    assert.equal(await response.text(), "Not Found");
    assertNoCacheSecurityHeaders(response);
  }
});

test("rejects a configured SUB_TOKEN that is not a 64-character hexadecimal secret", async () => {
  const env = createEnvironment();
  env.SUB_TOKEN = "not-a-valid-token";
  const response = await fetchSubscription(`/${env.SUB_TOKEN}/clash.yaml`, { env });

  assert.equal(response.status, 404);
  assert.equal(await response.text(), "Not Found");
  assertNoCacheSecurityHeaders(response);
});

test("returns a generic no-cache 503 when the selected KV value is missing", async () => {
  const response = await fetchSubscription(`/${TOKEN}/v2ray.txt`, {
    env: createEnvironment({ values: { "clash-config": "clash-content" } }),
  });

  assert.equal(response.status, 503);
  assert.equal(await response.text(), "Service Unavailable");
  assertNoCacheSecurityHeaders(response);
});

test("returns a generic no-cache 503 when KV throws", async () => {
  const response = await fetchSubscription(`/${TOKEN}/clash.yaml`, {
    env: createEnvironment({ error: new Error("KV credential details") }),
  });

  assert.equal(response.status, 503);
  assert.equal(await response.text(), "Service Unavailable");
  assertNoCacheSecurityHeaders(response);
});

test("returns a generic no-cache 503 when the SUBSCRIPTIONS binding is missing", async () => {
  const response = await fetchSubscription(`/${TOKEN}/clash.yaml`, { env: { SUB_TOKEN: TOKEN } });

  assert.equal(response.status, 503);
  assert.equal(await response.text(), "Service Unavailable");
  assertNoCacheSecurityHeaders(response);
});

test("returns a generic no-cache 503 when SUBSCRIPTIONS.get is not callable", async () => {
  const response = await fetchSubscription(`/${TOKEN}/clash.yaml`, {
    env: { SUB_TOKEN: TOKEN, SUBSCRIPTIONS: {} },
  });

  assert.equal(response.status, 503);
  assert.equal(await response.text(), "Service Unavailable");
  assertNoCacheSecurityHeaders(response);
});

test("HEAD error responses omit their body and retain security headers", async () => {
  const responses = [
    await fetchSubscription(`/${TOKEN}/missing`, { method: "HEAD" }),
    await fetchSubscription(`/${TOKEN}/clash.yaml`, {
      method: "HEAD",
      env: createEnvironment({ error: new Error("KV failure") }),
    }),
  ];

  for (const response of responses) {
    assert.ok([404, 503].includes(response.status));
    assert.equal(response.body, null);
    assert.equal(await response.text(), "");
    assertNoCacheSecurityHeaders(response);
  }
});
