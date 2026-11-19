import { notFound } from "next/navigation";
import { DashboardLayout } from "@/components/layout/dashboard-layout";
import { QuizAuthoringWorkspace } from "@/components/quizzes/QuizAuthoringWorkspace";
import type { ResultAttempt } from "@/components/quizzes/QuizResultsPanel";
import {
  getQuizGroundingCatalog,
  type QuizGroundingCatalog,
} from "@/lib/ai/quiz-grounding";
import { requireStaffProfile } from "@/lib/auth/server";
import { fromRpcRubric } from "@/lib/quizzes/authoring";
import {
  loadCurriculumCatalog,
  processExpiredQuizAttempts,
} from "@/lib/quizzes/server";
import {
  quizDb,
  type QuizAnswerRow,
  type QuizAttemptRow,
  type QuizCurriculumRow,
  type QuizEssayScoreRow,
  type QuizFinalizationRow,
  type QuizItemExtraRow,
  type QuizModuleRow,
  type QuizOutcomeRow,
  type QuizResultRow,
  type QuizVersionSettingsRow,
} from "@/lib/quizzes/types";
import { createServerSupabaseClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

function toStringArray(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string")
    : [];
}

const percentOf = (score: number | null, max: number | null) =>
  score !== null && max ? Math.round((score / max) * 1000) / 10 : null;

export default async function QuizDetailPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ version?: string; tab?: string; attempt?: string }>;
}) {
  const profile = await requireStaffProfile(["instructor"]);
  const query = await searchParams;
  const selected = query.version;
  const { id } = await params;
  const supabase = await createServerSupabaseClient();
  const db = quizDb(supabase);
  const { data: quiz, error: quizError } = await supabase
    .from("quizzes")
    .select(
      "id,title,topic,description,coc_module_id,instructor_id,archived_at",
    )
    .eq("id", id)
    .maybeSingle();
  if (quizError) throw new Error("Quiz details could not be loaded.");
  if (!quiz) notFound();

  // Results read path: finalise attempts whose deadline or time limit passed.
  await processExpiredQuizAttempts(profile.userId, quiz.id);

  const [
    { data: versions, error: versionError },
    { data: settings, error: settingsError },
    { data: mapping, error: mappingError },
    { data: moduleLinks, error: moduleError },
    { data: outcomeLinks, error: outcomeError },
    { data: classes, error: classError },
    catalog,
  ] = await Promise.all([
    supabase
      .from("quiz_versions")
      .select(
        "id,quiz_id,version_number,status,instructions,change_summary,published_at,retired_at",
      )
      .eq("quiz_id", quiz.id)
      .order("version_number", { ascending: false }),
    db
      .from("quiz_versions")
      .select("id,time_limit_minutes,result_release_mode")
      .eq("quiz_id", quiz.id),
    db
      .from("quizzes")
      .select("id,focus,quiz_type,difficulty,topic_id")
      .eq("id", quiz.id)
      .maybeSingle(),
    db.from("quiz_modules").select("quiz_id,module_id").eq("quiz_id", quiz.id),
    db
      .from("quiz_learning_outcomes")
      .select("quiz_id,outcome_id")
      .eq("quiz_id", quiz.id),
    supabase
      .from("classes")
      .select("id,title,class_code,status")
      .eq("status", "active")
      .eq("instructor_id", profile.userId)
      .order("title"),
    loadCurriculumCatalog(supabase),
  ]);
  if (
    versionError ||
    settingsError ||
    mappingError ||
    moduleError ||
    outcomeError ||
    classError
  )
    throw new Error("Quiz settings could not be loaded.");
  const settingsById = new Map(
    ((settings ?? []) as QuizVersionSettingsRow[]).map((row) => [row.id, row]),
  );
  const curriculum = mapping as QuizCurriculumRow | null;
  const currentVersion =
    (selected ? versions?.find((version) => version.id === selected) : null) ??
    versions?.find((version) => version.status === "draft") ??
    versions?.find((version) => version.status === "published") ??
    versions?.[0] ??
    null;
  if (selected && !versions?.some((version) => version.id === selected))
    notFound();
  const versionIds = (versions ?? []).map((item) => item.id);
  const [
    { data: items, error: itemError },
    { data: itemExtras, error: extraError },
  ] = await Promise.all([
    currentVersion
      ? supabase
          .from("quiz_items")
          .select(
            "id,item_code,item_type,prompt,options,correct_answer,explanation,origin,review_status,review_notes,order_index,removed_at",
          )
          .eq("quiz_version_id", currentVersion.id)
          .is("removed_at", null)
          .order("order_index")
      : Promise.resolve({ data: [], error: null }),
    versionIds.length
      ? db
          .from("quiz_items")
          .select("id,quiz_version_id,item_type,prompt,scenario,rubric,points,min_words,max_words,removed_at,review_status")
          .in("quiz_version_id", versionIds)
      : Promise.resolve({ data: [], error: null }),
  ]);
  if (itemError || extraError) throw new Error("Quiz questions could not be loaded.");
  const extras = new Map(
    ((itemExtras ?? []) as (QuizItemExtraRow & {
      quiz_version_id: string;
      item_type: string;
      prompt: string;
      removed_at: string | null;
      review_status: string;
    })[]).map((row) => [row.id, row]),
  );

  let grounding: QuizGroundingCatalog | null = null;
  if (quiz.coc_module_id) {
    try {
      grounding = await getQuizGroundingCatalog(supabase, quiz.coc_module_id);
    } catch {
      grounding = null;
    }
  }

  const [assignmentResponse, attemptResponse] = versionIds.length
    ? await Promise.all([
        supabase
          .from("quiz_assignments")
          .select("id,class_id,quiz_version_id,status,due_at,classes(title)")
          .in("quiz_version_id", versionIds),
        db
          .from("quiz_attempts")
          .select(
            "id,learner_id,class_id,quiz_assignment_id,quiz_version_id,status,started_at,submitted_at,completed_at,time_limit_minutes,submission_kind,evaluation_status",
          )
          .in("quiz_version_id", versionIds)
          .order("started_at", { ascending: false }),
      ])
    : [
        { data: [], error: null },
        { data: [], error: null },
      ];
  if (assignmentResponse.error || attemptResponse.error)
    throw new Error(
      "Quiz assignments or results could not be loaded. Refresh to try again.",
    );
  const attempts = (attemptResponse.data ?? []) as QuizAttemptRow[];
  const attemptIds = attempts.map((attempt) => attempt.id);
  const essayItemIds = [...extras.values()]
    .filter((item) => item.item_type === "scenario_essay")
    .map((item) => item.id);
  const assignedClassIds = [
    ...new Set((assignmentResponse.data ?? []).map((item) => item.class_id)),
  ];
  const learnerIds = [...new Set(attempts.map((item) => item.learner_id))];
  const [results, finalizations, essayScores, essayAnswers, learners, members] =
    await Promise.all([
      attemptIds.length
        ? db
            .from("quiz_results")
            .select("quiz_attempt_id,correct_count,question_count,objective_points,max_points,item_results")
            .in("quiz_attempt_id", attemptIds)
        : Promise.resolve({ data: [], error: null }),
      attemptIds.length
        ? db
            .from("quiz_result_finalizations")
            .select("attempt_id,objective_points,essay_points,total_points,max_points,percent,finalized_at,released_at")
            .in("attempt_id", attemptIds)
        : Promise.resolve({ data: [], error: null }),
      attemptIds.length && essayItemIds.length
        ? db
            .from("quiz_essay_scores")
            .select("id,attempt_id,item_id,criterion_scores,total,feedback,evaluated_by,evaluated_at")
            .in("attempt_id", attemptIds)
            .order("evaluated_at", { ascending: false })
        : Promise.resolve({ data: [], error: null }),
      attemptIds.length && essayItemIds.length
        ? db
            .from("quiz_answers")
            .select("quiz_attempt_id,quiz_item_id,answer,is_correct")
            .in("quiz_attempt_id", attemptIds)
            .in("quiz_item_id", essayItemIds)
        : Promise.resolve({ data: [], error: null }),
      learnerIds.length
        ? supabase.from("profiles").select("user_id,full_name").in("user_id", learnerIds)
        : Promise.resolve({ data: [], error: null }),
      assignedClassIds.length
        ? supabase
            .from("class_memberships")
            .select("learner_id,class_id")
            .in("class_id", assignedClassIds)
            .eq("status", "active")
        : Promise.resolve({ data: [], error: null }),
    ]);
  if (results.error || finalizations.error || essayScores.error || essayAnswers.error)
    throw new Error("Quiz results could not be loaded. Refresh to try again.");

  const resultByAttempt = new Map(
    ((results.data ?? []) as QuizResultRow[]).map((row) => [row.quiz_attempt_id, row]),
  );
  const finalByAttempt = new Map(
    ((finalizations.data ?? []) as QuizFinalizationRow[]).map((row) => [row.attempt_id, row]),
  );
  const scoresByKey = new Map<string, QuizEssayScoreRow[]>();
  for (const score of (essayScores.data ?? []) as QuizEssayScoreRow[]) {
    const key = `${score.attempt_id}:${score.item_id}`;
    scoresByKey.set(key, [...(scoresByKey.get(key) ?? []), score]);
  }
  const answerByKey = new Map(
    ((essayAnswers.data ?? []) as QuizAnswerRow[]).map((row) => [
      `${row.quiz_attempt_id}:${row.quiz_item_id}`,
      typeof row.answer === "string" ? row.answer : String(row.answer ?? ""),
    ]),
  );
  const nameById = new Map(
    (learners.data ?? []).map((row) => [row.user_id, row.full_name]),
  );
  const enrolled = new Set((members.data ?? []).map((row) => row.learner_id)).size;
  const classTitle = new Map(
    (assignmentResponse.data ?? []).map((item) => [item.class_id, item.classes?.title ?? "Class"]),
  );
  const versionNumber = new Map((versions ?? []).map((item) => [item.id, item.version_number]));

  const resultAttempts: ResultAttempt[] = attempts.map((attempt) => {
    const result = resultByAttempt.get(attempt.id);
    const final = finalByAttempt.get(attempt.id);
    const essays = [...extras.values()]
      .filter(
        (item) =>
          item.quiz_version_id === attempt.quiz_version_id &&
          item.item_type === "scenario_essay" &&
          !item.removed_at &&
          item.review_status === "approved",
      )
      .map((item) => {
        const history = scoresByKey.get(`${attempt.id}:${item.id}`) ?? [];
        const latest = history[0];
        return {
          itemId: item.id,
          prompt: item.prompt,
          scenario: item.scenario,
          rubric: fromRpcRubric(item.rubric),
          points: Number(item.points),
          answer: answerByKey.get(`${attempt.id}:${item.id}`) ?? null,
          latest: latest
            ? {
                criterionScores: latest.criterion_scores,
                total: Number(latest.total),
                feedback: latest.feedback,
                evaluatedAt: latest.evaluated_at,
              }
            : null,
          scoreCount: history.length,
        };
      });
    const objective =
      result?.objective_points !== null && result?.objective_points !== undefined
        ? Number(result.objective_points)
        : (result?.correct_count ?? null);
    const max =
      result?.max_points !== null && result?.max_points !== undefined
        ? Number(result.max_points)
        : (result?.question_count ?? null);
    const essayPoints = essays.reduce((total, essay) => total + (essay.latest?.total ?? 0), 0);
    const score = final
      ? Number(final.total_points)
      : attempt.evaluation_status === "not_required"
        ? objective
        : attempt.evaluation_status === "evaluated" && objective !== null
          ? objective + essayPoints
          : null;
    const maxScore = final ? Number(final.max_points) : max;
    return {
      id: attempt.id,
      learnerId: attempt.learner_id,
      learner: nameById.get(attempt.learner_id) || "Learner",
      classTitle: classTitle.get(attempt.class_id) ?? "Class",
      versionNumber: versionNumber.get(attempt.quiz_version_id) ?? 1,
      status: attempt.status,
      evaluationStatus: attempt.evaluation_status,
      submissionKind: attempt.submission_kind,
      submittedAt: attempt.submitted_at,
      percent:
        attempt.status !== "completed"
          ? null
          : final
            ? Number(final.percent)
            : attempt.evaluation_status === "not_required"
              ? percentOf(objective, max)
              : null,
      score,
      maxScore,
      items: Array.isArray(result?.item_results) ? result.item_results : [],
      essays,
    };
  });

  return (
    <DashboardLayout>
      <div className="mx-auto max-w-7xl">
        <QuizAuthoringWorkspace
          initialTab={query.tab}
          initialAttemptId={query.attempt}
          serverNow={new Date().toISOString()}
          key={currentVersion?.id}
          quiz={{
            id: quiz.id,
            title: quiz.title,
            topic: quiz.topic,
            description: quiz.description,
            cocModuleId: quiz.coc_module_id,
            archivedAt: quiz.archived_at,
          }}
          curriculum={{
            focus: curriculum?.focus ?? null,
            quizType: curriculum?.quiz_type ?? null,
            difficulty: curriculum?.difficulty ?? null,
            topicId: curriculum?.topic_id ?? null,
            moduleIds: ((moduleLinks ?? []) as QuizModuleRow[]).map((row) => row.module_id),
            outcomeIds: ((outcomeLinks ?? []) as QuizOutcomeRow[]).map((row) => row.outcome_id),
          }}
          catalog={catalog}
          version={
            currentVersion
              ? {
                  id: currentVersion.id,
                  versionNumber: currentVersion.version_number,
                  status: currentVersion.status,
                  instructions: currentVersion.instructions,
                  timeLimitMinutes: settingsById.get(currentVersion.id)?.time_limit_minutes ?? null,
                  resultReleaseMode: settingsById.get(currentVersion.id)?.result_release_mode ?? "immediate",
                }
              : null
          }
          items={(items ?? []).map((item) => {
            const extra = extras.get(item.id);
            return {
              id: item.id,
              itemCode: item.item_code,
              itemType: item.item_type as ResultAttempt["items"][number]["type"],
              prompt: item.prompt,
              options: toStringArray(item.options),
              correctAnswer:
                typeof item.correct_answer === "string"
                  ? item.correct_answer
                  : String(item.correct_answer ?? ""),
              explanation: item.explanation,
              origin: item.origin,
              reviewStatus: item.review_status,
              reviewNotes: item.review_notes,
              orderIndex: item.order_index,
              points: extra ? Number(extra.points) : 1,
              scenario: extra?.scenario ?? null,
              rubric: fromRpcRubric(extra?.rubric),
              minWords: extra?.min_words ?? null,
              maxWords: extra?.max_words ?? null,
            };
          })}
          hasDraft={(versions ?? []).some((item) => item.status === "draft")}
          classes={(classes ?? []).map((item) => ({
            id: item.id,
            title: item.title,
            code: item.class_code,
          }))}
          grounding={grounding}
          versions={(versions ?? []).map((item) => ({
            id: item.id,
            versionNumber: item.version_number,
            status: item.status,
            instructions: item.instructions,
            changeSummary: item.change_summary,
            publishedAt: item.published_at,
            timeLimitMinutes: settingsById.get(item.id)?.time_limit_minutes ?? null,
            resultReleaseMode: settingsById.get(item.id)?.result_release_mode ?? "immediate",
          }))}
          assignments={(assignmentResponse.data ?? []).map((item) => ({
            id: item.id,
            classId: item.class_id,
            versionId: item.quiz_version_id,
            status: item.status,
            classTitle: item.classes?.title ?? "Class",
            dueAt: item.due_at,
          }))}
          results={resultAttempts}
          enrolled={enrolled}
        />
      </div>
    </DashboardLayout>
  );
}
