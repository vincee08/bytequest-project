import { DashboardLayout } from "@/components/layout/dashboard-layout";
import {
  QuizLibrary,
  type LibraryQuizWithDeadlines,
} from "@/components/quizzes/QuizLibrary";
import { requireStaffProfile } from "@/lib/auth/server";
import { libraryStatus } from "@/lib/quizzes/library";
import { loadCurriculumCatalog } from "@/lib/quizzes/server";
import {
  quizDb,
  type QuizCurriculumRow,
  type QuizModuleRow,
  type QuizVersionSettingsRow,
} from "@/lib/quizzes/types";
import { createServerSupabaseClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function QuizzesPage() {
  await requireStaffProfile(["instructor"]);
  const supabase = await createServerSupabaseClient();
  const db = quizDb(supabase);
  const [
    { data: quizzes, error: quizError },
    { data: curriculum, error: curriculumError },
    { data: versions, error: versionError },
    { data: settings, error: settingsError },
    { data: items, error: itemError },
    { data: links, error: linkError },
    { data: assignments, error: assignmentError },
    catalog,
  ] = await Promise.all([
    supabase
      .from("quizzes")
      .select("id,title,topic,description,coc_module_id,updated_at,archived_at")
      .order("updated_at", { ascending: false }),
    db.from("quizzes").select("id,focus,quiz_type,difficulty,topic_id"),
    supabase
      .from("quiz_versions")
      .select("id,quiz_id,version_number,status,published_at"),
    db.from("quiz_versions").select("id,time_limit_minutes,result_release_mode"),
    supabase
      .from("quiz_items")
      .select("id,quiz_version_id,item_type,review_status,removed_at"),
    db.from("quiz_modules").select("quiz_id,module_id"),
    supabase
      .from("quiz_assignments")
      .select("id,quiz_version_id,due_at,classes(title)")
      .eq("status", "active"),
    loadCurriculumCatalog(supabase),
  ]);
  if (
    quizError ||
    curriculumError ||
    versionError ||
    settingsError ||
    itemError ||
    linkError ||
    assignmentError
  )
    throw new Error("Quiz library could not be loaded.");

  const now = Date.now();
  const curriculumById = new Map(
    ((curriculum ?? []) as QuizCurriculumRow[]).map((row) => [row.id, row]),
  );
  const settingsById = new Map(
    ((settings ?? []) as QuizVersionSettingsRow[]).map((row) => [row.id, row]),
  );
  const modulesByQuiz = new Map<string, string[]>();
  for (const link of (links ?? []) as QuizModuleRow[]) {
    modulesByQuiz.set(link.quiz_id, [
      ...(modulesByQuiz.get(link.quiz_id) ?? []),
      link.module_id,
    ]);
  }
  const moduleById = new Map(catalog.modules.map((module) => [module.id, module]));
  const cocById = new Map(catalog.cocs.map((coc) => [coc.id, coc]));

  const library: LibraryQuizWithDeadlines[] = (quizzes ?? []).map((quiz) => {
    const quizVersions = (versions ?? [])
      .filter((version) => version.quiz_id === quiz.id)
      .sort((a, b) => b.version_number - a.version_number);
    const current =
      quizVersions.find((version) => version.status === "draft") ??
      quizVersions.find((version) => version.status === "published") ??
      quizVersions[0];
    const published = quizVersions.find((version) => version.status === "published");
    const activeItems = (items ?? []).filter(
      (item) => item.quiz_version_id === current?.id && !item.removed_at,
    );
    const publishedAssignments = (assignments ?? []).filter(
      (assignment) => assignment.quiz_version_id === published?.id,
    );
    const mapping = curriculumById.get(quiz.id);
    const moduleIds = [...(modulesByQuiz.get(quiz.id) ?? [])].sort(
      (a, b) =>
        (moduleById.get(a)?.sequenceOrder ?? 0) -
        (moduleById.get(b)?.sequenceOrder ?? 0),
    );
    const upcoming = publishedAssignments
      .map((assignment) => assignment.due_at)
      .filter((due): due is string => !!due && new Date(due).getTime() > now)
      .sort();
    return {
      id: quiz.id,
      title: quiz.title,
      topic: quiz.topic,
      cocId: quiz.coc_module_id,
      coc: quiz.coc_module_id
        ? (cocById.get(quiz.coc_module_id)?.code.toUpperCase() ?? "COC")
        : "General",
      moduleIds,
      moduleCodes: moduleIds.map((id) => moduleById.get(id)?.code ?? "Module"),
      topicId: mapping?.topic_id ?? null,
      quizType: mapping?.quiz_type ?? null,
      mapped: !!quiz.coc_module_id && !!mapping?.focus,
      status: libraryStatus({
        archived: !!quiz.archived_at,
        hasPublished: !!published,
        assignmentDueDates: publishedAssignments.map((assignment) => assignment.due_at),
        now,
      }),
      hasDraft: quizVersions.some((version) => version.status === "draft"),
      version: current?.version_number ?? 1,
      questionCount: activeItems.length,
      essayCount: activeItems.filter(
        (item) => (item.item_type as string) === "scenario_essay",
      ).length,
      timeLimitMinutes: current
        ? (settingsById.get(current.id)?.time_limit_minutes ?? null)
        : null,
      updatedAt: quiz.updated_at,
      nextDueAt: upcoming[0] ?? null,
      deadlines: quiz.archived_at
        ? []
        : publishedAssignments.map((assignment) => ({
            id: assignment.id,
            classTitle: assignment.classes?.title ?? "Class",
            dueAt: assignment.due_at,
          })),
    };
  });

  return (
    <DashboardLayout>
      <div className="mx-auto max-w-7xl">
        <QuizLibrary
          serverNow={new Date().toISOString()}
          catalog={catalog}
          quizzes={library}
        />
      </div>
    </DashboardLayout>
  );
}
