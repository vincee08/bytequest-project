import { createServerClient } from "@supabase/ssr";
import { isAuthRetryableFetchError } from "@supabase/supabase-js";
import { NextResponse, type NextRequest } from "next/server";
import type { Database } from "@/types/database.generated";

const PUBLIC_PATHS = new Set(["/login", "/signup", "/auth/recover"]);
const ADMIN_PREFIXES = ["/admin", "/users", "/logs", "/settings", "/tesda-sources"];
const INSTRUCTOR_PREFIXES = [
  "/instructor",
  "/classes",
  "/attempts",
  "/modules",
  "/progress",
  "/analytics",
  "/reports",
  "/resources",
  "/quizzes",
  "/concerns",
  "/leaderboard",
  "/assessment-criteria",
  "/competencies",
  "/scenarios",
];

// Vercel ends middleware that has not answered within 25 s (504
// MIDDLEWARE_INVOCATION_TIMEOUT), and supabase-js keeps retrying a failed token
// refresh for up to 30 s, so the session check gets its own deadline.
export const SESSION_CHECK_DEADLINE_MS = 8_000;
export const SESSION_TIMEOUT_PATH = "/login?error=session_timeout";

class SessionCheckUnavailable extends Error {}

type GateSupabase = ReturnType<typeof createServerClient<Database>>;

function matchesPrefix(pathname: string, prefixes: readonly string[]) {
  return prefixes.some(
    (prefix) => pathname === prefix || pathname.startsWith(`${prefix}/`),
  );
}

function redirectWithCookies(
  request: NextRequest,
  response: NextResponse,
  pathname: string,
) {
  const target = request.nextUrl.clone();
  const [path, query = ""] = pathname.split("?");
  target.pathname = path;
  target.search = query ? `?${query}` : "";
  const redirectResponse = NextResponse.redirect(target);
  response.cookies.getAll().forEach((cookie) => {
    redirectResponse.cookies.set(cookie);
  });
  return redirectResponse;
}

function hasSessionCookie(request: NextRequest) {
  return request.cookies
    .getAll()
    .some(({ name }) => name.startsWith("sb-") && name.includes("-auth-token"));
}

function fetchBefore(deadline: number): typeof fetch {
  return (input, init) => {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), Math.max(0, deadline - Date.now()));
    const upstream = init?.signal;
    if (upstream?.aborted) controller.abort();
    else upstream?.addEventListener("abort", () => controller.abort(), { once: true });
    return fetch(input, { ...init, signal: controller.signal }).finally(() => clearTimeout(timer));
  };
}

function beforeDeadline<T>(work: Promise<T>, deadline: number): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const expiry = new Promise<never>((_, reject) => {
    timer = setTimeout(
      () => reject(new SessionCheckUnavailable()),
      Math.max(0, deadline - Date.now()),
    );
  });
  return Promise.race([work, expiry]).finally(() => clearTimeout(timer));
}

async function loadSession(supabase: GateSupabase) {
  const {
    data: { user },
    error,
  } = await supabase.auth.getUser();
  // A network failure is not a signed-out user: never answer "no account".
  if (isAuthRetryableFetchError(error)) throw new SessionCheckUnavailable();
  if (!user) return { user: null, profile: null };

  const { data: profile, error: profileError } = await supabase
    .from("profiles")
    .select("role,status")
    .eq("user_id", user.id)
    .maybeSingle();
  if (profileError) throw new SessionCheckUnavailable();
  return { user, profile };
}

export async function gateRequest(
  request: NextRequest,
  { deadlineMs = SESSION_CHECK_DEADLINE_MS }: { deadlineMs?: number } = {},
) {
  let response = NextResponse.next({ request });
  const pathname = request.nextUrl.pathname;
  // Recovery must also work while another account is signed in.
  if (pathname === "/auth/recover") return response;

  // API routes own their authentication and return machine-readable errors.
  // Redirecting them here turns 401/403 responses into HTML login pages.
  if (pathname === "/api" || pathname.startsWith("/api/")) {
    return response;
  }

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key =
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ??
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!url || !key) {
    return redirectWithCookies(request, response, "/login?error=configuration");
  }

  // Signed-out visitors (shared links included) need no Supabase round trip.
  if (!hasSessionCookie(request)) {
    if (PUBLIC_PATHS.has(pathname)) return response;
    return redirectWithCookies(request, response, "/login");
  }

  const deadline = Date.now() + deadlineMs;
  const supabase = createServerClient<Database>(url, key, {
    cookies: {
      getAll: () => request.cookies.getAll(),
      setAll(cookiesToSet) {
        cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
        response = NextResponse.next({ request });
        cookiesToSet.forEach(({ name, value, options }) => {
          response.cookies.set(name, value, options);
        });
      },
    },
    global: { fetch: fetchBefore(deadline) },
  });

  let session: Awaited<ReturnType<typeof loadSession>>;
  try {
    session = await beforeDeadline(loadSession(supabase), deadline);
  } catch (error) {
    if (!(error instanceof SessionCheckUnavailable)) throw error;
    if (PUBLIC_PATHS.has(pathname)) return response;
    return redirectWithCookies(request, response, SESSION_TIMEOUT_PATH);
  }

  const { user, profile } = session;
  if (!user) {
    if (PUBLIC_PATHS.has(pathname)) return response;
    return redirectWithCookies(request, response, "/login");
  }

  if (!profile || profile.status !== "active") {
    if (pathname === "/login") return response;
    return redirectWithCookies(request, response, "/login?error=account_inactive");
  }

  if (profile.role !== "admin" && profile.role !== "instructor") {
    if (pathname === "/login") return response;
    return redirectWithCookies(request, response, "/login?error=staff_only");
  }

  const roleDashboard =
    profile.role === "admin" ? "/admin/dashboard" : "/instructor/dashboard";

  if (PUBLIC_PATHS.has(pathname) || pathname === "/" || pathname === "/dashboard") {
    return redirectWithCookies(request, response, roleDashboard);
  }

  if (profile.role === "admin" && matchesPrefix(pathname, INSTRUCTOR_PREFIXES)) {
    return redirectWithCookies(request, response, "/admin/dashboard");
  }

  if (profile.role === "instructor" && matchesPrefix(pathname, ADMIN_PREFIXES)) {
    return redirectWithCookies(request, response, "/instructor/dashboard");
  }

  return response;
}
