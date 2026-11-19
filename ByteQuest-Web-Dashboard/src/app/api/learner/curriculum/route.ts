import { NextResponse } from 'next/server';
import type { Json } from '@/types/database.generated';
import { activityActor, activityHeaders, activityWriteOriginAllowed } from '@/lib/activities/server';
import { handleLearnerCurriculumGet, handleLearnerCurriculumPost } from '@/lib/curriculum/handlers';
import { curriculumClient } from '@/lib/curriculum/types';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function OPTIONS(request: Request) {
  return new NextResponse(null, { status: 204, headers: activityHeaders(request) });
}

/** Learner projection, read with the learner's own token (RLS applies). */
export async function GET(request: Request) {
  const reply = (body: unknown, status = 200) => NextResponse.json(body, { status, headers: activityHeaders(request) });
  try {
    const actor = await activityActor(request);
    const result = await handleLearnerCurriculumGet(actor, async () => {
      const { data, error } = await curriculumClient(actor!.client).rpc('get_learner_curriculum');
      return { data, error };
    });
    return reply(result.body, result.status);
  } catch {
    return reply({ error: 'The learning path could not be loaded. Try again.' }, 503);
  }
}

/** { action: 'complete_topic', topic_id } — the module must be unlocked (server-checked). */
export async function POST(request: Request) {
  const reply = (body: unknown, status = 200) => NextResponse.json(body, { status, headers: activityHeaders(request) });
  try {
    if (!activityWriteOriginAllowed(request)) return reply({ error: 'Origin not allowed.' }, 403);
    if (Number(request.headers.get('content-length') ?? 0) > 4096) return reply({ error: 'Request too large.' }, 413);
    const actor = await activityActor(request);
    const raw = await request.text();
    const result = await handleLearnerCurriculumPost(actor, raw, {
      rpc: async (action, payload) => {
        const { data, error } = await curriculumClient(actor!.service).rpc('manage_curriculum_content', {
          p_actor: actor!.id, p_action: action, p_payload: payload as Json,
        });
        return { data, error };
      },
      projection: async () => {
        const { data, error } = await curriculumClient(actor!.client).rpc('get_learner_curriculum');
        return { data, error };
      },
    });
    return reply(result.body, result.status);
  } catch {
    return reply({ error: 'The lesson could not be marked complete. Try again.' }, 503);
  }
}
