import { NextResponse } from "next/server";
import { activityWriteOriginAllowed } from "@/lib/activities/server";
import { readRosterUpload, rosterFailure, rosterInstructor, rosterNoStore, rosterRpcFailure, rosterService } from "@/lib/roster/server";
import type { RosterImportResponse, RosterOutcome } from "@/lib/roster/types";
import type { Json } from "@/types/database.generated";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/**
 * Confirms a previewed roster. The same file is uploaded again and must match
 * the previewed SHA-256, so the import applies exactly what was reviewed. The
 * database re-classifies every row in one transaction (idempotent).
 */
export async function POST(request: Request, { params }: { params: Promise<{ classId: string }> }) {
  if (!activityWriteOriginAllowed(request)) return rosterFailure("Origin not allowed.", 403);
  const { classId } = await params;
  const scope = await rosterInstructor(classId);
  if ("error" in scope) return scope.error;
  try {
    const upload = await readRosterUpload(request);
    if ("error" in upload) return upload.error;
    const expected = String(upload.form.get("expected_sha256") ?? "").trim().toLowerCase();
    if (!/^[0-9a-f]{64}$/.test(expected)) return rosterFailure("Preview the roster before confirming the import.", 400);
    if (expected !== upload.info.sha256) {
      return rosterFailure("The file changed after the preview. Preview it again before confirming.", 409, "FILE_CHANGED");
    }
    const { data, error } = await rosterService().rpc("import_class_roster", {
      p_actor: scope.actor.userId,
      p_class_id: classId,
      p_rows: upload.parsed.rows as unknown as Json,
      p_file_name: upload.info.name,
    });
    if (error) return rosterRpcFailure(error);
    const body: RosterImportResponse = { file: upload.info, result: data as unknown as RosterOutcome };
    return NextResponse.json(body, { headers: rosterNoStore });
  } catch {
    return rosterFailure("The import could not be confirmed. Refresh the class to check its learners before retrying.", 503);
  }
}
