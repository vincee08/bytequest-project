import assert from "node:assert/strict";
import test from "node:test";
import { NextRequest } from "next/server";
import { middleware } from "../src/middleware";
import { gateRequest, SESSION_TIMEOUT_PATH } from "../src/lib/auth/session-gate";

const ENV_KEYS = [
  "NEXT_PUBLIC_SUPABASE_URL",
  "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY",
  "NEXT_PUBLIC_SUPABASE_ANON_KEY",
] as const;

async function withEnv(values: Partial<Record<(typeof ENV_KEYS)[number], string>>, run: () => Promise<void>) {
  const saved = Object.fromEntries(ENV_KEYS.map((key) => [key, process.env[key]]));
  for (const key of ENV_KEYS) {
    if (values[key] === undefined) delete process.env[key];
    else process.env[key] = values[key];
  }
  try {
    await run();
  } finally {
    for (const key of ENV_KEYS) {
      if (saved[key] === undefined) delete process.env[key];
      else process.env[key] = saved[key];
    }
  }
}

async function withFetch(stub: typeof fetch, run: () => Promise<void>) {
  const original = globalThis.fetch;
  globalThis.fetch = stub;
  try {
    await run();
  } finally {
    globalThis.fetch = original;
  }
}

const supabaseEnv = {
  NEXT_PUBLIC_SUPABASE_URL: "http://127.0.0.1:54321",
  NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: "sb_publishable_test",
};

const noNetwork: typeof fetch = async () => {
  throw new Error("The session gate must not call Supabase without a session cookie.");
};

// Supabase that accepts the connection but never answers, as during the 504.
const hangingFetch: typeof fetch = (_input, init) =>
  new Promise((_, reject) => {
    init?.signal?.addEventListener("abort", () =>
      reject(new DOMException("The operation was aborted.", "AbortError")),
    );
  });

function sessionCookie() {
  const session = {
    access_token: "header.payload.signature",
    refresh_token: "refresh-token",
    token_type: "bearer",
    expires_in: 3600,
    expires_at: Math.floor(Date.now() / 1000) + 3600,
    user: { id: "00000000-0000-4000-8000-000000000001", aud: "authenticated", role: "authenticated" },
  };
  return `sb-127-auth-token=${encodeURIComponent(JSON.stringify(session))}`;
}

function request(path: string, cookie?: string) {
  return new NextRequest(`http://localhost${path}`, cookie ? { headers: { cookie } } : undefined);
}

test("API requests bypass page redirects and retain JSON route ownership", async () => {
  await withEnv({}, async () => {
    const response = await middleware(request("/api/reports/released-results"));
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("location"), null);
    assert.equal(response.headers.get("x-middleware-next"), "1");
  });
});

test("signed-out visitors reach the login page without a Supabase round trip", async () => {
  await withEnv(supabaseEnv, () =>
    withFetch(noNetwork, async () => {
      const login = await middleware(request("/login?fbclid=shared-link"));
      assert.equal(login.headers.get("x-middleware-next"), "1");
      assert.equal(login.headers.get("location"), null);

      const protectedPage = await middleware(request("/analytics"));
      assert.equal(protectedPage.status, 307);
      assert.equal(new URL(protectedPage.headers.get("location")!).pathname, "/login");
    }),
  );
});

test("an unresponsive Supabase cannot hold the request past the session deadline", async () => {
  await withEnv(supabaseEnv, () =>
    withFetch(hangingFetch, async () => {
      const started = Date.now();
      const login = await gateRequest(request("/login", sessionCookie()), { deadlineMs: 150 });
      assert.ok(Date.now() - started < 2_000, "the login page must render after the deadline");
      assert.equal(login.headers.get("x-middleware-next"), "1");

      const page = await gateRequest(request("/classes", sessionCookie()), { deadlineMs: 150 });
      const location = new URL(page.headers.get("location")!);
      assert.equal(`${location.pathname}${location.search}`, SESSION_TIMEOUT_PATH);
    }),
  );
});
