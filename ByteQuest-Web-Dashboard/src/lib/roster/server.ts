import "server-only";

import { createHash } from "node:crypto";
import { NextResponse } from "next/server";
import type { SupabaseClient } from "@supabase/supabase-js";
import { z } from "zod";
import { getServerProfile } from "@/lib/auth/server";
import { createAdminSupabaseClient } from "@/lib/supabase/admin";
import type { Database, Json } from "@/types/database.generated";
import { parseRosterFile, type RosterParseSuccess } from "./parse";
import { ROSTER_MAX_BYTES, type RosterBatchRow, type RosterEntryRow, type RosterFileInfo } from "./types";

type Table<T> = { Row: T; Insert: Partial<T>; Update: Partial<T>; Relationships: [] };
type RosterFunctions = {
  preview_class_roster: { Args: { p_actor: string; p_class_id: string; p_rows: Json }; Returns: Json };
  import_class_roster: { Args: { p_actor: string; p_class_id: string; p_rows: Json; p_file_name: string }; Returns: Json };
  cancel_class_roster_entry: { Args: { p_actor: string; p_entry_id: string }; Returns: Json };
};
export type RosterDatabase = Omit<Database, "public"> & {
  public: Omit<Database["public"], "Tables" | "Functions"> & {
    Tables: Database["public"]["Tables"] & {
      class_roster_entries: Table<RosterEntryRow>;
      roster_import_batches: Table<RosterBatchRow>;
    };
    Functions: Database["public"]["Functions"] & RosterFunctions;
  };
};

/** Types a cookie (RLS) client for the roster tables. */
export function rosterClient(client: SupabaseClient<Database>) {
  return client as unknown as SupabaseClient<RosterDatabase>;
}

/** Service client for the service-only roster functions (called after the route checks the actor). */
export function rosterService(timeoutMs = 30_000) {
  return rosterClient(createAdminSupabaseClient(timeoutMs));
}

export const rosterNoStore = { "Cache-Control": "private, no-store" };

export function rosterFailure(message: string, status: number, code?: string) {
  return NextResponse.json(code ? { error: message, code } : { error: message }, { status, headers: rosterNoStore });
}

/** Active instructor session plus a well-formed class id. Ownership is rechecked in SQL. */
export async function rosterInstructor(classId: string) {
  const actor = await getServerProfile();
  if (!actor) return { error: rosterFailure("Sign in to import a class roster.", 401) } as const;
  if (actor.role !== "instructor" || actor.status !== "active") {
    return { error: rosterFailure("Active instructor access is required to import a class roster.", 403) } as const;
  }
  if (!z.string().uuid().safeParse(classId).success) return { error: rosterFailure("Invalid class identifier.", 400) } as const;
  return { actor } as const;
}

type UploadSuccess = { form: FormData; parsed: RosterParseSuccess; info: RosterFileInfo };

/** Reads one multipart `file` field, enforces the size limit and parses it on the server. */
export async function readRosterUpload(request: Request): Promise<UploadSuccess | { error: NextResponse }> {
  const declared = Number(request.headers.get("content-length") ?? 0);
  if (declared > ROSTER_MAX_BYTES + 64 * 1024) {
    return { error: rosterFailure("The file is larger than 2 MB. Remove unused sheets or split the roster.", 413, "FILE_TOO_LARGE") };
  }
  let form: FormData;
  try {
    form = await request.formData();
  } catch {
    return { error: rosterFailure("Choose an Excel roster file (.xlsx or .xls) to upload.", 400) };
  }
  const file = form.get("file");
  if (!(file instanceof File)) return { error: rosterFailure("Choose an Excel roster file (.xlsx or .xls) to upload.", 400) };
  if (file.size > ROSTER_MAX_BYTES) {
    return { error: rosterFailure("The file is larger than 2 MB. Remove unused sheets or split the roster.", 413, "FILE_TOO_LARGE") };
  }
  const bytes = new Uint8Array(await file.arrayBuffer());
  const parsed = parseRosterFile({ name: file.name, size: file.size, bytes });
  if (!parsed.ok) return { error: rosterFailure(parsed.message, parsed.code === "FILE_TOO_LARGE" ? 413 : 422, parsed.code) };
  return {
    form,
    parsed,
    info: {
      name: file.name.slice(0, 255),
      size: file.size,
      sha256: createHash("sha256").update(bytes).digest("hex"),
      format: parsed.format,
      sheetName: parsed.sheetName,
      headerRow: parsed.headerRow,
      ignoredColumns: parsed.ignoredColumns,
      blankRowsSkipped: parsed.blankRowsSkipped,
      exampleRowsSkipped: parsed.exampleRowsSkipped,
    },
  };
}

/** Maps database errors to safe, specific messages (never raw SQL text). */
export function rosterRpcFailure(error: { code?: string; message?: string }) {
  const message = error.message ?? "";
  if (error.code === "42501") return rosterFailure("You can import rosters only into your own active class.", 403);
  if (message.includes("ROSTER_TOO_MANY_ROWS")) {
    return rosterFailure("The roster has more than 1,000 learner rows. Split it into smaller files and import each one.", 422, "TOO_MANY_ROWS");
  }
  if (message.includes("ROSTER_EMPTY") || message.includes("ROSTER_ROWS_INVALID")) {
    return rosterFailure("The roster has no learner rows to import.", 422, "NO_DATA_ROWS");
  }
  if (error.code === "55000") return rosterFailure("This roster entry is no longer pending. Refresh the class to see its status.", 409);
  if (error.code === "23505") return rosterFailure("The class changed while importing. Nothing was imported; preview the file again.", 409);
  return rosterFailure("The roster could not be processed. Nothing was imported; try again shortly.", 503);
}
