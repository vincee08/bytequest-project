import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database, Json } from '@/types/database.generated';
import type { ActivitiesDatabase, Homework, HomeworkSubmission } from '@/lib/activities/types';

/**
 * Feature-local types for the Evaluation Center and homework workflow
 * (Objective 4). The generated database types predate these columns and
 * tables; they are regenerated at integration.
 */
export type HomeworkStatus = 'submitted' | 'graded' | 'finalized' | 'released';
export type HomeworkCriterion = { id: string; criterion: string; description: string | null; max_points: number };
export type HomeworkRecord = Homework & {
  coc_module_id: string | null; module_id: string | null; mission_code: string | null;
  learning_objectives: string[]; criteria: HomeworkCriterion[]; max_score: number;
  submission_requirements: string | null;
  submission_format: HomeworkSubmissionFormat; required_file_count: number; accepted_file_types: HomeworkFileTypes;
};
/** What a learner submits; the server enforces it (manage_homework). */
export type HomeworkSubmissionFormat = 'answer_or_file' | 'answer' | 'file' | 'answer_and_file';
export type HomeworkFileTypes = 'any' | 'image';
export type HomeworkSubmissionRecord = Omit<HomeworkSubmission, 'status'> & {
  status: HomeworkStatus; criterion_scores: Record<string, number> | null;
  finalized_by: string | null; finalized_at: string | null;
  released_by: string | null; released_at: string | null;
};
export type CurriculumModuleRow = {
  id: string; coc_module_id: string; coc_code: string; code: string; title: string;
  element_title: string | null; sequence_order: number; source_reference: string; created_at: string;
};
export type MissionCurriculumLinkRow = { mission_code: string; module_id: string; pc_codes: string[]; sequence_order: number };
export type EvaluationOutcome = Database['public']['Enums']['evaluation_outcome'];
export type AttemptEvaluationRecordRow = {
  attempt_id: string; recorded_by: string; recorded_at: string; outcome: EvaluationOutcome;
  criterion_overrides: Json; adjustment_revision_id: string | null; note: string | null;
};

/** COC -> mission -> module catalog used by homework authoring and filters. */
export type CurriculumOptions = {
  cocs: { id: string; coc_code: string; title: string }[];
  missions: { mission_code: string; title: string; coc_id: string }[];
  modules: { id: string; coc_module_id: string; coc_code: string; code: string; title: string; sequence_order: number }[];
  links: { mission_code: string; module_id: string }[];
};

type Table<T> = { Row: T; Insert: Partial<T>; Update: Partial<T>; Relationships: [] };
type ActivitiesPublic = ActivitiesDatabase['public'];
export type EvaluationsDatabase = Omit<ActivitiesDatabase, 'public'> & {
  public: Omit<ActivitiesPublic, 'Tables' | 'Functions'> & {
    Tables: Omit<ActivitiesPublic['Tables'], 'homework_assignments' | 'homework_submissions'> & {
      homework_assignments: Table<HomeworkRecord>;
      homework_submissions: Table<HomeworkSubmissionRecord>;
      curriculum_modules: Table<CurriculumModuleRow>;
      mission_curriculum_links: Table<MissionCurriculumLinkRow>;
      attempt_evaluation_records: Table<AttemptEvaluationRecordRow>;
    };
    Functions: ActivitiesPublic['Functions'] & {
      record_attempt_evaluation: {
        Args: { p_actor: string; p_attempt_id: string; p_criterion_overrides: Json; p_reason: string | null; p_note: string | null };
        Returns: Json;
      };
      get_evaluation_queue: { Args: { p_stage: string; p_filters: Json }; Returns: Json };
      manage_quiz_evaluation: { Args: { p_actor: string; p_action: string; p_payload: Json }; Returns: Json };
    };
  };
};

export function evaluationsClient(client: SupabaseClient<Database> | SupabaseClient<ActivitiesDatabase>) {
  return client as unknown as SupabaseClient<EvaluationsDatabase>;
}
