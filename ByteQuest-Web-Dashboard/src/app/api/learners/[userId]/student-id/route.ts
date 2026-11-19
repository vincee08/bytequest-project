import { NextResponse } from "next/server";
import type { SupabaseClient } from "@supabase/supabase-js";
import { z } from "zod";
import { activityWriteOriginAllowed } from "@/lib/activities/server";
import { getServerProfile } from "@/lib/auth/server";
import { studentIdFailure, studentIdInputSchema } from "@/lib/learners/student-id";
import { createAdminSupabaseClient } from "@/lib/supabase/admin";
import type { Database, Json } from "@/types/database.generated";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

type StudentIdDatabase = Omit<Database, "public"> & {
  public: Omit<Database["public"], "Functions"> & {
    Functions: Database["public"]["Functions"] & {
      set_learner_student_id: { Args: { p_actor: string; p_learner_id: string; p_student_id: string | null }; Returns: Json };
    };
  };
};

const noStore = { "Cache-Control": "private, no-store" };
const reply = (body: unknown, status = 200) => NextResponse.json(body, { status, headers: noStore });

/** Admin sets (staff-managed) or clears a learner's student ID. Audited in the database. */
export async function POST(request: Request, { params }: { params: Promise<{ userId: string }> }) {
  if (!activityWriteOriginAllowed(request)) return reply({ error: "Origin not allowed." }, 403);
  const actor = await getServerProfile();
  if (!actor) return reply({ error: "Sign in to manage student IDs." }, 401);
  if (actor.role !== "admin" || actor.status !== "active") return reply({ error: "Only an active administrator can change student IDs." }, 403);
  const { userId } = await params;
  if (!z.string().uuid().safeParse(userId).success) return reply({ error: "Invalid learner identifier." }, 400);
  let body: unknown;
  try { body = await request.json(); } catch { return reply({ error: "Enter a student ID or clear it." }, 400); }
  const input = studentIdInputSchema.safeParse(body);
  if (!input.success) return reply({ error: input.error.issues[0]?.message ?? "Enter a student ID of at most 64 characters." }, 422);
  try {
    const service = createAdminSupabaseClient(15_000) as unknown as SupabaseClient<StudentIdDatabase>;
    const { data, error } = await service.rpc("set_learner_student_id", { p_actor: actor.userId, p_learner_id: userId, p_student_id: input.data.student_id as string }); // NULL clears the ID; generated RPC types cannot express nullable parameters.
    if (error) { const failure = studentIdFailure(error); return reply({ error: failure.message }, failure.status); }
    return reply({ profile: data });
  } catch {
    return reply({ error: "The student ID could not be saved. Refresh the account before retrying." }, 503);
  }
}
