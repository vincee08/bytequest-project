import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/types/database.generated";

/**
 * The re-defense quiz schema (curriculum links, settings, essays, evaluation)
 * is newer than the generated database types. Queries that touch it use this
 * untyped view of the same authenticated client and cast rows to the
 * feature-local types below. RLS and RPC authorization are unchanged.
 */
export function quizDb(client: SupabaseClient<Database>) {
  return client as unknown as SupabaseClient;
}

export type QuizItemType =
  | "multiple_choice"
  | "true_false"
  | "identification"
  | "scenario_based"
  | "scenario_essay";
export type QuizType = "pre_assessment" | "formative" | "summative";
export type QuizDifficulty = "foundation" | "intermediate" | "advanced";
export type ResultReleaseMode = "immediate" | "instructor_release";
export type EvaluationStatus =
  | "not_required"
  | "pending"
  | "evaluated"
  | "finalized"
  | "released";
export type SubmissionKind = "learner" | "auto_deadline" | "auto_time_limit";

export interface RubricCriterion {
  id: string;
  criterion: string;
  description: string;
  max_points: number;
}

export interface CurriculumModuleRow {
  id: string;
  coc_module_id: string;
  coc_code: string;
  code: string;
  title: string;
  sequence_order: number;
}
export interface LearningOutcomeRow {
  id: string;
  module_id: string;
  code: string;
  statement: string;
  sequence_order: number;
}
export interface CurriculumTopicRow {
  id: string;
  module_id: string;
  sequence_order: number;
  archived_at: string | null;
}
export interface TopicRevisionRow {
  topic_id: string;
  revision_number: number;
  title: string;
  summary: string | null;
  body_markdown: string;
  status: string;
}

export interface QuizCurriculumRow {
  id: string;
  focus: string | null;
  quiz_type: QuizType | null;
  difficulty: QuizDifficulty | null;
  topic_id: string | null;
}
export interface QuizModuleRow {
  quiz_id: string;
  module_id: string;
}
export interface QuizOutcomeRow {
  quiz_id: string;
  outcome_id: string;
}
export interface QuizVersionSettingsRow {
  id: string;
  time_limit_minutes: number | null;
  result_release_mode: ResultReleaseMode;
}
export interface QuizItemExtraRow {
  id: string;
  scenario: string | null;
  rubric: RubricCriterion[] | null;
  points: number;
  min_words: number | null;
  max_words: number | null;
}

export interface QuizItemResultJson {
  item_id: string;
  code?: string;
  type: QuizItemType;
  prompt: string;
  learner_answer: string | null;
  answered?: boolean;
  is_correct: boolean | null;
  points?: number;
  points_awarded?: number | null;
  order_index: number;
}
export interface QuizAttemptRow {
  id: string;
  learner_id: string;
  class_id: string;
  quiz_assignment_id: string;
  quiz_version_id: string;
  status: "in_progress" | "submitted" | "completed";
  started_at: string;
  submitted_at: string | null;
  completed_at: string | null;
  time_limit_minutes: number | null;
  submission_kind: SubmissionKind;
  evaluation_status: EvaluationStatus;
}
export interface QuizResultRow {
  quiz_attempt_id: string;
  correct_count: number;
  question_count: number;
  objective_points: number | null;
  max_points: number | null;
  item_results: QuizItemResultJson[];
}
export interface QuizAnswerRow {
  quiz_attempt_id: string;
  quiz_item_id: string;
  answer: string;
  is_correct: boolean | null;
}
export interface QuizEssayScoreRow {
  id: string;
  attempt_id: string;
  item_id: string;
  criterion_scores: Record<string, number>;
  total: number;
  feedback: string | null;
  evaluated_by: string;
  evaluated_at: string;
}
export interface QuizFinalizationRow {
  attempt_id: string;
  objective_points: number;
  essay_points: number;
  total_points: number;
  max_points: number;
  percent: number;
  finalized_at: string;
  released_at: string | null;
}
