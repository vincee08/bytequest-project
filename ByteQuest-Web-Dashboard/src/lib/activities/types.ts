import type { Database, Json } from '@/types/database.generated';
import type { SupabaseClient } from '@supabase/supabase-js';

export type Homework = {
  id: string; class_id: string; instructor_id: string; title: string;
  instructions: string; status: 'draft' | 'published'; deadline_at: string | null;
  published_at: string | null; revision: number; created_at: string; updated_at: string;
};
export type HomeworkSubmission = {
  id: string; assignment_id: string; learner_id: string; answer: string;
  submitted_at: string; effective_deadline_at: string | null; deadline_revision: number;
  lateness_seconds: number; status: 'submitted' | 'graded'; feedback: string | null;
  score: number | null; graded_at: string | null; graded_by: string | null;
};
export type HomeworkFile = {
  id: string; assignment_id: string; owner_id: string; kind: 'instruction' | 'answer';
  submission_id: string | null; filename: string; object_path: string;
  mime_type: string; size_bytes: number; created_at: string;
};
type Table<T> = { Row: T; Insert: Partial<T>; Update: Partial<T>; Relationships: [] };
export type ActivitiesDatabase = Omit<Database, 'public'> & {
  public: Omit<Database['public'], 'Tables' | 'Functions'> & {
    Tables: Database['public']['Tables'] & {
      homework_assignments: Table<Homework>;
      homework_submissions: Table<HomeworkSubmission>;
      homework_files: Table<HomeworkFile>;
    };
    Functions: Database['public']['Functions'] & {
      manage_homework: { Args: { p_actor: string; p_action: string; p_payload: Json }; Returns: Json };
      set_quiz_assignment_deadline: { Args: { p_actor: string; p_assignment_id: string; p_deadline: string | null; p_reopen: boolean }; Returns: Database['public']['Tables']['quiz_assignments']['Row'] };
    };
  };
};
export function activitiesClient(client: SupabaseClient<Database>) {
  return client as unknown as SupabaseClient<ActivitiesDatabase>;
}
