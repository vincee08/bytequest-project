import { getServerProfile } from "@/lib/auth/server";
import { buildRosterTemplate } from "@/lib/roster/parse";
import { rosterFailure, rosterNoStore } from "@/lib/roster/server";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/** Downloads the roster template (.xlsx) for staff. */
export async function GET() {
  const actor = await getServerProfile();
  if (!actor) return rosterFailure("Sign in to download the roster template.", 401);
  if (!["instructor", "admin"].includes(actor.role) || actor.status !== "active") {
    return rosterFailure("Active staff access is required to download the roster template.", 403);
  }
  try {
    const workbook = buildRosterTemplate();
    return new Response(new Uint8Array(workbook), {
      status: 200,
      headers: {
        ...rosterNoStore,
        "Content-Type": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "Content-Disposition": 'attachment; filename="bytequest-roster-template.xlsx"',
        "X-Content-Type-Options": "nosniff",
      },
    });
  } catch {
    return rosterFailure("The roster template could not be generated. Try again shortly.", 503);
  }
}
