import type {
  EvaluationStatus,
  QuizItemResultJson,
  SubmissionKind,
} from "./types";

/**
 * Quiz result statistics for the instructor Results tab.
 *
 * Metric definitions (documented for the panel):
 * - participants: distinct learners with an attempt (any state).
 * - submitted: distinct learners whose attempt is completed (learner or
 *   automatic submission).
 * - completion rate: submitted learners / learners enrolled in the assigned
 *   classes (null when nobody is enrolled).
 * - average, highest, lowest and distribution use FINAL scores only:
 *   immediate results, or instructor-release results once finalized or
 *   released. Pending and evaluated-but-not-finalized attempts are counted
 *   separately and excluded, so no average contains a provisional score.
 */
export interface StatsAttempt {
  learnerId: string;
  status: "in_progress" | "submitted" | "completed";
  evaluationStatus: EvaluationStatus;
  submissionKind: SubmissionKind;
  /** Final percent (0-100) or null while evaluation is pending. */
  percent: number | null;
}

export interface QuizResultStats {
  participants: number;
  submitted: number;
  inProgress: number;
  enrolled: number;
  completionRate: number | null;
  finalScores: number;
  pendingEvaluation: number;
  autoSubmitted: number;
  average: number | null;
  highest: number | null;
  lowest: number | null;
  distribution: { label: string; min: number; max: number; count: number }[];
}

const round1 = (value: number) => Math.round(value * 10) / 10;

export const DISTRIBUTION_BANDS = [
  { label: "0–49%", min: 0, max: 49.999 },
  { label: "50–59%", min: 50, max: 59.999 },
  { label: "60–69%", min: 60, max: 69.999 },
  { label: "70–79%", min: 70, max: 79.999 },
  { label: "80–89%", min: 80, max: 89.999 },
  { label: "90–100%", min: 90, max: 100 },
] as const;

export function isFinalScore(status: EvaluationStatus) {
  return (
    status === "not_required" || status === "finalized" || status === "released"
  );
}

export function quizResultStats(
  attempts: StatsAttempt[],
  enrolled: number,
): QuizResultStats {
  const participants = new Set(attempts.map((attempt) => attempt.learnerId));
  const completed = attempts.filter((attempt) => attempt.status === "completed");
  const submittedLearners = new Set(completed.map((attempt) => attempt.learnerId));
  const finals = completed.filter(
    (attempt) =>
      isFinalScore(attempt.evaluationStatus) && attempt.percent !== null,
  );
  const scores = finals.map((attempt) => attempt.percent as number);
  return {
    participants: participants.size,
    submitted: submittedLearners.size,
    inProgress: new Set(
      attempts
        .filter((attempt) => attempt.status === "in_progress")
        .map((attempt) => attempt.learnerId),
    ).size,
    enrolled,
    completionRate:
      enrolled > 0
        ? round1((Math.min(submittedLearners.size, enrolled) / enrolled) * 100)
        : null,
    finalScores: scores.length,
    pendingEvaluation: completed.length - finals.length,
    autoSubmitted: completed.filter(
      (attempt) => attempt.submissionKind !== "learner",
    ).length,
    average: scores.length
      ? round1(scores.reduce((total, score) => total + score, 0) / scores.length)
      : null,
    highest: scores.length ? round1(Math.max(...scores)) : null,
    lowest: scores.length ? round1(Math.min(...scores)) : null,
    distribution: DISTRIBUTION_BANDS.map((band) => ({
      label: band.label,
      min: band.min,
      max: band.max,
      count: scores.filter((score) => score >= band.min && score <= band.max)
        .length,
    })),
  };
}

export interface QuestionCorrectness {
  itemId: string;
  orderIndex: number;
  prompt: string;
  type: string;
  responses: number;
  answered: number;
  correct: number;
  /** Objective items: % correct of submitted responses. Essays: average % of points. */
  rate: number | null;
}

/**
 * Per-question results across submitted attempts. Objective correctness is
 * known at submission; essay rates use the latest instructor scores only.
 */
export function questionCorrectness(
  submissions: { items: QuizItemResultJson[] }[],
  essayScores: Map<string, { points: number; max: number }[]> = new Map(),
): QuestionCorrectness[] {
  const byItem = new Map<string, QuestionCorrectness>();
  for (const submission of submissions) {
    for (const item of submission.items) {
      const entry =
        byItem.get(item.item_id) ??
        ({
          itemId: item.item_id,
          orderIndex: item.order_index,
          prompt: item.prompt,
          type: item.type,
          responses: 0,
          answered: 0,
          correct: 0,
          rate: null,
        } satisfies QuestionCorrectness);
      entry.responses += 1;
      if (item.answered !== false && item.learner_answer) entry.answered += 1;
      if (item.is_correct === true) entry.correct += 1;
      byItem.set(item.item_id, entry);
    }
  }
  return [...byItem.values()]
    .map((entry) => {
      if (entry.type === "scenario_essay") {
        const scores = essayScores.get(entry.itemId) ?? [];
        const max = scores.reduce((total, score) => total + score.max, 0);
        return {
          ...entry,
          rate: max
            ? round1(
                (scores.reduce((total, score) => total + score.points, 0) /
                  max) *
                  100,
              )
            : null,
        };
      }
      return {
        ...entry,
        rate: entry.responses
          ? round1((entry.correct / entry.responses) * 100)
          : null,
      };
    })
    .sort((a, b) => a.orderIndex - b.orderIndex);
}

export const evaluationStatusLabels: Record<EvaluationStatus, string> = {
  not_required: "Result shown at submission",
  pending: "Evaluate — essays to score",
  evaluated: "Finalize — scoring complete",
  finalized: "Release — finalized",
  released: "Released to learner",
};

export const submissionKindLabels: Record<SubmissionKind, string> = {
  learner: "Submitted by learner",
  auto_deadline: "Auto-submitted at the deadline",
  auto_time_limit: "Auto-submitted when the time limit ended",
};
