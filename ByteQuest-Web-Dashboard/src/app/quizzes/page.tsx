import { DashboardLayout } from "@/components/layout/dashboard-layout";
import { QuizLibrary } from "@/components/quizzes/QuizLibrary";
import { requireStaffProfile } from "@/lib/auth/server";
import { createServerSupabaseClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function QuizzesPage() {
  await requireStaffProfile(["instructor"]);
  const supabase = await createServerSupabaseClient();
  const [
    { data: quizzes, error: quizError },
    { data: versions, error: versionError },
    { data: items, error: itemError },
    { data: modules, error: moduleError },
    { data: assignments, error: assignmentError },
  ] = await Promise.all([
    supabase
      .from("quizzes")
      .select("id,title,topic,description,coc_module_id,updated_at,archived_at")
      .order("updated_at", { ascending: false }),
    supabase
      .from("quiz_versions")
      .select("id,quiz_id,version_number,status,published_at"),
    supabase
      .from("quiz_items")
      .select("id,quiz_version_id,review_status,removed_at"),
    supabase
      .from("coc_modules")
      .select("id,coc_code,title")
      .order("order_index"),
    supabase.from('quiz_assignments').select('id,quiz_version_id,due_at,classes(title)').eq('status', 'active'),
  ]);
  if (quizError || versionError || itemError || moduleError || assignmentError)
    throw new Error("Quiz library could not be loaded.");

  const moduleById = new Map(
    (modules ?? []).map((module) => [module.id, module]),
  );
  const versionByQuiz = new Map<
    string,
    NonNullable<typeof versions>[number][]
  >();
  (versions ?? []).forEach((version) =>
    versionByQuiz.set(version.quiz_id, [
      ...(versionByQuiz.get(version.quiz_id) ?? []),
      version,
    ]),
  );
  const itemCountByVersion = new Map<string, number>();
  (items ?? [])
    .filter((item) => !item.removed_at)
    .forEach((item) =>
      itemCountByVersion.set(
        item.quiz_version_id,
        (itemCountByVersion.get(item.quiz_version_id) ?? 0) + 1,
      ),
    );

  return (
    <DashboardLayout>
      <div className="mx-auto max-w-7xl">
        <QuizLibrary
          serverNow={new Date().toISOString()}
          modules={(modules ?? []).map((module) => ({
            id: module.id,
            code: module.coc_code,
            title: module.title,
          }))}
          quizzes={(quizzes ?? []).map((quiz) => {
            const sorted = [...(versionByQuiz.get(quiz.id) ?? [])].sort(
              (a, b) => b.version_number - a.version_number,
            );
            const current =
              sorted.find((version) => version.status === "draft") ??
              sorted.find((version) => version.status === "published") ??
              sorted[0];
            return {
              id: quiz.id,
              title: quiz.title,
              topic: quiz.topic,
              coc: quiz.coc_module_id
                ? (moduleById.get(quiz.coc_module_id)?.coc_code.toUpperCase() ??
                  "General")
                : "General",
              status: quiz.archived_at
                ? "archived"
                : (current?.status ?? "draft"),
              version: current?.version_number ?? 1,
              questionCount: current
                ? (itemCountByVersion.get(current.id) ?? 0)
                : 0,
              deadlines: (assignments ?? []).filter(a => sorted.some(v => v.id === a.quiz_version_id && v.status === 'published') && !quiz.archived_at).map(a => ({ id: a.id, classTitle: a.classes?.title ?? 'Class', dueAt: a.due_at })),
            };
          })}
        />
      </div>
    </DashboardLayout>
  );
}
