import "server-only";
import { createHash } from "node:crypto";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database, Json } from "@/types/database.generated";
import {
  isAllowedLearningResourceMime,
  matchesResourceContent,
} from "@/lib/resources/policy";

type UploadDatabase = Omit<Database, "public"> & {
  public: Omit<Database["public"], "Functions"> & {
    Functions: Database["public"]["Functions"] & {
      manage_file_upload: {
        Args: { p_actor: string | null; p_action: string; p_spec: Json };
        Returns: Json;
      };
    };
  };
};
export type UploadIntent =
  Database["public"]["Tables"]["file_upload_intents"]["Row"] & {
    spec: { size: number; mime: string; sha256: string };
  };
export async function uploadAction(
  client: { rpc: unknown },
  actor: string | null,
  action: string,
  spec: Json,
) {
  return (client as unknown as SupabaseClient<UploadDatabase>).rpc(
    "manage_file_upload",
    { p_actor: actor, p_action: action, p_spec: spec },
  );
}
export function uploadIdentity(spec: object) {
  const digest = createHash("sha256")
    .update(JSON.stringify(spec))
    .digest("hex");
  return `${digest.slice(0, 8)}-${digest.slice(8, 12)}-5${digest.slice(13, 16)}-a${digest.slice(17, 20)}-${digest.slice(20, 32)}`;
}
export async function smallJson(request: Request) {
  const reader = request.body?.getReader();
  if (!reader) throw Error("BODY_REQUIRED");
  const parts: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > 8192) throw Error("BODY_TOO_LARGE");
      parts.push(value);
    }
  } finally {
    await reader.cancel().catch(() => {});
  }
  return JSON.parse(Buffer.concat(parts).toString("utf8")) as unknown;
}
export class InvalidUploadedFile extends Error {}
/** Storage bytes are fetched internally, bounded and never returned in a function response. */
export async function verifyUploadedFile(
  client: Pick<SupabaseClient<Database>, "storage">,
  intent: UploadIntent,
) {
  const signed = await client.storage
    .from(intent.bucket)
    .createSignedUrl(intent.object_path, 60);
  if (signed.error) throw Error("STORAGE_NOT_READY");
  const download = new URL(signed.data.signedUrl);
  if (download.origin !== new URL(process.env.NEXT_PUBLIC_SUPABASE_URL!).origin)
    throw Error("STORAGE_ORIGIN_INVALID");
  const response = await fetch(download, {
    cache: "no-store",
    redirect: "error",
    signal: AbortSignal.timeout(90_000),
  });
  if (!response.ok || !response.body) throw Error("STORAGE_NOT_READY");
  const reader = response.body.getReader();
  const hash = createHash("sha256");
  const text =
    intent.spec.mime === "text/plain"
      ? new TextDecoder("utf-8", { fatal: true })
      : null;
  let length = 0;
  let prefix = Buffer.alloc(0);
  try {
    if (
      response.headers.get("content-type")?.split(";")[0] !== intent.spec.mime
    )
      throw new InvalidUploadedFile();
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      length += value.length;
      if (length > intent.spec.size) throw new InvalidUploadedFile();
      hash.update(value);
      if (prefix.length < 16)
        prefix = Buffer.concat([
          prefix,
          Buffer.from(value).subarray(0, 16 - prefix.length),
        ]);
      if (text) {
        try {
          if (
            /[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(
              text.decode(value, { stream: true }),
            )
          )
            throw new InvalidUploadedFile();
        } catch {
          throw new InvalidUploadedFile();
        }
      }
    }
    if (text) {
      try {
        text.decode();
      } catch {
        throw new InvalidUploadedFile();
      }
    }
    if (
      length !== intent.spec.size ||
      hash.digest("hex") !== intent.spec.sha256 ||
      (!text &&
        (!isAllowedLearningResourceMime(intent.spec.mime) ||
          !matchesResourceContent(intent.spec.mime, prefix)))
    )
      throw new InvalidUploadedFile();
  } finally {
    await reader.cancel().catch(() => {});
  }
}
