import { NextResponse } from "next/server";
import { z } from "zod";
import { activityWriteOriginAllowed } from "@/lib/activities/server";
import { rosterFailure, rosterInstructor, rosterNoStore, rosterRpcFailure, rosterService } from "@/lib/roster/server";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const schema = z.object({ action: z.literal("cancel"), entry_id: z.string().uuid() }).strict();

/** Cancels a pending roster entry of the instructor's own class so it can never be claimed. */
export async function POST(request: Request, { params }: { params: Promise<{ classId: string }> }) {
  if (!activityWriteOriginAllowed(request)) return rosterFailure("Origin not allowed.", 403);
  const { classId } = await params;
  const scope = await rosterInstructor(classId);
  if ("error" in scope) return scope.error;
  let input: unknown;
  try { input = await request.json(); } catch { return rosterFailure("Choose a pending roster entry.", 400); }
  const parsed = schema.safeParse(input);
  if (!parsed.success) return rosterFailure("Choose a pending roster entry.", 400);
  try {
    const service = rosterService(15_000);
    const { data: entry, error: lookupError } = await service
      .from("class_roster_entries")
      .select("id,class_id")
      .eq("id", parsed.data.entry_id)
      .maybeSingle();
    if (lookupError) return rosterFailure("The roster entry could not be loaded. Try again.", 503);
    if (!entry || entry.class_id !== classId) return rosterFailure("Roster entry not found in this class.", 404);
    const { data, error } = await service.rpc("cancel_class_roster_entry", { p_actor: scope.actor.userId, p_entry_id: entry.id });
    if (error) return rosterRpcFailure(error);
    return NextResponse.json({ entry: data }, { headers: rosterNoStore });
  } catch {
    return rosterFailure("The roster entry could not be cancelled. Refresh the class before retrying.", 503);
  }
}
