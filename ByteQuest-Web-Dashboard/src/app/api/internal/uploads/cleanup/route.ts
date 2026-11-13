import { timingSafeEqual } from "node:crypto";
import { NextResponse } from "next/server";
import { createAdminSupabaseClient } from "@/lib/supabase/admin";
import { uploadAction, type UploadIntent } from "@/lib/uploads/server";
export const runtime = "nodejs";
export const maxDuration = 240;
export async function GET(request: Request) {
  const expected = process.env.CRON_SECRET;
  const supplied = request.headers.get("authorization") ?? "";
  const token = Buffer.from(`Bearer ${expected ?? ""}`),
    actual = Buffer.from(supplied);
  if (
    !expected ||
    actual.length !== token.length ||
    !timingSafeEqual(token, actual)
  )
    return NextResponse.json({ error: "Not authorized." }, { status: 401 });
  const client = createAdminSupabaseClient(30_000);
  let cleaned = 0;
  try {
    const batch = await uploadAction(client, null, "claim_cleanup", {});
    if (batch.error) throw Error("CLEANUP_UNAVAILABLE");
    const started = Date.now();
    for (const intent of batch.data as unknown as UploadIntent[]) {
      if (Date.now() - started > 170_000) break; // Unprocessed leases become eligible on the next run.
      const removed = await client.storage
        .from(intent.bucket)
        .remove([intent.object_path]);
      if (removed.error) continue;
      const done = await uploadAction(client, null, "finish_cleanup", {
        id: intent.id,
        lease_id: intent.lease_id,
      });
      if (!done.error) cleaned++;
    }
    return NextResponse.json(
      { cleaned },
      { headers: { "Cache-Control": "no-store" } },
    );
  } catch {
    return NextResponse.json(
      { error: "Cleanup could not finish; expired leases will retry safely." },
      { status: 503 },
    );
  }
}
