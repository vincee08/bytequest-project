import { z } from "zod";

/**
 * Feature-local contracts for the Objective 6 analytics RPCs
 * (supabase/migrations/20261119170000-20261119170500). Averages and rates are
 * nullable: PostgreSQL returns null, never 0, when there is no data.
 */

const id = z.string().min(1);
const count = z.coerce.number().int().nonnegative();
const metric = z.number().nullable();
const timestamp = z.string().nullable();

export const periodSchema = z.object({ from: z.string(), to: z.string() });

/** Evaluate -> Finalize -> Release -> Released (Evaluation Center mapping). */
export const stageCountsSchema = z.object({ evaluate: count, finalize: count, release: count, released: count });
export type StageCounts = z.infer<typeof stageCountsSchema>;

/** A6 points and level. Engagement is reported apart from competency and scores. */
export const engagementSchema = z.object({
  points: count, points_in_period: count, level: z.number().nullable(), level_title: z.string().nullable(),
  next_level_points: z.number().nullable(), level_progress_percent: z.number().nullable(),
});
export type Engagement = z.infer<typeof engagementSchema>;

/** A practice or simulation step: contract phase id, step number and title. */
export const stepRefSchema = z.object({ id: z.string(), step: z.number().nullable(), title: z.string() });
export type StepRef = z.infer<typeof stepRefSchema>;

export const RELEASE_MODES = ["immediate", "instructor_release"] as const;
export type ReleaseMode = (typeof RELEASE_MODES)[number];
const releaseMode = z.enum(RELEASE_MODES).nullable().optional().transform((value) => value ?? null);

export const filterOptionsSchema = z.object({
  classes: z.array(z.object({ id, title: z.string(), class_code: z.string().nullable() })),
  cocs: z.array(z.object({ code: z.string(), title: z.string() })),
  modules: z.array(z.object({ id, coc_code: z.string(), code: z.string(), title: z.string(), sequence_order: z.number() })),
  topics: z.array(z.object({ id, module_id: id, coc_code: z.string(), title: z.string() })),
  missions: z.array(z.object({ mission_code: z.string(), title: z.string(), coc_code: z.string(), module_id: z.string().nullable(), mission_number: z.number() })),
  quizzes: z.array(z.object({ id, title: z.string(), coc_code: z.string().nullable(), status: z.string() })),
  learners: z.array(z.object({ id, name: z.string(), student_id: z.string().nullable(), class_ids: z.array(z.string()) })),
  generated_at: z.string(),
});
export type FilterOptions = z.infer<typeof filterOptionsSchema>;

export const overviewSchema = z.object({
  period: periodSchema,
  population: z.object({ description: z.string(), enrolled: count, active_in_period: count, completed: count }),
  classes: z.array(z.object({ id, title: z.string(), class_code: z.string().nullable(), enrolled: count })),
  assessments: z.object({
    applicable: z.boolean(), attempts: count, submitted: count, released: count, competent: count,
    not_yet_competent: count, competent_rate: metric, avg_percent: metric, pending_release: count,
  }),
  quizzes: z.object({
    applicable: z.boolean(), submitted: count, scored: count, pending: count, avg_percent: metric,
    eligible: count, completed: count, completion_rate: metric,
  }),
  homework: z.object({
    applicable: z.boolean(), eligible: count, submitted: count, released: count, pending_evaluation: count,
    missing: count, late: count, avg_percent: metric, completion_rate: metric,
  }),
  evaluation: z.object({
    technical: stageCountsSchema, homework: stageCountsSchema, quiz: stageCountsSchema, total: stageCountsSchema,
  }),
  missions: z.object({
    applicable: z.boolean(), verified: count, learners_verified: count, completion_rate: metric, runs: count,
    successful_runs: count, failed_runs: count, avg_duration_seconds: metric,
  }),
  learning_progress: z.object({ applicable: z.boolean(), avg_percent: metric, items_total: count, definition: z.string() }),
  trend: z.array(z.object({
    date: z.string(), assessments: count, quizzes: count, homework: count, practice_runs: count, verified: count,
  })),
  generated_at: z.string(),
});
export type AnalyticsOverview = z.infer<typeof overviewSchema>;

const learnerScoreSchema = z.object({ learner_id: id, name: z.string(), score: z.number() }).nullable();

export const classPerformanceSchema = z.object({
  period: periodSchema,
  classes: z.array(z.object({
    id, title: z.string(), class_code: z.string().nullable(), enrolled: count, active_in_period: count,
    avg_score: metric, quiz_avg: metric, assessment_competent_rate: metric, mission_completion_rate: metric,
    assignment_completion_rate: metric, progress_avg: metric, highest: learnerScoreSchema, lowest: learnerScoreSchema,
  })),
  summary: z.object({
    enrolled: count, active_in_period: count, avg_score: metric, quiz_avg: metric, assessment_competent_rate: metric,
    mission_completion_rate: metric, assignment_completion_rate: metric, progress_avg: metric,
  }),
  generated_at: z.string(),
});
export type ClassPerformance = z.infer<typeof classPerformanceSchema>;

export const LEARNER_STATUSES = ["on_track", "struggling", "falling_behind"] as const;
export type LearnerStatus = (typeof LEARNER_STATUSES)[number];

export const statusReasonSchema = z.object({
  code: z.enum(["inactive", "below_class_median", "quiz_average_low", "not_yet_competent", "repeated_incomplete_runs"]),
  kind: z.enum(["falling_behind", "struggling"]),
  threshold_days: z.number().optional(),
  days_inactive: z.number().nullable().optional(),
  last_activity_at: timestamp.optional(),
  progress_percent: z.number().nullable().optional(),
  class_median: z.number().nullable().optional(),
  class_title: z.string().nullable().optional(),
  quiz_avg: z.number().nullable().optional(),
  threshold: z.number().optional(),
  missions: z.array(z.union([
    z.string(),
    z.object({ mission_code: z.string(), title: z.string().nullable(), incomplete_runs: z.number() }),
  ])).optional(),
});
export type StatusReason = z.infer<typeof statusReasonSchema>;

export const learnerRowSchema = z.object({
  id, name: z.string(), student_id: z.string().nullable(), email: z.string(),
  classes: z.array(z.object({ id, title: z.string() })),
  progress_percent: metric, completed_items: count.nullable(), total_items: count.nullable(),
  performance_score: metric, quiz_avg: metric, quizzes_scored: count,
  assessment: z.object({ released: count, competent: count, pending: count }),
  missions_verified: count, practice_runs: count,
  assignments: z.object({ submitted: count, missing: count, late: count, pending_evaluation: count }),
  last_activity_at: timestamp, status: z.enum(LEARNER_STATUSES), reasons: z.array(statusReasonSchema),
  engagement: engagementSchema,
});
export type LearnerRow = z.infer<typeof learnerRowSchema>;

export const learnerPerformanceSchema = z.object({
  period: periodSchema,
  learners: z.array(learnerRowSchema),
  thresholds: z.object({
    inactivity_days: z.number(), progress_ratio_of_class_median: z.number(), quiz_average_below: z.number(),
    incomplete_runs_on_one_mission: z.number(),
  }),
  counts: z.object({ on_track: count, struggling: count, falling_behind: count }),
  generated_at: z.string(),
});
export type LearnerPerformance = z.infer<typeof learnerPerformanceSchema>;

export const quizAnalyticsSchema = z.object({
  period: periodSchema,
  quizzes: z.array(z.object({
    id, title: z.string(), coc_code: z.string().nullable(), status: z.string(), release_mode: releaseMode,
    participants: count, pending: count,
    eligible: count, completion_rate: metric, average: metric, highest: metric, lowest: metric,
  })),
  quiz: z.object({
    id, title: z.string(), coc_code: z.string().nullable(), status: z.string(), release_mode: releaseMode,
    question_count: count,
  }).nullable().optional().transform((value) => value ?? null),
  participants: count, pending: count, eligible: count, completed: count,
  completion_rate: metric.optional().transform((value) => value ?? null),
  average: metric.optional().transform((value) => value ?? null),
  highest: metric.optional().transform((value) => value ?? null),
  lowest: metric.optional().transform((value) => value ?? null),
  distribution: z.array(z.object({ bucket: z.string(), min: z.number(), max: z.number(), count })),
  per_question: z.array(z.object({
    item_id: id, code: z.string(), prompt: z.string(), type: z.string(), version_number: z.number(),
    answered: count,
    // Objective items: correct answers among released attempts. Essays: null.
    correct: count.nullable(), correct_rate: metric,
    points: z.number().nullable().optional().transform((value) => value ?? null),
    // Essays: mean current essay score (points) and its share of the item points.
    avg_points: metric.optional().transform((value) => value ?? null),
    avg_percent: metric.optional().transform((value) => value ?? null),
  })),
  results: z.array(z.object({
    learner_id: id, name: z.string(), student_id: z.string().nullable(), class_id: z.string().nullable(),
    class_title: z.string().nullable(), score: z.number().nullable(), max_score: z.number().nullable(),
    percent: metric, status: z.enum(["scored", "pending", "not_submitted", "other_class"]),
    stage: z.enum(["evaluate", "finalize", "release", "released"]).nullable().optional().transform((value) => value ?? null),
    submitted_at: timestamp,
  })),
  generated_at: z.string(),
});
export type QuizAnalytics = z.infer<typeof quizAnalyticsSchema>;

/** One practice step across the runs in the period. Missed = not completed or ≥ 1 incorrect attempt. */
export const missionStepSchema = z.object({
  phase_id: z.string(), step: z.number().nullable(), title: z.string(), runs: count, missed: count,
  missed_rate: metric, not_completed: count, avg_incorrect: metric,
});
export type MissionStep = z.infer<typeof missionStepSchema>;

export const missionAnalyticsSchema = z.object({
  period: periodSchema,
  missions: z.array(z.object({
    mission_code: z.string(), title: z.string(), coc_code: z.string(),
    module: z.object({ id, code: z.string(), title: z.string() }).nullable(),
    learners_in_scope: count,
    // In the period:
    learners_attempted: count, learners_verified: count, runs: count, successful_runs: count, failed_runs: count,
    avg_runs_per_learner: metric, avg_duration_seconds: metric, avg_invalid_actions: metric,
    // To date (by the period end):
    learners_verified_to_date: count, completion_rate_to_date: metric,
    // Practice step results in the period (practice_mission_runs.step_results):
    steps: z.array(missionStepSchema),
    most_missed: z.array(missionStepSchema.omit({ not_completed: true })),
  })),
  assessments: z.array(z.object({
    mission_code: z.string(), title: z.string(), coc_code: z.string(), attempts: count, submitted: count,
    released: count, competent: count, not_yet_competent: count, pending: count, avg_percent: metric,
  })),
  generated_at: z.string(),
});
export type MissionAnalytics = z.infer<typeof missionAnalyticsSchema>;

export const CRITERION_SOURCES = ["assessment", "simulation", "homework", "essay"] as const;
export type CriterionSource = (typeof CRITERION_SOURCES)[number];
const criterionSchema = z.object({
  source: z.enum(CRITERION_SOURCES), criterion_id: id, code: z.string(), title: z.string(),
  mission_code: z.string().nullable(), mission_title: z.string().nullable(),
  activity_title: z.string().nullable().optional().transform((value) => value ?? null),
  max: z.number().nullable(), avg: metric, percent: metric,
  evaluated_learners: count, satisfied: count.nullable(), not_satisfied: count.nullable(),
  // Simulation criteria: the steps (contract phases) the criterion checks.
  steps: z.array(stepRefSchema).optional().transform((value) => value ?? []),
});
export type CriterionRow = z.infer<typeof criterionSchema>;

export const criteriaAnalyticsSchema = z.object({
  period: periodSchema,
  criteria: z.array(criterionSchema),
  strongest: z.array(criterionSchema),
  weakest: z.array(criterionSchema),
  generated_at: z.string(),
});
export type CriteriaAnalytics = z.infer<typeof criteriaAnalyticsSchema>;

export const EVALUATION_STAGES = ["evaluate", "finalize", "release", "released"] as const;
export type EvaluationStage = (typeof EVALUATION_STAGES)[number];
export const HOMEWORK_STATUSES = ["submitted", "graded", "finalized", "released", "missing", "open"] as const;
export type HomeworkStatus = (typeof HOMEWORK_STATUSES)[number];

export const learnerProfileSchema = z.object({
  period: periodSchema,
  learner: z.object({ id, name: z.string(), student_id: z.string().nullable(), email: z.string(), account_status: z.string() }),
  classes: z.array(z.object({ id, title: z.string() })),
  status: z.object({
    status: z.enum(LEARNER_STATUSES), reasons: z.array(statusReasonSchema), last_activity_at: timestamp,
    progress_percent: metric, performance_score: metric, quiz_avg: metric, missions_verified: count, practice_runs: count,
    assessment: z.object({ released: count, competent: count, pending: count }),
    assignments: z.object({ submitted: count, missing: count, late: count, pending_evaluation: count }),
  }).nullable(),
  evaluation: stageCountsSchema,
  engagement: engagementSchema.extend({
    achievements: count,
    recent_events: z.array(z.object({
      event_type: z.string(), label: z.string().nullable(), points: z.number(), detail: z.string().nullable(), awarded_at: z.string(),
    })),
  }),
  progress: z.object({
    overall_percent: metric, completed_items: count, total_items: count,
    cocs: z.array(z.object({
      coc_code: z.string(), title: z.string(), percent: metric, completed_items: count, total_items: count,
      coc_quiz_passed_at: timestamp,
      modules: z.array(z.object({
        id, code: z.string(), title: z.string(), sequence_order: z.number(), percent: metric,
        completed_items: count, total_items: count, completed_at: timestamp,
        topics: z.array(z.object({ id, title: z.string(), completed_at: timestamp })),
        missions: z.array(z.object({ mission_code: z.string(), title: z.string(), verified_at: timestamp })),
      })),
    })),
  }),
  quizzes: z.array(z.object({
    quiz_id: id, title: z.string(), class_title: z.string().nullable(), percent: metric,
    correct_count: z.number().nullable(), question_count: z.number().nullable(),
    score: z.number().nullable(), max_score: z.number().nullable(), release_mode: releaseMode,
    stage: z.enum(EVALUATION_STAGES).nullable(),
    status: z.enum(["scored", "pending"]),
    submitted_at: timestamp,
  })),
  missions: z.array(z.object({
    mission_code: z.string(), title: z.string().nullable(), coc_code: z.string(), module_code: z.string().nullable(),
    verified_at: timestamp, runs: count, successful_runs: count, failed_runs: count,
    best_duration_seconds: metric, avg_invalid_actions: metric, last_run_at: timestamp,
    recent_runs: z.array(z.object({
      run_number: z.number(), outcome: z.string(), duration_seconds: z.number().nullable(), invalid_count: z.number(),
      correction_count: z.number(), ended_at: timestamp,
      missed_steps: z.array(z.object({
        phase_id: z.string(), step: z.number().nullable(), title: z.string(), done: z.boolean(), incorrect: z.number(),
      })),
    })),
  })),
  assignments: z.array(z.object({
    homework_id: id, title: z.string(), class_title: z.string().nullable(), deadline_at: timestamp,
    submitted_at: timestamp, late: z.boolean(), status: z.enum(HOMEWORK_STATUSES),
    stage: z.enum(EVALUATION_STAGES).nullable(),
    score: z.number().nullable(), max_score: z.number().nullable(), percent: metric,
  })),
  assessments: z.array(z.object({
    attempt_id: id, mission_code: z.string(), title: z.string(), assignment_title: z.string(),
    class_title: z.string().nullable(), status: z.string(), stage: z.enum(EVALUATION_STAGES).nullable(),
    simulation: z.boolean(),
    submitted_at: timestamp, released_at: timestamp,
    percent: metric, outcome: z.string().nullable(),
    criteria: z.array(z.object({
      criterion_id: id, code: z.string(), title: z.string(), observation: z.string().nullable(),
      score: z.number().nullable(), max: z.number().nullable(), steps: z.array(stepRefSchema),
    })),
  })),
  timeline: z.array(z.object({
    at: z.string(), kind: z.string(), title: z.string().nullable(), detail: z.record(z.unknown()),
  })),
  generated_at: z.string(),
});
export type LearnerProfile = z.infer<typeof learnerProfileSchema>;

export const ANALYTICS_ERROR_CODES = ["ANALYTICS_SCOPE_DENIED", "ANALYTICS_FILTER_INVALID", "ANALYTICS_ACCESS_DENIED"] as const;
export type AnalyticsErrorCode = (typeof ANALYTICS_ERROR_CODES)[number] | "ANALYTICS_UNAVAILABLE";

export function analyticsErrorCode(message: string | null | undefined): AnalyticsErrorCode {
  const match = ANALYTICS_ERROR_CODES.find((code) => message?.includes(code));
  return match ?? "ANALYTICS_UNAVAILABLE";
}
