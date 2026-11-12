import "server-only";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/types/database.generated";
import { LEARNING_RESOURCE_BUCKET } from "@/lib/resources/policy";
import { MAX_AI_PDF_BYTES } from "@/lib/resources/pdf";

export class ResourceSourceError extends Error {
  constructor(
    public readonly publicMessage: string,
    public readonly status = 422,
  ) {
    super("RESOURCE_SOURCE_UNAVAILABLE");
  }
}
export async function authorizeResourceSource(
  client: SupabaseClient<Database>,
  instructorId: string,
  classId: string,
  resourceId: string,
) {
  const { data: owned } = await client
    .from("classes")
    .select("id")
    .eq("id", classId)
    .eq("instructor_id", instructorId)
    .eq("status", "active")
    .maybeSingle();
  if (!owned)
    throw new ResourceSourceError(
      "Choose a resource from your own active class.",
      403,
    );
  const { data: resource } = await client
    .from("learning_resources")
    .select(
      "id,class_id,title,mime_type,size_bytes,storage_bucket,storage_path",
    )
    .eq("id", resourceId)
    .eq("class_id", classId)
    .eq("status", "active")
    .maybeSingle();
  if (!resource)
    throw new ResourceSourceError(
      "This resource is missing, archived, or outside the selected class.",
      404,
    );
  if (resource.mime_type !== "application/pdf")
    throw new ResourceSourceError(
      "AI reading currently supports text-based PDFs. Images and videos remain available as class resources.",
    );
  if (!resource.size_bytes || resource.size_bytes > MAX_AI_PDF_BYTES)
    throw new ResourceSourceError(
      "Choose a PDF up to 10 MB for AI generation.",
    );
  if (
    resource.storage_bucket !== LEARNING_RESOURCE_BUCKET ||
    !resource.storage_path.startsWith(
      `classes/${classId}/resources/${resourceId}/`,
    ) ||
    /\.\.|\\/.test(resource.storage_path)
  )
    throw new ResourceSourceError(
      "This resource has an unsupported storage reference.",
    );
  return resource;
}
export async function downloadResourceSource(
  client: SupabaseClient<Database>,
  resource: Awaited<ReturnType<typeof authorizeResourceSource>>,
) {
  // Sign as the Instructor: Storage SELECT RLS must also authorize the object.
  const { data, error } = await client.storage
    .from(LEARNING_RESOURCE_BUCKET)
    .createSignedUrl(resource.storage_path, 60);
  if (error || !data)
    throw new ResourceSourceError(
      "The private PDF could not be opened. Check Storage and retry.",
      503,
    );
  if (
    new URL(data.signedUrl).origin !==
    new URL(process.env.NEXT_PUBLIC_SUPABASE_URL!).origin
  )
    throw new ResourceSourceError(
      "The resource storage endpoint is invalid.",
      503,
    );
  const response = await fetch(data.signedUrl, {
    signal: AbortSignal.timeout(30_000),
    redirect: "error",
    cache: "no-store",
  });
  if (!response.ok || !response.body)
    throw new ResourceSourceError(
      "The private PDF could not be downloaded. Retry shortly.",
      503,
    );
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      length += value.byteLength;
      if (length > MAX_AI_PDF_BYTES)
        throw new ResourceSourceError(
          "This PDF exceeds the 10 MB AI reading limit.",
        );
      chunks.push(value);
    }
  } finally {
    await reader.cancel().catch(() => {});
  }
  if (length !== resource.size_bytes)
    throw new ResourceSourceError(
      "The stored PDF does not match its resource record. Upload a fresh copy.",
    );
  return Buffer.concat(chunks);
}
