import { NextResponse } from "next/server";
import { cookies } from "next/headers";
import { createClient } from "@supabase/supabase-js";
import { z } from "zod";
import { createServerSupabaseClient } from "@/lib/supabase/server";
import {
  RECOVERY_COOKIE,
  recoveryProof,
  validRecoveryProof,
  sessionId,
} from "@/lib/auth/recovery";
import { smallJson } from "@/lib/uploads/server";
import {
  activityWriteOriginAllowed,
  activityHeaders,
} from "@/lib/activities/server";
export const runtime = "nodejs";
const cookieOptions = {
  httpOnly: true,
  secure: process.env.NODE_ENV === "production",
  sameSite: "strict" as const,
  path: "/api/auth/recovery",
  maxAge: 900,
};
async function recoverySession() {
  const client = await createServerSupabaseClient();
  const {
    data: { user },
    error,
  } = await client.auth.getUser();
  if (error || !user) return null;
  const {
    data: { session },
  } = await client.auth.getSession();
  if (!session) return null;
  const jar = await cookies();
  if (
    !validRecoveryProof(
      jar.get(RECOVERY_COOKIE)?.value,
      user.id,
      sessionId(session.access_token),
    )
  )
    return null;
  return { client, user };
}
export async function OPTIONS(request: Request) {
  return new NextResponse(null, {
    status: 204,
    headers: activityHeaders(request),
  });
}
export async function GET() {
  try {
    return NextResponse.json(
      { ready: !!(await recoverySession()) },
      { headers: { "Cache-Control": "private, no-store" } },
    );
  } catch {
    return NextResponse.json({ ready: false }, { status: 503 });
  }
}
export async function POST(request: Request) {
  const reply = (body: unknown, status = 200) =>
    NextResponse.json(body, { status, headers: activityHeaders(request) });
  try {
    const body = z
      .discriminatedUnion("action", [
        z
          .object({
            action: z.literal("request"),
            email: z.string().trim().email().max(320),
          })
          .strict(),
        z
          .object({
            action: z.literal("verify"),
            token_hash: z.string().min(20).max(256),
          })
          .strict(),
        z
          .object({
            action: z.literal("update"),
            password: z.string().min(12).max(128),
          })
          .strict(),
      ])
      .safeParse(await smallJson(request));
    if (!body.success)
      return reply(
        {
          error:
            "Check the email address or use a password with at least 12 characters.",
        },
        400,
      );
    const localMobileRequest =
      body.data.action === "request" &&
      process.env.NEXT_PUBLIC_SUPABASE_URL === "http://127.0.0.1:58921" &&
      ["http://127.0.0.1:3009", "http://localhost:3009"].includes(
        request.headers.get("origin") ?? "",
      );
    if (!activityWriteOriginAllowed(request) && !localMobileRequest)
      return reply({ error: "Origin not allowed." }, 403);
    if (body.data.action === "request") {
      const client = createClient(
        process.env.NEXT_PUBLIC_SUPABASE_URL!,
        process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ??
          process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
        {
          auth: {
            persistSession: false,
            autoRefreshToken: false,
            flowType: "implicit",
          },
        },
      );
      // The hosted email template places TokenHash in a fragment, never a URL query/log.
      const origin =
        process.env.BYTEQUEST_SITE_URL ?? new URL(request.url).origin;
      const result = await client.auth.resetPasswordForEmail(body.data.email, {
        redirectTo: origin + "/auth/recover",
      });
      if (result.error)
        return reply(
          {
            error:
              result.error.status === 429
                ? "Wait a minute before requesting another link."
                : "Recovery email could not be sent. Try again or contact the administrator.",
          },
          result.error.status === 429 ? 429 : 503,
        );
      return reply({
        message: "If an account exists, recovery instructions have been sent.",
      });
    }
    if (body.data.action === "verify") {
      const client = await createServerSupabaseClient();
      const verified = await client.auth.verifyOtp({
        token_hash: body.data.token_hash,
        type: "recovery",
      });
      if (verified.error || !verified.data.user || !verified.data.session)
        return reply(
          {
            error:
              "This recovery link has expired or was already used. Request a new link.",
          },
          400,
        );
      (await cookies()).set(
        RECOVERY_COOKIE,
        recoveryProof(
          verified.data.user.id,
          sessionId(verified.data.session.access_token),
        ),
        cookieOptions,
      );
      return reply({ ready: true });
    }
    const recovered = await recoverySession();
    if (!recovered)
      return reply(
        { error: "The recovery session has expired. Request a new link." },
        401,
      );
    const result = await recovered.client.auth.updateUser({
      password: body.data.password,
    });
    if (result.error)
      return reply(
        {
          error:
            "The password could not be updated. Use a different strong password and retry.",
        },
        400,
      );
    await recovered.client.auth.signOut({ scope: "global" });
    (await cookies()).set(RECOVERY_COOKIE, "", { ...cookieOptions, maxAge: 0 });
    return reply({ updated: true });
  } catch {
    return reply(
      {
        error:
          "Recovery could not be completed. Request a new link and try again.",
      },
      503,
    );
  }
}
