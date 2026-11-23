import { NextResponse } from "next/server";
import { z } from "zod";
import {
  activityActor,
  activityError,
  activityHeaders,
  activityWriteOriginAllowed,
} from "@/lib/activities/server";
import {
  smallJson,
  uploadAction,
  uploadIdentity,
  verifyUploadedFile,
  InvalidUploadedFile,
  type UploadIntent,
} from "@/lib/uploads/server";
import { homeworkErrorMessage } from "@/lib/evaluations/homework";

export const runtime = "nodejs";
export const maxDuration = 180;
const prepare = z
  .object({
    action: z.literal("prepare"),
    purpose: z.enum(["resource", "homework"]),
    target_id: z.string().uuid(),
    filename: z.string().trim().min(1).max(200),
    mime: z.string(),
    size: z.number().int().positive().max(52428800),
    sha256: z.string().regex(/^[a-f0-9]{64}$/),
    title: z.string().trim().min(2).max(300).optional(),
    description: z.string().trim().max(2000).optional(),
  })
  .strict();
const finish = z
  .object({ action: z.literal("complete"), upload_id: z.string().uuid() })
  .strict();
const extensions: Record<string, string[]> = {
  "application/pdf": ["pdf"],
  "image/jpeg": ["jpg", "jpeg"],
  "image/png": ["png"],
  "image/webp": ["webp"],
  "video/mp4": ["mp4"],
  "video/webm": ["webm"],
  "text/plain": ["txt"],
};
export async function OPTIONS(request: Request) {
  return new NextResponse(null, {
    status: 204,
    headers: activityHeaders(request),
  });
}
export async function POST(request: Request) {
  const reply = (data: unknown, status = 200) =>
    NextResponse.json(data, { status, headers: activityHeaders(request) });
  try {
    if (!activityWriteOriginAllowed(request))
      return reply({ error: "Origin not allowed." }, 403);
    const actor = await activityActor(request);
    if (!actor || !["instructor", "learner"].includes(actor.role))
      return reply({ error: "Sign in with an authorized account." }, 401);
    let body: unknown;
    try {
      body = await smallJson(request);
    } catch {
      return reply({ error: "Provide a small, valid upload request." }, 400);
    }
    const start = prepare.safeParse(body);
    if (start.success) {
      const input = start.data;
      const filename = input.filename.replace(/[\\/\u0000-\u001f\u007f]/g, "_");
      if (
        !extensions[input.mime]?.includes(
          filename.split(".").pop()?.toLowerCase() ?? "",
        ) ||
        (input.purpose === "resource" &&
          (!input.title || input.mime === "text/plain")) ||
        (input.purpose === "homework" &&
          (input.size > 10485760 || input.mime.startsWith("video/")))
      )
        return reply(
          {
            error:
              "Choose a matching file format and an allowed file size (resources 50 MB; homework 10 MB).",
          },
          422,
        );
      // Fixed field order gives identical retries the same immutable identity.
      const spec = {
        purpose: input.purpose,
        target_id: input.target_id,
        filename,
        mime: input.mime,
        size: input.size,
        sha256: input.sha256,
        title: input.title ?? "",
        description: input.description ?? "",
      };
      const id = uploadIdentity({ actor: actor.id, ...spec });
      const saved = await uploadAction(actor.service, actor.id, "prepare", {
        id,
        ...spec,
      });
      if (saved.error) {
        if (saved.error.message?.includes("UPLOAD_PENDING_LIMIT"))
          return reply(
            {
              error:
                "Too many unfinished uploads. Finish an existing upload or wait for cleanup before adding another.",
            },
            409,
          );
        const e = activityError(saved.error);
        return reply({ error: e.error }, e.status);
      }
      const intent = saved.data as unknown as UploadIntent;
      if (intent.state === "complete")
        return reply({ complete: true, record: intent.result });
      const signed = await actor.service.storage
        .from(intent.bucket)
        .createSignedUploadUrl(intent.object_path, { upsert: false });
      // A lost acknowledgement can leave the exact object present while the
      // journal is still pending. Storage also refuses a second signed URL in
      // that case. Resume verification; never grant overwrite permission.
      if (
        signed.error &&
        "statusCode" in signed.error &&
        String(signed.error.statusCode) === "409"
      )
        return reply({ upload_id: intent.id, uploaded: true });
      if (signed.error)
        return reply(
          {
            error:
              "Storage upload permission could not be prepared. Retry shortly.",
          },
          503,
        );
      return reply({ upload_id: intent.id, signed_url: signed.data.signedUrl });
    }
    const parsed = finish.safeParse(body);
    if (!parsed.success)
      return reply({ error: "Choose a valid upload action." }, 400);
    const claimed = await uploadAction(actor.service, actor.id, "claim", {
      id: parsed.data.upload_id,
    });
    if (claimed.error) {
      const e = activityError(claimed.error);
      return reply({ error: e.error }, e.status);
    }
    const intent = claimed.data as unknown as UploadIntent;
    if (intent.state === "complete")
      return reply({ complete: true, record: intent.result });
    const lease = { id: intent.id, lease_id: intent.lease_id };
    try {
      await verifyUploadedFile(actor.service, intent);
    } catch (error) {
      await uploadAction(
        actor.service,
        actor.id,
        error instanceof InvalidUploadedFile ? "reject" : "retry",
        lease,
      );
      return reply(
        {
          error:
            error instanceof InvalidUploadedFile
              ? "The uploaded bytes do not match the selected file. Choose the original file and retry."
              : "Upload verification was interrupted. Retry the same file and details.",
        },
        error instanceof InvalidUploadedFile ? 415 : 503,
      );
    }
    const committed = await uploadAction(
      actor.service,
      actor.id,
      "commit",
      lease,
    );
    if (committed.error) {
      // A file the homework does not accept (answer-only, images only) is a
      // final refusal: reject the intent so cleanup removes the bytes.
      const message = committed.error.message ?? "";
      const refused = ["HOMEWORK_FILES_NOT_ACCEPTED", "HOMEWORK_IMAGE_FILES_REQUIRED"].some((code) => message.includes(code));
      await uploadAction(actor.service, actor.id, refused ? "reject" : "retry", lease);
      const e = (refused ? homeworkErrorMessage(committed.error) : null) ?? activityError(committed.error);
      return reply({ error: e.error }, e.status);
    }
    return reply(
      {
        complete: true,
        record: (committed.data as unknown as UploadIntent).result,
      },
      201,
    );
  } catch {
    return reply(
      {
        error:
          "Upload could not be confirmed. Retry the same file and details.",
      },
      503,
    );
  }
}
