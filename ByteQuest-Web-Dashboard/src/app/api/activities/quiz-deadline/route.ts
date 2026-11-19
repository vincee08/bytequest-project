import { NextResponse } from 'next/server';
import type { SupabaseClient } from '@supabase/supabase-js';
import { z } from 'zod';
import { activityActor, activityError, activityWriteOriginAllowed } from '@/lib/activities/server';

export const runtime = 'nodejs';
// close_now (re-defense A3): set this class deadline to the server time; attempts in progress are submitted automatically.
const schema = z.object({ assignment_id: z.string().uuid(), deadline_at: z.string().datetime({ offset: true }).nullable(), reopen: z.boolean(), close_now: z.boolean().optional() }).strict();
export async function POST(request: Request) {
  const reply = (body: unknown, status = 200) => NextResponse.json(body, { status, headers: { 'Cache-Control': 'private, no-store' } });
  try {
    if (!activityWriteOriginAllowed(request)) return reply({ error: 'Origin not allowed.' }, 403);
    const actor = await activityActor(request);
    if (!actor || actor.role !== 'instructor') return reply({ error: 'Active Instructor access is required.' }, 403);
    const raw = await request.text(); if (raw.length > 4096) return reply({ error: 'Request too large.' }, 413);
    let input: unknown; try { input = JSON.parse(raw); } catch { return reply({ error: 'Invalid deadline request.' }, 400); }
    const parsed = schema.safeParse(input); if (!parsed.success) return reply({ error: 'Choose a class assignment and valid deadline.' }, 400);
    const service = actor.service as unknown as SupabaseClient;
    const { data, error } = await service.rpc('set_quiz_assignment_deadline', { p_actor: actor.id, p_assignment_id: parsed.data.assignment_id, p_deadline: parsed.data.deadline_at, p_reopen: parsed.data.reopen, p_close_now: parsed.data.close_now ?? false });
    if (error) {
      if (error.message?.includes('QUIZ_ALREADY_CLOSED')) return reply({ error: 'This class quiz is already closed.' }, 409);
      if (error.message?.includes('QUIZ_NOT_YET_OPEN')) return reply({ error: 'This class quiz has not opened yet.' }, 409);
      const result = activityError(error); return reply({ error: result.error }, result.status);
    }
    return reply({ assignment: data });
  } catch { return reply({ error: 'The deadline could not be saved. Refresh before retrying.' }, 503); }
}
