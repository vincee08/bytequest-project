import assert from "node:assert/strict";
import test from "node:test";
import { NextRequest } from "next/server";
import { middleware } from "../src/middleware";

test("API requests bypass page redirects and retain JSON route ownership", async () => {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const publishableKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  delete process.env.NEXT_PUBLIC_SUPABASE_URL;
  delete process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  delete process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  try {
    const response = await middleware(
      new NextRequest("http://localhost/api/reports/released-results"),
    );
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("location"), null);
    assert.equal(response.headers.get("x-middleware-next"), "1");
  } finally {
    if (url === undefined) delete process.env.NEXT_PUBLIC_SUPABASE_URL;
    else process.env.NEXT_PUBLIC_SUPABASE_URL = url;
    if (publishableKey === undefined) delete process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
    else process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY = publishableKey;
    if (anonKey === undefined) delete process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
    else process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = anonKey;
  }
});
