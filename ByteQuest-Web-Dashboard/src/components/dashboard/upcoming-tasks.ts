/**
 * Upcoming deadlines for the instructor overview, merged from the three real
 * deadline sources: class quiz assignments (published versions), published
 * homework and active technical assignments. Only active classes and future
 * deadlines are included; nothing is inferred when a deadline is missing.
 */
export type UpcomingKind = "quiz" | "homework" | "assignment";

export type UpcomingTask = {
  id: string;
  kind: UpcomingKind;
  title: string;
  detail: string;
  classId: string;
  classTitle: string;
  dueAt: string;
  href: string;
};

type ClassRow = { id: string; title: string; status: string };
type QuizAssignmentRow = {
  id: string;
  class_id: string;
  due_at: string | null;
  status: string;
  quiz_versions: { status: string; quizzes: { title: string } | null } | null;
};
type HomeworkRow = { id: string; class_id: string; title: string; status: string; deadline_at: string | null };
type AssignmentRow = { id: string; class_id: string; title: string; status: string; assignment_type: string; due_at: string | null };

const assignmentTypeLabel = (value: string) =>
  value ? value.replaceAll("_", " ").replace(/^\w/, (letter) => letter.toUpperCase()) : "Assignment";

export function buildUpcomingTasks({
  now,
  classes,
  quizzes,
  homework,
  assignments,
  limit = 6,
}: {
  now: Date;
  classes: ClassRow[];
  quizzes: QuizAssignmentRow[];
  homework: HomeworkRow[];
  assignments: AssignmentRow[];
  limit?: number;
}): UpcomingTask[] {
  const activeClasses = new Map(classes.filter((row) => row.status === "active").map((row) => [row.id, row.title]));
  const future = (value: string | null): value is string => Boolean(value) && new Date(value as string).getTime() >= now.getTime();
  const tasks: UpcomingTask[] = [];

  for (const row of quizzes) {
    if (row.status !== "active" || row.quiz_versions?.status !== "published" || !future(row.due_at) || !activeClasses.has(row.class_id)) continue;
    tasks.push({ id: `quiz-${row.id}`, kind: "quiz", title: row.quiz_versions.quizzes?.title ?? "Quiz", detail: "Quiz", classId: row.class_id, classTitle: activeClasses.get(row.class_id)!, dueAt: row.due_at, href: `/classes/${row.class_id}?tab=assignments` });
  }
  for (const row of homework) {
    if (row.status !== "published" || !future(row.deadline_at) || !activeClasses.has(row.class_id)) continue;
    tasks.push({ id: `homework-${row.id}`, kind: "homework", title: row.title, detail: "Homework", classId: row.class_id, classTitle: activeClasses.get(row.class_id)!, dueAt: row.deadline_at, href: `/classes/${row.class_id}?tab=assignments` });
  }
  for (const row of assignments) {
    if (row.status !== "active" || !future(row.due_at) || !activeClasses.has(row.class_id)) continue;
    tasks.push({ id: `assignment-${row.id}`, kind: "assignment", title: row.title, detail: assignmentTypeLabel(row.assignment_type), classId: row.class_id, classTitle: activeClasses.get(row.class_id)!, dueAt: row.due_at, href: `/classes/${row.class_id}?tab=assignments` });
  }

  return tasks
    .sort((a, b) => new Date(a.dueAt).getTime() - new Date(b.dueAt).getTime() || a.title.localeCompare(b.title))
    .slice(0, limit);
}
