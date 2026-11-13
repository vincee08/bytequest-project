import { notFound } from "next/navigation";
import { DashboardLayout } from "@/components/layout/dashboard-layout";
import { QuizAuthoringWorkspace } from "@/components/quizzes/QuizAuthoringWorkspace";
import {
  getQuizGroundingCatalog,
  type QuizGroundingCatalog,
} from "@/lib/ai/quiz-grounding";
import { requireStaffProfile } from "@/lib/auth/server";
import { createServerSupabaseClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

function toStringArray(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string")
    : [];
}

export default async function QuizDetailPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ version?: string; tab?: string }>;
}) {
  const profile = await requireStaffProfile(["instructor"]);
  const selected = (await searchParams).version;
  const { id } = await params;
  const supabase = await createServerSupabaseClient();
  const { data: quiz, error: quizError } = await supabase
    .from("quizzes")
    .select(
      "id,title,topic,description,coc_module_id,instructor_id,archived_at",
    )
    .eq("id", id)
    .maybeSingle();
  if (quizError) throw new Error("Quiz details could not be loaded.");
  if (!quiz) notFound();

  const [
    { data: versions, error: versionError },
    { data: modules, error: moduleError },
    { data: classes, error: classError },
  ] = await Promise.all([
    supabase
      .from("quiz_versions")
      .select(
        "id,quiz_id,version_number,status,instructions,change_summary,published_at,retired_at",
      )
      .eq("quiz_id", quiz.id)
      .order("version_number", { ascending: false }),
    supabase
      .from("coc_modules")
      .select("id,coc_code,title")
      .order("order_index"),
    supabase
      .from("classes")
      .select("id,title,class_code,status")
      .eq("status", "active")
      .eq("instructor_id", profile.userId)
      .order("title"),
  ]);
  if (versionError || moduleError || classError)
    throw new Error("Quiz settings could not be loaded.");
  const currentVersion =
    (selected ? versions?.find((version) => version.id === selected) : null) ??
    versions?.find((version) => version.status === "draft") ??
    versions?.find((version) => version.status === "published") ??
    versions?.[0] ??
    null;
  if (selected && !versions?.some((version) => version.id === selected))
    notFound();
  const { data: items, error: itemError } = currentVersion
    ? await supabase
        .from("quiz_items")
        .select(
          "id,item_code,item_type,prompt,options,correct_answer,explanation,origin,review_status,review_notes,order_index,removed_at",
        )
        .eq("quiz_version_id", currentVersion.id)
        .is("removed_at", null)
        .order("order_index")
    : { data: [], error: null };
  if (itemError) throw new Error("Quiz questions could not be loaded.");

  let grounding: QuizGroundingCatalog | null = null;
  if (quiz.coc_module_id) {
    try {
      grounding = await getQuizGroundingCatalog(supabase, quiz.coc_module_id);
    } catch {
      grounding = null;
    }
  }

  const versionIds = (versions ?? []).map((item) => item.id);
  const [assignmentResponse, attemptResponse] = versionIds.length
    ? await Promise.all([
        supabase
          .from("quiz_assignments")
          .select("id,class_id,quiz_version_id,status,due_at,classes(title)")
          .in("quiz_version_id", versionIds),
        supabase
          .from("quiz_attempts")
          .select(
            "id,status,quiz_version_id,completed_at,learner_id,classes(title),quiz_results(correct_count,question_count)",
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
  const learnerIds = [
    ...new Set((attemptResponse.data ?? []).map((item) => item.learner_id)),
  ];
  const { data: learners } = learnerIds.length
    ? await supabase
        .from("profiles")
        .select("user_id,full_name")
        .in("user_id", learnerIds)
    : { data: [] };
  return (
    <DashboardLayout>
      <div className="mx-auto max-w-7xl">
        <QuizAuthoringWorkspace
          initialTab={(await searchParams).tab}
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
          version={
            currentVersion
              ? {
                  id: currentVersion.id,
                  versionNumber: currentVersion.version_number,
                  status: currentVersion.status,
                  instructions: currentVersion.instructions,
                }
              : null
          }
          items={(items ?? []).map((item) => ({
            id: item.id,
            itemCode: item.item_code,
            itemType: item.item_type,
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
          }))}
          hasDraft={(versions ?? []).some((item) => item.status === "draft")}
          modules={(modules ?? []).map((item) => ({
            id: item.id,
            code: item.coc_code,
            title: item.title,
          }))}
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
          }))}
          assignments={(assignmentResponse.data ?? []).map((item) => ({
            id: item.id,
            classId: item.class_id,
            versionId: item.quiz_version_id,
            status: item.status,
            classTitle: item.classes?.title ?? "Class",
            dueAt: item.due_at,
          }))}
          results={(attemptResponse.data ?? []).map((item) => ({
            id: item.id,
            learner:
              learners?.find((learner) => learner.user_id === item.learner_id)
                ?.full_name ?? "Learner",
            classTitle: item.classes?.title ?? "Class",
            status: item.status,
            versionNumber:
              versions?.find((version) => version.id === item.quiz_version_id)
                ?.version_number ?? 1,
            completedAt: item.completed_at,
            correctCount: item.quiz_results?.correct_count ?? null,
            questionCount: item.quiz_results?.question_count ?? null,
          }))}
        />
      </div>
    </DashboardLayout>
  );
}
