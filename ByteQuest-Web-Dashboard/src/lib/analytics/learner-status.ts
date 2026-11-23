import type { LearnerPerformance, LearnerRow, LearnerStatus } from "@/lib/analytics/performance-types";

/** The order in which PostgreSQL evaluates the status rules: falling behind wins. */
export const STATUS_BOARD_ORDER = ["falling_behind", "struggling", "on_track"] as const satisfies readonly LearnerStatus[];

/** Learner status for a summary: loaded, or unavailable without failing the page around it. */
export type LearnerStatusState =
  | { state: "ready"; data: LearnerPerformance }
  | { state: "unavailable" };

export type LearnerStatusGroup = {
  status: LearnerStatus;
  count: number;
  learners: LearnerRow[];
  /** Learners of this status that are counted but not listed because of the limit. */
  hidden: number;
};

export function groupLearnersByStatus(
  data: Pick<LearnerPerformance, "learners">,
  limit = Number.POSITIVE_INFINITY,
): LearnerStatusGroup[] {
  return STATUS_BOARD_ORDER.map((status) => {
    const rows = data.learners.filter((row) => row.status === status);
    const learners = rows.slice(0, limit);
    return { status, count: rows.length, learners, hidden: rows.length - learners.length };
  });
}
