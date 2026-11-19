// Shared harness for route-level tests: drives the real Next.js route
// handlers while Supabase Auth and PostgREST are answered by a fake global
// fetch. `server-only` is a bundler guard; it is stubbed so server modules
// load under plain Node (as Jest module mappers do). Not a test file itself
// (scripts/test-web.mjs only discovers tests/*.test.ts[x]).
const serverOnly = require.resolve('server-only');
require.cache[serverOnly] = { id: serverOnly, filename: serverOnly, loaded: true, exports: {} } as unknown as NodeJS.Module;

export type FakeCall = { method: string; path: string; body: unknown };
export type FakeReply = { status: number; body: unknown };
type RpcFn = (body: Record<string, unknown>) => FakeReply;
type RpcHandler = RpcFn | Record<string, unknown> | unknown[] | string | number | boolean | null;
export type FakeSupabase = {
  userId: string;
  role?: string;
  rpc?: Record<string, RpcHandler>;
  tables?: Record<string, unknown>;
};

export async function withFakeSupabase(fake: FakeSupabase, run: (calls: FakeCall[]) => Promise<void>) {
  const calls: FakeCall[] = [];
  const originalFetch = globalThis.fetch;
  const saved = { url: process.env.NEXT_PUBLIC_SUPABASE_URL, anon: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY, service: process.env.SUPABASE_SERVICE_ROLE_KEY };
  process.env.NEXT_PUBLIC_SUPABASE_URL = 'http://supabase.test';
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = 'anon-test-key';
  process.env.SUPABASE_SERVICE_ROLE_KEY = 'service-test-key';
  globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = new URL(typeof input === 'string' ? input : input instanceof URL ? input.href : input.url);
    let body: unknown = null;
    if (typeof init?.body === 'string' && init.body) { try { body = JSON.parse(init.body); } catch { body = init.body; } }
    calls.push({ method: init?.method ?? 'GET', path: url.pathname, body });
    if (url.pathname === '/auth/v1/user') {
      return Response.json({ id: fake.userId, aud: 'authenticated', role: 'authenticated', email: 'qa@fake.invalid', app_metadata: {}, user_metadata: {}, created_at: '2026-11-19T00:00:00Z' });
    }
    if (url.pathname === '/rest/v1/profiles') return Response.json({ role: fake.role ?? 'learner', status: 'active' });
    if (url.pathname.startsWith('/rest/v1/rpc/')) {
      const name = url.pathname.slice('/rest/v1/rpc/'.length);
      if (fake.rpc && name in fake.rpc) {
        const handler = fake.rpc[name];
        if (typeof handler === 'function') {
          const reply = handler((body ?? {}) as Record<string, unknown>);
          return Response.json(reply.body, { status: reply.status });
        }
        return Response.json(handler);
      }
      return Response.json({ code: 'PGRST202', message: `Could not find the function public.${name} in the schema cache` }, { status: 404 });
    }
    const table = url.pathname.replace(/^\/rest\/v1\//, '');
    if (fake.tables && table in fake.tables) return Response.json(fake.tables[table]);
    return Response.json({ message: `unexpected request ${url.pathname}` }, { status: 500 });
  }) as typeof fetch;
  try {
    await run(calls);
  } finally {
    globalThis.fetch = originalFetch;
    for (const [key, value] of [['NEXT_PUBLIC_SUPABASE_URL', saved.url], ['NEXT_PUBLIC_SUPABASE_ANON_KEY', saved.anon], ['SUPABASE_SERVICE_ROLE_KEY', saved.service]] as const) {
      if (value === undefined) delete process.env[key]; else process.env[key] = value;
    }
  }
}

/** A request authenticated with a bearer token (the mobile/API path of activityActor). */
export function bearerRequest(path: string, init: RequestInit = {}) {
  return new Request(`http://localhost:3008${path}`, {
    ...init,
    headers: { authorization: 'Bearer test-token', 'content-type': 'application/json', ...(init.headers ?? {}) },
  });
}
