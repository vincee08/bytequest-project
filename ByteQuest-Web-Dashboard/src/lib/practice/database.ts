import type { Database, Json } from '@/types/database.generated';
import type { SupabaseClient } from '@supabase/supabase-js';
import { createAdminSupabaseClient } from '@/lib/supabase/admin';
import type { PracticeRunRow, PracticeVerificationPort } from '@/lib/practice/verification';

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
    practice_mission_runs:Table<PracticeRunRow & {learner_id:string;mission_id:string;created_at:string}>;
  };
  Functions:Database['public']['Functions'] & {
    practice_verify_mission:{Args:{p_learner:string;p_mission:string};Returns:undefined};
    practice_record_failed_verification:{Args:{p_learner:string;p_mission:string;p_failure:string};Returns:undefined};
    practice_begin_quiz:{Args:{p_learner:string;p_coc:string;p_id:string;p_questions:Json};Returns:PracticeAttempt};
    practice_submit_quiz:{Args:{p_learner:string;p_attempt:string;p_answers:Json};Returns:PracticeAttempt};
  };
}};
export function practiceServerClient() { return createAdminSupabaseClient() as unknown as SupabaseClient<PracticeDatabase>; }

/** Service-role adapter for the practice verification outcome. */
export function practiceVerificationPort(client: SupabaseClient<PracticeDatabase>): PracticeVerificationPort {
  return {
    async verify(learner, mission) {
      const { error } = await client.rpc('practice_verify_mission', { p_learner: learner, p_mission: mission });
      return error;
    },
    async recordFailure(learner, mission, failure) {
      const { error } = await client.rpc('practice_record_failed_verification', {
        p_learner: learner, p_mission: mission, p_failure: failure,
      });
      return error;
    },
    async latestRun(learner, mission) {
      const { data, error } = await client.from('practice_mission_runs')
        .select('run_number,duration_seconds,invalid_count,correction_count,outcome,failure_code')
        .eq('learner_id', learner).eq('mission_id', mission)
        .order('run_number', { ascending: false }).limit(1).maybeSingle();
      return error || !data ? null : data as PracticeRunRow;
    },
  };
}
