import type { Database, Json } from '@/types/database.generated';
import type { SupabaseClient } from '@supabase/supabase-js';
import { createAdminSupabaseClient } from '@/lib/supabase/admin';

export type PracticeAttempt = {
  id:string; learner_id:string; coc_code:string; status:'generating'|'active'|'submitted';
  questions:Json; answers:Json; source:'bank'|'ai'; score:number|null;
  passing_percent:number; passed:boolean|null; created_at:string; submitted_at:string|null;
}
type Table<T> = {Row:T; Insert:Partial<T>; Update:Partial<T>; Relationships:[]};
export type PracticeDatabase = Omit<Database,'public'> & {public:Omit<Database['public'],'Tables'|'Functions'> & {
  Tables:Database['public']['Tables'] & {
    practice_quiz_attempts:Table<PracticeAttempt>;
    practice_mission_completions:Table<{learner_id:string;mission_id:string;contract_version:string;evidence_through_id:number;verified_at:string}>;
    practice_coc_progress:Table<{learner_id:string;coc_code:string;completed_at:string;quiz_attempt_id:string}>;
  };
  Functions:Database['public']['Functions'] & {
    practice_verify_mission:{Args:{p_learner:string;p_mission:string};Returns:undefined};
    practice_begin_quiz:{Args:{p_learner:string;p_coc:string;p_id:string;p_questions:Json};Returns:PracticeAttempt};
    practice_submit_quiz:{Args:{p_learner:string;p_attempt:string;p_answers:Json};Returns:PracticeAttempt};
  };
}};
export function practiceServerClient() { return createAdminSupabaseClient() as unknown as SupabaseClient<PracticeDatabase>; }
