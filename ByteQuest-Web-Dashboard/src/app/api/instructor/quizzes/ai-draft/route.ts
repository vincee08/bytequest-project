import { randomUUID } from "node:crypto";
import { NextResponse } from "next/server";
import type { SupabaseClient } from "@supabase/supabase-js";
import { z } from "zod";
import {
  getQuizAiConfiguration,
  QuizAiConfigurationError,
} from "@/lib/ai/config";
import {
  loadApprovedQuizGrounding,
  loadCurriculumQuizGrounding,
  QuizGroundingError,
} from "@/lib/ai/quiz-grounding";
import {
  authorizeResourceSource,
  downloadResourceSource,
  ResourceSourceError,
} from "@/lib/ai/resource-source";
import {
  generateQuizDraftWithOpenRouter,
  QuizAiProviderError,
} from "@/lib/ai/providers/openrouter";
import { quizItemTypeSchema, type QuizDraftRequest } from "@/lib/ai/quiz-draft";
import {
  extractResourcePdf,
  ResourcePdfError,
  pdfErrorMessages,
} from "@/lib/resources/pdf";
import { getServerProfile } from "@/lib/auth/server";
import { createAdminSupabaseClient } from "@/lib/supabase/admin";
import { createServerSupabaseClient } from "@/lib/supabase/server";

export const runtime = "nodejs";
export const maxDuration = 180;
const requestSchema = z
  .object({
    quizVersionId: z.string().uuid(),
    sourceMode: z
      .enum(["curriculum", "approved_coc", "class_resource"])
      .default("approved_coc"),
    activityVersionId: z.string().uuid().optional(),
    classId: z.string().uuid().optional(),
    resourceId: z.string().uuid().optional(),
    externalConsent: z.boolean().optional(),
    requestId: z.string().uuid().optional(),
    topic: z.string().trim().min(2).max(240),
    instructorContext: z.string().trim().max(2000).optional(),
    difficulty: z.enum(["foundation", "intermediate", "advanced"]),
    itemCount: z.number().int().min(1).max(10),
    itemTypes: z.array(quizItemTypeSchema).min(1).max(5),
    // "Regenerate this question": replace one draft question in one step.
    replaceItemId: z.string().uuid().optional(),
    replaceReason: z.string().trim().min(3).max(500).optional(),
  })
  .refine((value) =>
    value.sourceMode === "class_resource"
      ? Boolean(
          value.classId && value.resourceId && value.externalConsent === true,
        )
      : value.sourceMode === "approved_coc"
        ? Boolean(value.activityVersionId)
        : value.externalConsent === true,
  )
  .refine(
    (value) =>
      !value.replaceItemId ||
      (value.itemCount === 1 &&
        value.itemTypes.length === 1 &&
        Boolean(value.replaceReason)),
  );

export async function GET() {
  const actor = await getServerProfile();
  if (!actor || actor.role !== "instructor" || actor.status !== "active")
    return jsonError("Instructor access is required.", 403);
  try {
    getQuizAiConfiguration();
    return NextResponse.json(
      { configured: true, simulated: Boolean(process.env.BQ_AI_TEST_ENDPOINT) },
      { headers: { "Cache-Control": "private, no-store" } },
    );
  } catch {
    return NextResponse.json(
      { configured: false },
      { headers: { "Cache-Control": "private, no-store" } },
    );
  }
}

function jsonError(error: string, status: number, retryAfter?: string) {
  return NextResponse.json(
    { error },
    { status, headers: retryAfter ? { "Retry-After": retryAfter } : undefined },
  );
}
export async function POST(request: Request) {
  const actor = await getServerProfile();
  if (!actor || actor.role !== "instructor" || actor.status !== "active")
    return jsonError("Active Instructor access is required.", 403);
  const parsed = requestSchema.safeParse(
    await request.json().catch(() => null),
  );
  if (!parsed.success)
    return jsonError(
      "Choose a source, valid quiz settings and question types, and confirm that the content may be sent to OpenRouter. Regeneration needs a reason.",
      400,
    );
  const input = parsed.data;
  const supabase = await createServerSupabaseClient();
  const { data: version } = await supabase
    .from("quiz_versions")
    .select("id,quiz_id,status")
    .eq("id", input.quizVersionId)
    .maybeSingle();
  if (!version || version.status !== "draft")
    return jsonError("An owned draft quiz version is required.", 403);
  const { data: quiz } = await supabase
    .from("quizzes")
    .select("id,instructor_id,title,coc_module_id,archived_at")
    .eq("id", version.quiz_id)
    .maybeSingle();
  if (!quiz || quiz.instructor_id !== actor.userId || quiz.archived_at)
    return jsonError(
      "You can generate drafts only for your own active quiz.",
      403,
    );
  if (input.replaceItemId) {
    const { data: original } = await supabase
      .from("quiz_items")
      .select("id,item_type,removed_at,quiz_version_id")
      .eq("id", input.replaceItemId)
      .maybeSingle();
    if (
      !original ||
      original.removed_at ||
      original.quiz_version_id !== version.id ||
      (original.item_type as string) !== input.itemTypes[0]
    )
      return jsonError(
        "Choose an active question of this draft to regenerate.",
        422,
      );
  }
  const admin = createAdminSupabaseClient();
  let grounding: QuizDraftRequest["grounding"];
  let curriculum: QuizDraftRequest["curriculum"];
  let resource: Awaited<ReturnType<typeof authorizeResourceSource>> | undefined;
  try {
    if (input.sourceMode === "class_resource") {
      resource = await authorizeResourceSource(
        supabase,
        actor.userId,
        input.classId!,
        input.resourceId!,
      );
    } else if (input.sourceMode === "curriculum") {
      curriculum = await loadCurriculumQuizGrounding(supabase, quiz.id);
    } else {
      if (!quiz.coc_module_id)
        return jsonError(
          "Select and save a related COC, or choose My Class Resource for a supplementary quiz.",
          422,
        );
      grounding = await loadApprovedQuizGrounding(
        admin,
        quiz.coc_module_id,
        input.activityVersionId!,
      );
    }
  } catch (error) {
    if (error instanceof ResourceSourceError)
      return jsonError(error.publicMessage, error.status);
    if (error instanceof QuizGroundingError)
      return jsonError(
        input.sourceMode === "curriculum"
          ? "Map this quiz to a COC, its modules and a focus in Settings before generating from the curriculum."
          : "The selected activity needs complete, active approved COC content. Choose another approved activity or author manually.",
        422,
      );
    return jsonError(
      "The selected source could not be verified. Try again shortly.",
      503,
    );
  }
  let configuration;
  try {
    configuration = getQuizAiConfiguration();
  } catch (error) {
    if (error instanceof QuizAiConfigurationError)
      return jsonError(
        "OpenRouter is not configured on this server. Ask the administrator to configure the local AI key; manual authoring remains available.",
        503,
      );
    throw error;
  }
  const itemTypes = [...new Set(input.itemTypes)];
  // Store identifiers and consent only; never persist PDF text or instructor notes.
  const inputContext = {
    request_id: input.requestId ?? randomUUID(),
    source_mode: input.sourceMode,
    classification: "supplementary",
    topic: input.topic,
    difficulty: input.difficulty,
    item_types: itemTypes,
    draft_only: true,
    external_content_confirmed: input.externalConsent === true,
    instructor_context_supplied: Boolean(input.instructorContext),
    ...(input.replaceItemId ? { replace_item_id: input.replaceItemId } : {}),
    ...(resource
      ? { class_id: resource.class_id, resource_id: resource.id }
      : curriculum
        ? {
            coc_module_id: curriculum.coc.id,
            module_ids: curriculum.modules.map((module) => module.id),
            outcome_ids: curriculum.outcomes.map((outcome) => outcome.id),
            topic_id: curriculum.topic?.id ?? null,
          }
        : {
            tesda_source_id: grounding!.source.id,
            coc_module_id: grounding!.coc.id,
            competency_id: grounding!.competency.id,
            module_version_id: grounding!.module.id,
            activity_version_id: grounding!.activity.id,
            mission_id: grounding!.mission.id,
            rubric_version_id: grounding!.rubric.id,
          }),
  };
  const { data: generation, error: beginError } = await supabase.rpc(
    "begin_ai_quiz_generation",
    {
      p_quiz_version_id: version.id,
      p_provider: configuration.provider,
      p_model: configuration.model,
      p_input_context: inputContext,
      p_requested_count: input.itemCount,
    },
  );
  if (beginError || !generation)
    return jsonError(
      beginError?.message.includes("IN_PROGRESS")
        ? "An AI request is already in progress. Wait for it to finish; duplicate generation was prevented."
        : "The AI request could not be started. Refresh and retry.",
      beginError?.code === "55000" ? 409 : 403,
    );
  if (generation.status === "completed")
    return NextResponse.json({
      generationId: generation.id,
      provider: configuration.provider,
      generatedCount: generation.generated_count,
      status: "draft_review_required",
      reused: true,
    });
  if (generation.status !== "requested")
    return jsonError(
      "This request previously failed. Start a new generation request.",
      410,
    );

  try {
    let selectedResource: QuizDraftRequest["resource"];
    if (resource) {
      const extracted = await extractResourcePdf(
        await downloadResourceSource(supabase, resource),
      );
      selectedResource = { title: resource.title, text: extracted.text };
    }
    const items = await generateQuizDraftWithOpenRouter(
      {
        quizTitle: quiz.title,
        topic: input.topic,
        instructorContext: input.instructorContext?.trim() || null,
        difficulty: input.difficulty,
        itemCount: input.itemCount,
        itemTypes,
        grounding,
        curriculum,
        resource: selectedResource,
      },
      configuration,
    );
    // Recheck resource and class access after the external call before saving.
    if (resource)
      await authorizeResourceSource(
        supabase,
        actor.userId,
        resource.class_id,
        resource.id,
      );
    const service = admin as unknown as SupabaseClient;
    const { data: completion, error: completionError } = await service.rpc(
      "complete_ai_quiz_draft",
      {
        p_actor: actor.userId,
        p_generation_id: generation.id,
        p_provider: configuration.provider,
        p_model: configuration.model,
        p_items: items,
        p_replace_item_id: input.replaceItemId ?? null,
        p_replace_reason: input.replaceReason ?? null,
      },
    );
    const result = completion as { generated_count?: number } | null;
    if (completionError || !result?.generated_count)
      throw new Error("AI_DRAFT_COMMIT_FAILED");
    return NextResponse.json(
      {
        generationId: generation.id,
        provider: configuration.provider,
        generatedCount: result.generated_count,
        replaced: Boolean(input.replaceItemId),
        status: "draft_review_required",
      },
      { status: 201 },
    );
  } catch (error) {
    const failureCode =
      error instanceof QuizAiProviderError || error instanceof ResourcePdfError
        ? error.code
        : error instanceof ResourceSourceError
          ? "RESOURCE_SOURCE_UNAVAILABLE"
          : "AI_DRAFT_COMMIT_FAILED";
    await admin.rpc("fail_ai_quiz_generation", {
      p_generation_id: generation.id,
      p_actor_id: actor.userId,
      p_failure_code: failureCode,
    });
    if (error instanceof ResourcePdfError)
      return jsonError(
        pdfErrorMessages[error.code] ?? pdfErrorMessages.PDF_INVALID,
        error.code === "PDF_BUSY" ? 429 : 422,
      );
    if (error instanceof ResourceSourceError)
      return jsonError(error.publicMessage, error.status);
    if (error instanceof QuizAiProviderError)
      return jsonError(error.publicMessage, error.status, error.retryAfter);
    return jsonError(
      "The draft could not be saved safely. No question was published. Retry or author manually.",
      502,
    );
  }
}
