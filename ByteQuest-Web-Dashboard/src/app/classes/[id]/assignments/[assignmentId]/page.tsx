import { notFound } from 'next/navigation';
import { DashboardLayout } from '@/components/layout/dashboard-layout';
import { HomeworkWorkspace } from '@/components/classes/HomeworkWorkspace';
import { requireStaffProfile } from '@/lib/auth/server';
import { createServerSupabaseClient } from '@/lib/supabase/server';
import { activitiesClient } from '@/lib/activities/types';
import { createAdminSupabaseClient } from '@/lib/supabase/admin';

export const dynamic = 'force-dynamic';
export default async function HomeworkPage({ params }: { params: Promise<{ id: string; assignmentId: string }> }) {
  const profile = await requireStaffProfile(['instructor']);
  const { id, assignmentId } = await params;
  const client = activitiesClient(await createServerSupabaseClient());
  const [classroom, homework] = await Promise.all([
    client.from('classes').select('id,title,status').eq('id', id).eq('instructor_id', profile.userId).maybeSingle(),
    client.from('homework_assignments').select('*').eq('id', assignmentId).eq('class_id', id).maybeSingle(),
  ]);
  if (classroom.error || homework.error) throw new Error('Assignment could not be loaded.');
  if (!classroom.data || !homework.data) notFound();
  const [memberships, submissions, files] = await Promise.all([
    client.from('class_memberships').select('learner_id,status').eq('class_id', id),
    client.from('homework_submissions').select('*').eq('assignment_id', assignmentId),
    client.from('homework_files').select('*').eq('assignment_id', assignmentId),
  ]);
  if (memberships.error || submissions.error || files.error) throw new Error('Submissions could not be loaded.');
  const learnerIds = [...new Set([...(memberships.data ?? []).map(m => m.learner_id), ...(submissions.data ?? []).map(s => s.learner_id)])];
  // The owned class and homework are authorized above. Restrict this server-only
  // identity read to this class's membership/submission IDs so removed learners
  // retain their names on historical work without broadening profile RLS.
  const { data: profiles, error } = learnerIds.length ? await createAdminSupabaseClient().from('profiles').select('user_id,full_name,email').in('user_id', learnerIds) : { data: [], error: null };
  if (error) throw new Error('Learner names could not be loaded.');
  return <DashboardLayout><div className="mx-auto max-w-5xl"><HomeworkWorkspace homework={homework.data} classTitle={classroom.data.title} active={classroom.data.status === 'active'} files={files.data ?? []} submissions={submissions.data ?? []} learners={learnerIds.map(id => ({ id, name: profiles?.find(p => p.user_id === id)?.full_name ?? 'Learner', email: profiles?.find(p => p.user_id === id)?.email ?? '', active: (memberships.data ?? []).some(m => m.learner_id === id && m.status === 'active') }))} /></div></DashboardLayout>;
}
