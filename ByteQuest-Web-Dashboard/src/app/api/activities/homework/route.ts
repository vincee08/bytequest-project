import { NextResponse } from 'next/server';
import { z } from 'zod';
import { activityActor, activityError, activityHeaders, activityWriteOriginAllowed } from '@/lib/activities/server';
import { homeworkActionSchema, homeworkErrorMessage, learnerRecordView, learnerSubmissionView, staffSubmissionView } from '@/lib/evaluations/homework';
import { evaluationsClient } from '@/lib/evaluations/types';
import type { Json } from '@/types/database.generated';

export const runtime = 'nodejs';
const uuid = z.string().uuid();
export async function OPTIONS(request: Request) { return new NextResponse(null, { status: 204, headers: activityHeaders(request) }); }
export async function GET(request: Request) {
  const reply = (body: unknown, status = 200) => NextResponse.json(body, { status, headers: activityHeaders(request) });
  try {
    const actor = await activityActor(request);
    if (!actor || !['learner','instructor'].includes(actor.role)) return reply({ error: 'Active Learner or Instructor access is required.' }, 401);
    const client = evaluationsClient(actor.client);
    const service = evaluationsClient(actor.service);
    const query = new URL(request.url).searchParams;
    const classId = query.get('class'); const id = query.get('id');
    if ((classId && !uuid.safeParse(classId).success) || (id && !uuid.safeParse(id).success)) return reply({ error: 'Choose a valid assignment or class.' }, 400);
    let assignments = client.from('homework_assignments').select('*').order('created_at', { ascending: false });
    if (classId) assignments = assignments.eq('class_id', classId);
    if (id) assignments = assignments.eq('id', id);
    const { data: homework, error } = await assignments;
    if (error) return reply({ error: 'Homework could not be loaded. Try again.' }, 503);
    if (id && !homework?.length) return reply({ error: 'Assignment not found.' }, 404);
    const rows = homework ?? [];
    const ids = rows.map(h => h.id);
    const classIds = [...new Set(rows.map(h => h.class_id))];
    const cocIds = [...new Set(rows.flatMap(h => h.coc_module_id ? [h.coc_module_id] : []))];
    const moduleIds = [...new Set(rows.flatMap(h => h.module_id ? [h.module_id] : []))];
    const missionCodes = [...new Set(rows.flatMap(h => h.mission_code ? [h.mission_code] : []))];
    const none = { data: [], error: null };
    // Assignments above are RLS-scoped. A learner's own submission is read with
    // the service client (RLS hides an in-evaluation grade from learner
    // clients) and redacted until release.
    const [submissions, files, classes, cocs, modules, missions] = await Promise.all([
      !ids.length ? none : actor.role === 'learner'
        ? service.from('homework_submissions').select('*').in('assignment_id', ids).eq('learner_id', actor.id)
        : client.from('homework_submissions').select('*').in('assignment_id', ids),
      ids.length ? client.from('homework_files').select('*').in('assignment_id', ids) : none,
      classIds.length ? client.from('classes').select('id,title').in('id', classIds) : none,
      cocIds.length ? client.from('coc_modules').select('id,coc_code,title').in('id', cocIds) : none,
      moduleIds.length ? client.from('curriculum_modules').select('id,code,title').in('id', moduleIds) : none,
      missionCodes.length ? client.from('missions').select('mission_code,title').in('mission_code', missionCodes) : none,
    ]);
    if (submissions.error || files.error || classes.error || cocs.error || modules.error || missions.error) return reply({ error: 'Homework details could not be loaded.' }, 503);
    const cocById = new Map((cocs.data ?? []).map(c => [c.id, c]));
    const moduleById = new Map((modules.data ?? []).map(m => [m.id, m]));
    const missionByCode = new Map((missions.data ?? []).map(m => [m.mission_code, m]));
    return reply({
      homework: rows.map(h => ({
        ...h,
        coc_code: h.coc_module_id ? cocById.get(h.coc_module_id)?.coc_code ?? null : null,
        coc_title: h.coc_module_id ? cocById.get(h.coc_module_id)?.title ?? null : null,
        module_code: h.module_id ? moduleById.get(h.module_id)?.code ?? null : null,
        module_title: h.module_id ? moduleById.get(h.module_id)?.title ?? null : null,
        mission_title: h.mission_code ? missionByCode.get(h.mission_code)?.title ?? null : null,
      })),
      submissions: (submissions.data ?? []).map(s => actor.role === 'learner' ? learnerSubmissionView(s) : staffSubmissionView(s)),
      files: files.data, classes: classes.data, server_now: new Date().toISOString(),
    });
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
    const parsed = homeworkActionSchema.safeParse(input);
    if (!parsed.success) return reply({ error: 'Check the homework fields, criteria, deadline, or score.' }, 400);
    if ((parsed.data.action === 'submit') !== (actor.role === 'learner')) return reply({ error: 'This action is not allowed for your role.' }, 403);
    const { action, ...payload } = parsed.data;
    const { data, error } = await actor.service.rpc('manage_homework', { p_actor: actor.id, p_action: action, p_payload: payload as Json });
    if (error) { const result = homeworkErrorMessage(error) ?? activityError(error); return reply({ error: result.error }, result.status); }
    // Learner replies (submit and its idempotent retries) never carry an
    // unreleased grade, whatever the RPC returns.
    return reply({ record: actor.role === 'learner' ? learnerRecordView(data) : data });
  } catch { return reply({ error: 'Homework could not be saved. Refresh to check before retrying.' }, 503); }
}
