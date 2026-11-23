import { notFound } from 'next/navigation';
import { DashboardLayout } from '@/components/layout/dashboard-layout';
import { HomeworkWorkspace } from '@/components/classes/HomeworkWorkspace';
import { requireStaffProfile } from '@/lib/auth/server';
import { createServerSupabaseClient } from '@/lib/supabase/server';
import { loadCurriculumOptions, namesFor } from '@/lib/evaluations/server';
import { UNNAMED_LEARNER } from '@/lib/learners/identity';
import { evaluationsClient } from '@/lib/evaluations/types';

export const dynamic = 'force-dynamic';
export default async function HomeworkPage({ params, searchParams }: { params: Promise<{ id: string; assignmentId: string }>; searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const profile = await requireStaffProfile(['instructor', 'admin']);
  const canAct = profile.role === 'instructor';
  const { id, assignmentId } = await params;
  const query = await searchParams;
  const initialSubmission = (Array.isArray(query.submission) ? query.submission[0] : query.submission) ?? null;
  const client = evaluationsClient(await createServerSupabaseClient());
  let classQuery = client.from('classes').select('id,title,status').eq('id', id);
  if (canAct) classQuery = classQuery.eq('instructor_id', profile.userId);
  const [classroom, homework] = await Promise.all([
    classQuery.maybeSingle(),
    client.from('homework_assignments').select('*').eq('id', assignmentId).eq('class_id', id).maybeSingle(),
  ]);
  if (classroom.error || homework.error) throw new Error('Assignment could not be loaded.');
  if (!classroom.data || !homework.data) notFound();
  const h = homework.data;
  const [memberships, submissions, files, options, coc, mission, curriculumModule] = await Promise.all([
    client.from('class_memberships').select('learner_id,status').eq('class_id', id),
    client.from('homework_submissions').select('*').eq('assignment_id', assignmentId),
    client.from('homework_files').select('*').eq('assignment_id', assignmentId),
    h.status === 'draft' && canAct ? loadCurriculumOptions(client).catch(() => null) : Promise.resolve(null),
    h.coc_module_id ? client.from('coc_modules').select('coc_code,title').eq('id', h.coc_module_id).maybeSingle() : Promise.resolve({ data: null }),
    h.mission_code ? client.from('missions').select('mission_code,title').eq('mission_code', h.mission_code).maybeSingle() : Promise.resolve({ data: null }),
    h.module_id ? client.from('curriculum_modules').select('code,title').eq('id', h.module_id).maybeSingle() : Promise.resolve({ data: null }),
  ]);
  if (memberships.error || submissions.error || files.error) throw new Error('Submissions could not be loaded.');
  const rows = submissions.data ?? [];
  const learnerIds = [...new Set([...(memberships.data ?? []).map(m => m.learner_id), ...rows.map(s => s.learner_id)])];
  // The owned class and homework are authorized above. Restrict this server-only
  // identity read to this class's membership/submission/grader IDs so removed
  // learners retain their names on historical work without broadening profile RLS.
  const people = await namesFor([...learnerIds, ...rows.flatMap(s => [s.graded_by, s.finalized_by, s.released_by])]);
  return <DashboardLayout><div className="mx-auto max-w-5xl"><HomeworkWorkspace
    homework={h}
    classTitle={classroom.data.title}
    active={classroom.data.status === 'active'}
    canAct={canAct}
    files={files.data ?? []}
    submissions={rows}
    learners={learnerIds.map(learnerId => ({ id: learnerId, name: people.get(learnerId)?.name ?? UNNAMED_LEARNER, email: people.get(learnerId)?.email ?? '', active: (memberships.data ?? []).some(m => m.learner_id === learnerId && m.status === 'active') }))}
    names={Object.fromEntries([...people.entries()].map(([personId, person]) => [personId, person.name]))}
    options={options}
    curriculumLabels={{
      coc: coc.data ? `${coc.data.coc_code.toUpperCase()} · ${coc.data.title}` : undefined,
      mission: mission.data ? `${mission.data.mission_code.toUpperCase().replace('_', ' ')} · ${mission.data.title}` : undefined,
      module: curriculumModule.data ? `${curriculumModule.data.code} ${curriculumModule.data.title}` : undefined,
    }}
    initialSubmission={initialSubmission}
  /></div></DashboardLayout>;
}
