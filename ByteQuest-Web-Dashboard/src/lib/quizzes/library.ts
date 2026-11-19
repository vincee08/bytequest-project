import type { QuizType } from "./types";

/**
 * Library availability states:
 * - draft: no published version yet;
 * - published: a published version exists and at least one class
 *   assignment is still open (or none is assigned yet);
 * - closed: every active class assignment of the published version is past
 *   its deadline ("Close now" sets the deadline to the server time);
 * - archived: the quiz was archived (history retained).
 */
export type LibraryStatus = "draft" | "published" | "closed" | "archived";

export interface LibraryQuiz {
  id: string;
  title: string;
  topic: string;
  cocId: string | null;
  coc: string;
  moduleIds: string[];
  moduleCodes: string[];
  topicId: string | null;
  quizType: QuizType | null;
  mapped: boolean;
  status: LibraryStatus;
  hasDraft: boolean;
  version: number;
  questionCount: number;
  essayCount: number;
  timeLimitMinutes: number | null;
  updatedAt: string;
  nextDueAt: string | null;
}

export function libraryStatus(input: {
  archived: boolean;
  hasPublished: boolean;
  assignmentDueDates: (string | null)[];
  now: number;
}): LibraryStatus {
  if (input.archived) return "archived";
  if (!input.hasPublished) return "draft";
  if (
    input.assignmentDueDates.length > 0 &&
    input.assignmentDueDates.every(
      (due) => due !== null && new Date(due).getTime() <= input.now,
    )
  ) {
    return "closed";
  }
  return "published";
}

export interface LibraryFilters {
  search: string;
  cocId: string;
  moduleId: string;
  topicId: string;
  quizType: string;
  status: string;
  sort: "updated" | "title" | "due" | "status";
}

export const defaultLibraryFilters: LibraryFilters = {
  search: "",
  cocId: "",
  moduleId: "",
  topicId: "",
  quizType: "",
  status: "active",
  sort: "updated",
};

const statusOrder: Record<LibraryStatus, number> = {
  draft: 0,
  published: 1,
  closed: 2,
  archived: 3,
};

/**
 * A module filter matches quizzes linked to that module and whole-COC quizzes
 * of the module's COC (they assess every module of the COC).
 */
export function filterLibrary<T extends LibraryQuiz>(
  quizzes: T[],
  filters: LibraryFilters,
  moduleCoc: Map<string, string>,
) {
  const query = filters.search.trim().toLowerCase();
  const visible = quizzes.filter((quiz) => {
    if (filters.status === "active" && quiz.status === "archived") return false;
    if (
      filters.status &&
      filters.status !== "active" &&
      filters.status !== "all" &&
      quiz.status !== filters.status
    )
      return false;
    if (filters.cocId && quiz.cocId !== filters.cocId) return false;
    if (filters.moduleId) {
      const linked = quiz.moduleIds.includes(filters.moduleId);
      const wholeCoc =
        quiz.mapped &&
        quiz.moduleIds.length === 0 &&
        quiz.cocId === moduleCoc.get(filters.moduleId);
      if (!linked && !wholeCoc) return false;
    }
    if (filters.topicId && quiz.topicId !== filters.topicId) return false;
    if (filters.quizType && quiz.quizType !== filters.quizType) return false;
    if (
      query &&
      !`${quiz.title} ${quiz.topic} ${quiz.coc} ${quiz.moduleCodes.join(" ")}`
        .toLowerCase()
        .includes(query)
    )
      return false;
    return true;
  });
  return visible.sort((a, b) => {
    if (filters.sort === "title") return a.title.localeCompare(b.title);
    if (filters.sort === "status")
      return (
        statusOrder[a.status] - statusOrder[b.status] ||
        a.title.localeCompare(b.title)
      );
    if (filters.sort === "due") {
      const left = a.nextDueAt ? new Date(a.nextDueAt).getTime() : Infinity;
      const right = b.nextDueAt ? new Date(b.nextDueAt).getTime() : Infinity;
      return left - right || a.title.localeCompare(b.title);
    }
    return new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime();
  });
}

export const libraryStatusLabels: Record<LibraryStatus, string> = {
  draft: "Draft",
  published: "Published",
  closed: "Closed",
  archived: "Archived",
};
