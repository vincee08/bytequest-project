import { NextResponse } from 'next/server';
import { activityActor, activityError, activityHeaders, activityWriteOriginAllowed } from '@/lib/activities/server';
import {
  evaluationActionSchema, evaluationErrorMessage, homeworkBulkResults, isMissingFunctionError, parseQueueQuery,
  queueFilters, summarizeBulk, type BulkItemResult, type QueueResult,
} from '@/lib/evaluations/requests';
import { evaluationsClient } from '@/lib/evaluations/types';
import type { Json } from '@/types/database.generated';

export const runtime = 'nodejs';

const failure = (error: { code?: string; message?: string }) => evaluationErrorMessage(error) ?? activityError(error);
const itemError = (error: { code?: string; message?: string }) => evaluationErrorMessage(error)?.error ?? 'This item could not be updated. Refresh to check its status.';

export async function OPTIONS(request: Request) { return new NextResponse(null, { status: 204, headers: activityHeaders(request) }); }

/** Evaluation Center queue (instructor: own classes; admin: read-only, all classes). */
export async function GET(request: Request) {
  const reply = (body: unknown, status = 200) => NextResponse.json(body, { status, headers: activityHeaders(request) });
  try {
    const actor = await activityActor(request);
    if (!actor) return reply({ error: 'Sign in to an active instructor or admin account.' }, 401);
    if (!['instructor', 'admin'].includes(actor.role)) return reply({ error: 'The Evaluation Center is available to instructors and admins.' }, 403);
    const query = parseQueueQuery(new URL(request.url).searchParams);
    if (!query.success) return reply({ error: 'Choose a valid stage, class, type, COC, module or learner.' }, 400);
    const { data, error } = await evaluationsClient(actor.client).rpc('get_evaluation_queue', {
      p_stage: query.data.stage, p_filters: queueFilters(query.data) as Json,
    });
    if (error) { const mapped = failure(error); return reply({ error: mapped.error }, mapped.status); }
    const queue = data as unknown as QueueResult;
    // RLS may hide the profile of a learner who has left the class; the items
    // are already authorized, so names are resolved for exactly these IDs.
    const missing = [...new Set(queue.items.filter((item) => !item.learner.name && item.learner.id).map((item) => item.learner.id as string))];
    if (missing.length) {
      const { data: profiles } = await actor.service.from('profiles').select('user_id,full_name').in('user_id', missing);
      const names = new Map((profiles ?? []).map((p) => [p.user_id, p.full_name]));
      for (const item of queue.items) {
        if (!item.learner.name) item.learner.name = (item.learner.id && names.get(item.learner.id)) || 'Learner';
      }
    }
    return reply(queue);
  } catch { return reply({ error: 'The Evaluation Center is temporarily unavailable. Try again.' }, 503); }
}

/** Evaluate / Finalize / Release actions. Bulk actions report one result per item. */
export async function POST(request: Request) {
  const reply = (body: unknown, status = 200) => NextResponse.json(body, { status, headers: activityHeaders(request) });
  try {
    if (!activityWriteOriginAllowed(request)) return reply({ error: 'Origin not allowed.' }, 403);
    const actor = await activityActor(request);
    if (!actor) return reply({ error: 'Sign in to an active instructor account.' }, 401);
    if (actor.role !== 'instructor') return reply({ error: 'Only the class instructor can evaluate, finalize or release results.' }, 403);
    if (Number(request.headers.get('content-length') ?? 0) > 100000) return reply({ error: 'Request too large.' }, 413);
    const raw = await request.text();
    if (raw.length > 100000) return reply({ error: 'Request too large.' }, 413);
    let input: unknown; try { input = JSON.parse(raw); } catch { return reply({ error: 'Invalid evaluation request.' }, 400); }
    const parsed = evaluationActionSchema.safeParse(input);
    if (!parsed.success) return reply({ error: 'Check the item type, action, selected items and evaluation fields.' }, 400);
    const body = parsed.data;
    const client = evaluationsClient(actor.client);
    const service = evaluationsClient(actor.service);

    if (body.kind === 'technical' && body.action === 'record_evaluation') {
      const { data, error } = await service.rpc('record_attempt_evaluation', {
        p_actor: actor.id,
        p_attempt_id: body.attempt_id,
        p_criterion_overrides: { criteria: body.criterion_overrides ?? [], ...(body.outcome ? { outcome: body.outcome } : {}) },
        p_reason: body.reason || null,
        p_note: body.note || null,
      });
      if (error) { const mapped = failure(error); return reply({ error: mapped.error }, mapped.status); }
      return reply({ kind: body.kind, action: body.action, record: data });
    }

    if (body.kind === 'technical') {
      const results: BulkItemResult[] = [];
      if (body.action === 'finalize') {
        // Finalize confirms the recorded evaluation exactly as it stands (the
        // definer RPC runs as the signed-in instructor and rechecks ownership).
        const [attempts, revisions] = await Promise.all([
          client.from('attempts').select('id,status').in('id', body.attempt_ids),
          client.from('score_revisions').select('attempt_id,revision_number,total_value,max_value,percentage,outcome,criterion_values')
            .in('attempt_id', body.attempt_ids).order('revision_number', { ascending: false }),
        ]);
        if (attempts.error || revisions.error) return reply({ error: 'The selected attempts could not be loaded.' }, 503);
        for (const id of body.attempt_ids) {
          const attempt = attempts.data?.find((row) => row.id === id);
          const latest = revisions.data?.find((row) => row.attempt_id === id);
          if (!attempt) { results.push({ id, ok: false, error: 'This attempt is not in one of your classes.' }); continue; }
          if (attempt.status === 'finalized' || attempt.status === 'released') { results.push({ id, ok: true, changed: false, status: attempt.status }); continue; }
          if (!latest) { results.push({ id, ok: false, error: itemError({ message: 'PROVISIONAL_REVISION_REQUIRED' }) }); continue; }
          const { error } = await client.rpc('finalize_attempt', {
            p_attempt_id: id, p_total_value: latest.total_value as number, p_max_value: latest.max_value as number,
            p_percentage: latest.percentage as number, p_outcome: latest.outcome, p_criterion_values: latest.criterion_values,
            p_remarks: body.remarks || undefined,
          });
          results.push(error ? { id, ok: false, error: itemError(error) } : { id, ok: true, changed: true, status: 'finalized' });
        }
      } else {
        for (const id of body.attempt_ids) {
          const { error } = await client.rpc('release_attempt', { p_attempt_id: id, p_release_reason: body.note || undefined });
          results.push(error ? { id, ok: false, error: itemError(error) } : { id, ok: true, status: 'released' });
        }
      }
      return reply({ kind: body.kind, action: body.action, ...summarizeBulk(results) });
    }

    if (body.kind === 'homework') {
      const { kind: _kind, action, ...payload } = body;
      void _kind;
      const { data, error } = await actor.service.rpc('manage_homework', { p_actor: actor.id, p_action: action, p_payload: payload as Json });
      if (error) { const mapped = failure(error); return reply({ error: mapped.error }, mapped.status); }
      if (action === 'grade') return reply({ kind: body.kind, action, record: data });
      return reply({ kind: body.kind, action, ...summarizeBulk(homeworkBulkResults(data)) });
    }

    // Quiz essays: slice A3's service-only manage_quiz_evaluation.
    const results: BulkItemResult[] = [];
    for (const id of body.attempt_ids) {
      const { data, error } = await service.rpc('manage_quiz_evaluation', {
        p_actor: actor.id,
        p_action: body.action,
        p_payload: (body.action === 'finalize' ? { attempt_id: id } : { attempt_ids: [id] }) as Json,
      });
      if (error && isMissingFunctionError(error)) {
        return reply({ error: 'Quiz essay evaluation is not available on this server yet. Technical assessments and homework still work.' }, 501);
      }
      const status = data && typeof data === 'object' && !Array.isArray(data) && typeof (data as { status?: unknown }).status === 'string'
        ? (data as { status: string }).status : body.action === 'finalize' ? 'finalized' : 'released';
      results.push(error ? { id, ok: false, error: itemError(error) } : { id, ok: true, status });
    }
    return reply({ kind: body.kind, action: body.action, ...summarizeBulk(results) });
  } catch { return reply({ error: 'The evaluation could not be saved. Refresh to check its status before retrying.' }, 503); }
}
