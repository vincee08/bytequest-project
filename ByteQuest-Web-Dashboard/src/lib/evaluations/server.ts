import 'server-only';
import type { SupabaseClient } from '@supabase/supabase-js';
import { createAdminSupabaseClient } from '@/lib/supabase/admin';
import { learnerDisplayName } from '@/lib/learners/identity';
import type { CurriculumOptions, EvaluationsDatabase } from './types';

/** COC -> mission -> module catalog (read through the caller's RLS). */
export async function loadCurriculumOptions(client: SupabaseClient<EvaluationsDatabase>): Promise<CurriculumOptions> {
  const [cocs, missions, modules, links] = await Promise.all([
    client.from('coc_modules').select('id,coc_code,title').order('coc_code'),
    client.from('missions').select('mission_code,title,coc_id').order('mission_code'),
    client.from('curriculum_modules').select('id,coc_module_id,coc_code,code,title,sequence_order').order('coc_code').order('sequence_order'),
    client.from('mission_curriculum_links').select('mission_code,module_id'),
  ]);
  if (cocs.error || missions.error || modules.error || links.error) throw new Error('The COC and mission catalog could not be loaded.');
  return { cocs: cocs.data ?? [], missions: missions.data ?? [], modules: modules.data ?? [], links: links.data ?? [] };
}

/**
 * Names for learner/grader IDs that already appear in authorized rows. RLS
 * hides profiles of learners who left a class; history keeps their names.
 */
export async function namesFor(ids: (string | null | undefined)[]) {
  const unique = [...new Set(ids.filter((id): id is string => Boolean(id)))];
  if (!unique.length) return new Map<string, { name: string; email: string }>();
  const { data, error } = await createAdminSupabaseClient().from('profiles').select('user_id,full_name,email').in('user_id', unique);
  if (error) throw new Error('Names could not be loaded.');
  return new Map((data ?? []).map((p) => [p.user_id, { name: learnerDisplayName(p), email: p.email ?? '' }]));
}
