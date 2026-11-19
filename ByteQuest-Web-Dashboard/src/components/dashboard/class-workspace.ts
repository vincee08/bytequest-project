/** Class workspace tabs (?tab= deep links) and quiz deadline row mapping. */

export const classTabs = ["learners", "assignments", "resources", "bypasses", "settings"] as const;
export type ClassTab = (typeof classTabs)[number];

export function resolveClassTab(requested: string | string[] | undefined): ClassTab {
  const value = Array.isArray(requested) ? requested[0] : requested;
  return classTabs.includes(value as ClassTab) ? (value as ClassTab) : "learners";
}

export function classTabHref(classId: string, tab: ClassTab) {
  return `/classes/${classId}?tab=${tab}`;
}

type ClassQuizAssignment = {
  id: string;
  due_at: string | null;
  quiz_versions: { status: string; quizzes: { title: string } | null } | null;
};

/**
 * One deadline control per published quiz assignment of this class: the quiz
 * title is the quiz, the class title is the class (they were swapped before).
 */
export function classQuizDeadlineRows(assignments: ClassQuizAssignment[], classTitle: string) {
  return assignments
    .filter((row) => row.quiz_versions?.status === "published")
    .map((row) => ({
      quizTitle: row.quiz_versions?.quizzes?.title ?? "Quiz",
      assignment: { id: row.id, dueAt: row.due_at, classTitle },
    }));
}
