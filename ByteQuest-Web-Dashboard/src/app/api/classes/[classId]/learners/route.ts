import { NextResponse } from "next/server";
import { z } from "zod";
import { getServerProfile } from "@/lib/auth/server";
import { createServerSupabaseClient } from "@/lib/supabase/server";
import { createAdminSupabaseClient } from "@/lib/supabase/admin";
import { enrollmentFailure, enrollLearnerSchema, learnerSearchFilter, learnerSearchSchema, LEARNER_SEARCH_PAGE_SIZE, learnerEnrollmentState } from "@/lib/learners/enrollment";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
const noStore = { "Cache-Control": "private, no-store" };
function failure(message: string, status: number, code?: string) { return NextResponse.json(code ? { error: message, code } : { error: message }, { status, headers: noStore }); }

async function authorize(classId: string) {
  const actor = await getServerProfile();
  if (!actor) return { error: failure("Sign in to manage class enrollment.", 401) };
  if (actor.role !== "instructor" || actor.status !== "active") return { error: failure("Active instructor access is required.", 403) };
  if (!z.string().uuid().safeParse(classId).success) return { error: failure("Invalid class identifier.", 400) };
  const client = await createServerSupabaseClient();
  const { data: owned, error } = await client.from("classes").select("id").eq("id", classId).eq("instructor_id", actor.userId).eq("status", "active").maybeSingle();
  if (error) return { error: failure("Class access could not be verified. Try again.", 503) };
  if (!owned) return { error: failure("You can manage enrollment only in your own active class.", 403) };
  return { client };
}

export async function GET(request: Request, { params }: { params: Promise<{ classId: string }> }) {
  const { classId } = await params;
  const scope = await authorize(classId);
  if (scope.error) return scope.error;
  const input = learnerSearchSchema.safeParse(Object.fromEntries(new URL(request.url).searchParams));
  if (!input.success) return failure(input.error.issues[0]?.message ?? "Invalid learner search.", 400);
  const { q, page } = input.data;
  try {
    // Same authoritative profiles directory as the Admin Learners Page. The
    // owner explicitly authorized discovery of all active registered learners.
    // Service access is READ ONLY here, after session/role/owned-class checks;
    // no Auth user API, profile metadata, other-class data or RLS change.
    const directory = createAdminSupabaseClient(10_000);
    const { data, error } = await directory.from("profiles").select("user_id,full_name,email")
      .eq("role", "learner").eq("status", "active").or(learnerSearchFilter(q))
      .order("full_name").order("user_id").range(page * LEARNER_SEARCH_PAGE_SIZE, (page + 1) * LEARNER_SEARCH_PAGE_SIZE);
    if (error || !data) return failure("Learner search is unavailable. Try again shortly.", 503);
    const rows = data.slice(0, LEARNER_SEARCH_PAGE_SIZE);
    const ids = rows.map((row) => row.user_id);
    const { data: memberships, error: membershipError } = ids.length
      ? await scope.client!.from("class_memberships").select("learner_id,status").eq("class_id", classId).in("learner_id", ids)
      : { data: [], error: null };
    if (membershipError) return failure("Class enrollment status could not be loaded. Try again.", 503);
    return NextResponse.json({
      learners: rows.map((row) => ({ id: row.user_id, fullName: row.full_name, email: row.email,
        enrollment: learnerEnrollmentState((memberships ?? []).filter((membership) => membership.learner_id === row.user_id).map((membership) => membership.status)),
      })),
      hasMore: data.length > LEARNER_SEARCH_PAGE_SIZE && page < 100,
    }, { headers: noStore });
  } catch { return failure("Learner search is unavailable. Try again shortly.", 503); }
}

export async function POST(request: Request, { params }: { params: Promise<{ classId: string }> }) {
  const { classId } = await params;
  const scope = await authorize(classId);
  if (scope.error) return scope.error;
  let body: unknown;
  try { body = await request.json(); } catch { return failure("Select a registered learner.", 400); }
  const input = enrollLearnerSchema.safeParse(body);
  if (!input.success) return failure("Select a registered learner using the search results.", 400);
  try {
    // The authenticated RPC rechecks learner eligibility and class ownership.
    // Its partial unique index resolves same-class races; the one-active-class
    // trigger refuses a learner who is active in another class.
    // Removed memberships are retained; re-enrollment inserts a new record.
    const { data, error } = await scope.client!.rpc("enroll_learner", { p_class_id: classId, p_learner_id: input.data.learnerId });
    if (error) { const mapped = enrollmentFailure(error.code, error.message); return failure(mapped.message, mapped.status, mapped.code); }
    return NextResponse.json({ membershipId: data.id, learnerId: data.learner_id, status: data.status }, { status: 201, headers: noStore });
  } catch { return failure("Enrollment could not be confirmed. Refresh the class before retrying.", 503); }
}
