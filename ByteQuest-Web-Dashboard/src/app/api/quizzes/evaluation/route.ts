import { NextResponse } from "next/server";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  activityActor,
  activityWriteOriginAllowed,
} from "@/lib/activities/server";
import {
  evaluationError,
  evaluationRpcPayload,
  quizEvaluationRequestSchema,
} from "@/lib/quizzes/evaluation";

export const runtime = "nodejs";

/**
 * Evaluate -> Finalize -> Release for quiz essays and instructor-release
 * quizzes. The database re-checks that the caller teaches the attempt's class.
 */
export async function POST(request: Request) {
  const reply = (body: unknown, status = 200) =>
    NextResponse.json(body, {
      status,
      headers: { "Cache-Control": "private, no-store" },
    });
  try {
    if (!activityWriteOriginAllowed(request))
      return reply({ error: "Origin not allowed." }, 403);
    const actor = await activityActor(request);
    if (!actor || actor.role !== "instructor")
      return reply({ error: "Active Instructor access is required." }, 403);
    const raw = await request.text();
    if (raw.length > 20000) return reply({ error: "Request too large." }, 413);
    let input: unknown;
    try {
      input = JSON.parse(raw);
    } catch {
      return reply({ error: "Invalid evaluation request." }, 400);
    }
    const parsed = quizEvaluationRequestSchema.safeParse(input);
    if (!parsed.success)
      return reply(
        { error: "Check the attempt, rubric scores and feedback, then retry." },
        400,
      );
    const { action, payload } = evaluationRpcPayload(parsed.data);
    const service = actor.service as unknown as SupabaseClient;
    const { data, error } = await service.rpc("manage_quiz_evaluation", {
      p_actor: actor.id,
      p_action: action,
      p_payload: payload,
    });
    if (error) {
      const result = evaluationError(error.message);
      return reply({ error: result.error }, result.status);
    }
    return reply({ result: data });
  } catch {
    return reply(
      { error: "The evaluation could not be saved. Refresh before retrying." },
      503,
    );
  }
}
