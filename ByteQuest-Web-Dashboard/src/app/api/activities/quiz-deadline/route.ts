import { NextResponse } from 'next/server';
import { z } from 'zod';
import { activityActor, activityError, activityWriteOriginAllowed } from '@/lib/activities/server';

export const runtime = 'nodejs';
const schema = z.object({ assignment_id: z.string().uuid(), deadline_at: z.string().datetime({ offset: true }).nullable(), reopen: z.boolean() }).strict();
export async function POST(request: Request) {
  const reply = (body: unknown, status = 200) => NextResponse.json(body, { status, headers: { 'Cache-Control': 'private, no-store' } });
  try {
    if (!activityWriteOriginAllowed(request)) return reply({ error: 'Origin not allowed.' }, 403);
    const actor = await activityActor(request);
    if (!actor || actor.role !== 'instructor') return reply({ error: 'Active Instructor access is required.' }, 403);
    const raw = await request.text(); if (raw.length > 4096) return reply({ error: 'Request too large.' }, 413);
    let input: unknown; try { input = JSON.parse(raw); } catch { return reply({ error: 'Invalid deadline request.' }, 400); }
    const parsed = schema.safeParse(input); if (!parsed.success) return reply({ error: 'Choose a class assignment and valid deadline.' }, 400);
    const { data, error } = await actor.service.rpc('set_quiz_assignment_deadline', { p_actor: actor.id, p_assignment_id: parsed.data.assignment_id, p_deadline: parsed.data.deadline_at, p_reopen: parsed.data.reopen });
    if (error) { const result = activityError(error); return reply({ error: result.error }, result.status); }
    return reply({ assignment: data });
  } catch { return reply({ error: 'The deadline could not be saved. Refresh before retrying.' }, 503); }
}
