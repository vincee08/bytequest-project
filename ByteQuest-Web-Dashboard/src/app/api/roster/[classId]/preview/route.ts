import { NextResponse } from "next/server";
import { activityWriteOriginAllowed } from "@/lib/activities/server";
import { readRosterUpload, rosterFailure, rosterInstructor, rosterNoStore, rosterRpcFailure, rosterService } from "@/lib/roster/server";
import type { RosterOutcome, RosterPreviewResponse } from "@/lib/roster/types";
import type { Json } from "@/types/database.generated";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/** Parses the uploaded roster on the server and classifies every row. Changes nothing. */
export async function POST(request: Request, { params }: { params: Promise<{ classId: string }> }) {
  if (!activityWriteOriginAllowed(request)) return rosterFailure("Origin not allowed.", 403);
  const { classId } = await params;
  const scope = await rosterInstructor(classId);
  if ("error" in scope) return scope.error;
  try {
    const upload = await readRosterUpload(request);
    if ("error" in upload) return upload.error;
    const { data, error } = await rosterService().rpc("preview_class_roster", {
      p_actor: scope.actor.userId,
      p_class_id: classId,
      p_rows: upload.parsed.rows as unknown as Json,
    });
    if (error) return rosterRpcFailure(error);
    const body: RosterPreviewResponse = { file: upload.info, preview: data as unknown as RosterOutcome };
    return NextResponse.json(body, { headers: rosterNoStore });
  } catch {
    return rosterFailure("The roster preview could not be completed. Nothing was imported; try again shortly.", 503);
  }
}
