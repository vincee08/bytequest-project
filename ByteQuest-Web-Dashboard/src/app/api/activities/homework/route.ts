import { NextResponse } from 'next/server';
import { z } from 'zod';
import { activityActor, activityError, activityHeaders, activityWriteOriginAllowed } from '@/lib/activities/server';
import type { Json } from '@/types/database.generated';

export const runtime = 'nodejs';
const uuid = z.string().uuid();
const deadline = z.string().datetime({ offset: true }).nullable();
const fields = { title: z.string().trim().min(2).max(300), instructions: z.string().trim().min(1).max(20000), deadline_at: deadline };
const schema = z.discriminatedUnion('action', [
  z.object({ action: z.literal('create'), class_id: uuid, ...fields }).strict(),
  z.object({ action: z.literal('edit'), assignment_id: uuid, ...fields }).strict(),
  z.object({ action: z.literal('publish'), assignment_id: uuid }).strict(),
  z.object({ action: z.literal('deadline'), assignment_id: uuid, deadline_at: deadline }).strict(),
  z.object({ action: z.literal('submit'), assignment_id: uuid, answer: z.string().trim().max(20000), file_ids: z.array(uuid).max(5) }).strict(),
  z.object({ action: z.literal('grade'), assignment_id: uuid, submission_id: uuid, feedback: z.string().trim().max(10000), score: z.number().min(0).max(100).nullable() }).strict(),
]);
export async function OPTIONS(request: Request) { return new NextResponse(null, { status: 204, headers: activityHeaders(request) }); }
export async function GET(request: Request) {
  const reply = (body: unknown, status = 200) => NextResponse.json(body, { status, headers: activityHeaders(request) });
  try {
    const actor = await activityActor(request);
    if (!actor || !['learner','instructor'].includes(actor.role)) return reply({ error: 'Active Learner or Instructor access is required.' }, 401);
    const query = new URL(request.url).searchParams;
    const classId = query.get('class'); const id = query.get('id');
    if ((classId && !uuid.safeParse(classId).success) || (id && !uuid.safeParse(id).success)) return reply({ error: 'Choose a valid assignment or class.' }, 400);
    let assignments = actor.client.from('homework_assignments').select('*').order('created_at', { ascending: false });
    if (classId) assignments = assignments.eq('class_id', classId);
    if (id) assignments = assignments.eq('id', id);
    const { data: homework, error } = await assignments;
    if (error) return reply({ error: 'Homework could not be loaded. Try again.' }, 503);
    if (id && !homework?.length) return reply({ error: 'Assignment not found.' }, 404);
    const ids = (homework ?? []).map(h => h.id);
    const classIds = [...new Set((homework ?? []).map(h => h.class_id))];
    const [submissions, files, classes] = await Promise.all([
      ids.length ? actor.client.from('homework_submissions').select('*').in('assignment_id', ids) : { data: [], error: null },
      ids.length ? actor.client.from('homework_files').select('*').in('assignment_id', ids) : { data: [], error: null },
      classIds.length ? actor.client.from('classes').select('id,title').in('id', classIds) : { data: [], error: null },
    ]);
    if (submissions.error || files.error || classes.error) return reply({ error: 'Homework details could not be loaded.' }, 503);
    return reply({ homework, submissions: submissions.data, files: files.data, classes: classes.data, server_now: new Date().toISOString() });
  } catch { return reply({ error: 'Homework service temporarily unavailable.' }, 503); }
}
export async function POST(request: Request) {
  const reply = (body: unknown, status = 200) => NextResponse.json(body, { status, headers: activityHeaders(request) });
  try {
    if (!activityWriteOriginAllowed(request)) return reply({ error: 'Origin not allowed.' }, 403);
    const actor = await activityActor(request);
    if (!actor || !['learner','instructor'].includes(actor.role)) return reply({ error: 'Sign in to an active account.' }, 401);
    if (Number(request.headers.get('content-length') ?? 0) > 100000) return reply({ error: 'Request too large.' }, 413);
    const raw = await request.text();
    if (raw.length > 100000) return reply({ error: 'Request too large.' }, 413);
    let input: unknown; try { input = JSON.parse(raw); } catch { return reply({ error: 'Invalid homework request.' }, 400); }
    const parsed = schema.safeParse(input);
    if (!parsed.success) return reply({ error: 'Check the homework fields, deadline, or score.' }, 400);
    if ((parsed.data.action === 'submit') !== (actor.role === 'learner')) return reply({ error: 'This action is not allowed for your role.' }, 403);
    const { action, ...payload } = parsed.data;
    const { data, error } = await actor.service.rpc('manage_homework', { p_actor: actor.id, p_action: action, p_payload: payload as Json });
    if (error) { const result = activityError(error); return reply({ error: result.error }, result.status); }
    return reply({ record: data });
  } catch { return reply({ error: 'Homework could not be saved. Refresh to check before retrying.' }, 503); }
}
