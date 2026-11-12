import { createHash } from "node:crypto";
import { NextResponse } from "next/server";
import { z } from "zod";
import { getServerProfile } from "@/lib/auth/server";
import {
  ALLOWED_LEARNING_RESOURCE_TYPES,
  isAllowedLearningResourceMime,
  LEARNING_RESOURCE_BUCKET,
  MAX_LEARNING_RESOURCE_BYTES,
  matchesResourceContent,
} from "@/lib/resources/policy";
import { createAdminSupabaseClient } from "@/lib/supabase/admin";
import { createServerSupabaseClient } from "@/lib/supabase/server";
import { readResourceForm, UploadSizeError } from "@/lib/resources/upload-form";

export const runtime = "nodejs";

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ classId: string }> },
) {
  const actor = await getServerProfile();
  if (!actor || actor.role !== "instructor" || actor.status !== "active")
    return NextResponse.json(
      { error: "Active Instructor access is required." },
      { status: 403 },
    );
  const classId = classIdSchema.safeParse((await params).classId);
  if (!classId.success)
    return NextResponse.json(
      { error: "Invalid class identifier." },
      { status: 400 },
    );
  const client = await createServerSupabaseClient();
  const { data: owned } = await client
    .from("classes")
    .select("id")
    .eq("id", classId.data)
    .eq("instructor_id", actor.userId)
    .eq("status", "active")
    .maybeSingle();
  if (!owned)
    return NextResponse.json(
      { error: "Choose your own active class." },
      { status: 403 },
    );
  const { data, error } = await client
    .from("learning_resources")
    .select("id,title,mime_type,size_bytes")
    .eq("class_id", classId.data)
    .eq("status", "active")
    .order("created_at", { ascending: false });
  if (error)
    return NextResponse.json(
      { error: "Resources could not be loaded. Try Refresh resources." },
      { status: 503 },
    );
  return NextResponse.json(
    { resources: data },
    { headers: { "Cache-Control": "private, no-store" } },
  );
}

const classIdSchema = z.string().uuid();
const resourceMetadataSchema = z.object({
  title: z.string().trim().min(2).max(300),
  description: z.string().trim().max(2000).optional(),
});

export async function POST(
  request: Request,
  { params }: { params: Promise<{ classId: string }> },
) {
  const actor = await getServerProfile();
  if (!actor || actor.role !== "instructor" || actor.status !== "active") {
    return NextResponse.json(
      { error: "Active Instructor access is required." },
      { status: 403 },
    );
  }

  const parsedClassId = classIdSchema.safeParse((await params).classId);
  if (!parsedClassId.success) {
    return NextResponse.json(
      { error: "Invalid class identifier." },
      { status: 400 },
    );
  }

  const supabase = await createServerSupabaseClient();
  const { data: ownedClass, error: scopeError } = await supabase
    .from("classes")
    .select("id")
    .eq("id", parsedClassId.data)
    .eq("instructor_id", actor.userId)
    .eq("status", "active")
    .maybeSingle();
  if (scopeError || !ownedClass)
    return NextResponse.json(
      { error: "You can upload resources only to your own active class." },
      { status: 403 },
    );
  let formData: FormData;
  try {
    formData = await readResourceForm(request);
  } catch (error) {
    return NextResponse.json(
      {
        error:
          error instanceof UploadSizeError
            ? "The file must be no more than 50 MB."
            : "The upload was incomplete. Choose the file again and retry.",
      },
      { status: error instanceof UploadSizeError ? 413 : 400 },
    );
  }
  const file = formData?.get("file");
  const parsedMetadata = resourceMetadataSchema.safeParse({
    title: formData?.get("title"),
    description: formData?.get("description") || undefined,
  });

  if (!(file instanceof File) || !parsedMetadata.success) {
    return NextResponse.json(
      {
        error:
          "Provide a file, a 2–300 character title, and an optional description.",
      },
      { status: 400 },
    );
  }

  if (!isAllowedLearningResourceMime(file.type)) {
    return NextResponse.json(
      {
        error:
          "Only PDF, JPEG, PNG, WebP, MP4, and WebM learning resources are allowed.",
      },
      { status: 415 },
    );
  }

  if (file.size < 1 || file.size > MAX_LEARNING_RESOURCE_BYTES) {
    return NextResponse.json(
      { error: "The file must be larger than 0 bytes and no more than 50 MB." },
      { status: 413 },
    );
  }

  const bytes = Buffer.from(await file.arrayBuffer());
  if (!matchesResourceContent(file.type, bytes))
    return NextResponse.json(
      {
        error:
          "The file content does not match its selected format. Export the original file and try again.",
      },
      { status: 415 },
    );

  // Content + scoped metadata identify retries, including a lost HTTP response.
  // A different title/description intentionally creates a separate resource.
  const digest = createHash("sha256")
    .update(
      JSON.stringify([
        actor.userId,
        parsedClassId.data,
        parsedMetadata.data,
        file.type,
      ]),
    )
    .update(bytes)
    .digest("hex");
  const resourceId = `${digest.slice(0, 8)}-${digest.slice(8, 12)}-5${digest.slice(13, 16)}-a${digest.slice(17, 20)}-${digest.slice(20, 32)}`;
  const existing = () =>
    supabase
      .from("learning_resources")
      .select("*")
      .eq("id", resourceId)
      .eq("class_id", parsedClassId.data)
      .maybeSingle();
  const previous = await existing();
  if (previous.error)
    return NextResponse.json(
      { error: "Resource history could not be checked. Try again shortly." },
      { status: 503 },
    );
  if (previous.data?.status === "active")
    return NextResponse.json({ resource: previous.data, reused: true });
  if (previous.data)
    return NextResponse.json(
      {
        error:
          "This exact resource was archived. Change its title to upload a new copy.",
      },
      { status: 409 },
    );
  const extension = ALLOWED_LEARNING_RESOURCE_TYPES[file.type];
  const storagePath = `classes/${parsedClassId.data}/resources/${resourceId}/resource.${extension}`;
  const admin = createAdminSupabaseClient(30_000);
  const { error: journalError } = await admin
    .from("resource_upload_jobs")
    .upsert(
      {
        id: resourceId,
        class_id: parsedClassId.data,
        instructor_id: actor.userId,
        storage_path: storagePath,
      },
      { onConflict: "id", ignoreDuplicates: true },
    );
  if (journalError)
    return NextResponse.json(
      {
        error:
          "Safe upload tracking is unavailable. Ask the local administrator to apply the resource QA migration, then retry.",
      },
      { status: 503 },
    );
  const journal = async (state: string) =>
    admin
      .from("resource_upload_jobs")
      .update({ state, updated_at: new Date().toISOString() })
      .eq("id", resourceId);

  const { error: uploadError } = await admin.storage
    .from(LEARNING_RESOURCE_BUCKET)
    .upload(storagePath, bytes, {
      contentType: file.type,
      upsert: false,
      cacheControl: "3600",
    });

  if (uploadError) {
    const status =
      "statusCode" in uploadError ? String(uploadError.statusCode) : "";
    if (
      status !== "409" &&
      !/already exists|duplicate/i.test(uploadError.message)
    ) {
      const message =
        status === "413"
          ? "Storage rejected the file size. Maximum 50 MB."
          : status === "404"
            ? "The private resource bucket is not configured. Ask the local environment administrator to run preview setup."
            : status === "403"
              ? "Storage refused the upload. Ask the administrator to check private bucket permissions."
              : "Private Storage is unavailable. Start the isolated QA Storage service and retry; your file has not been rejected as invalid.";
      return NextResponse.json(
        { error: message },
        { status: status === "413" ? 413 : 503 },
      );
    }
    // Another identical upload may be finishing, or a process stopped before
    // metadata commit. Reuse its immutable bytes; never overwrite the object.
  }

  const { data, error } = await supabase.rpc("create_learning_resource", {
    p_resource_id: resourceId,
    p_class_id: parsedClassId.data,
    p_title: parsedMetadata.data.title,
    p_description: parsedMetadata.data.description ?? "",
    p_storage_path: storagePath,
    p_mime_type: file.type,
    p_size_bytes: file.size,
  });

  if (error || !data) {
    const committed = await existing();
    if (committed.data?.status === "active") {
      await journal("complete");
      return NextResponse.json({ resource: committed.data, reused: true });
    }
    // Only compensate a definitive rejection, never an ambiguous network error
    // or a duplicate writer. A retry reconciles an interrupted metadata commit.
    const definitive = error?.code === "42501" || error?.code === "22023";
    const cleanup =
      definitive && !uploadError && !committed.error
        ? await admin.storage
            .from(LEARNING_RESOURCE_BUCKET)
            .remove([storagePath])
        : null;
    await journal(cleanup && !cleanup.error ? "cleaned" : "cleanup_required");
    const message = error?.message.includes("CLASS_SCOPE_DENIED")
      ? "You can upload resources only to your own active class."
      : cleanup && !cleanup.error
        ? "Resource details were rejected and the uploaded file was removed. Check the details and retry."
        : "Resource confirmation was interrupted. Retry the same file and details to safely finish this upload.";
    return NextResponse.json(
      { error: message },
      { status: definitive ? 403 : 503 },
    );
  }

  await journal("complete");
  return NextResponse.json({ resource: data }, { status: 201 });
}
