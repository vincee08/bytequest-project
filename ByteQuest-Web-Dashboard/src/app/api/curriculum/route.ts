import { NextResponse } from 'next/server';
import type { Json } from '@/types/database.generated';
import { activityActor, activityHeaders, activityWriteOriginAllowed } from '@/lib/activities/server';
import { handleStaffCurriculumPost, MAX_CURRICULUM_REQUEST_BYTES } from '@/lib/curriculum/handlers';
import { loadCurriculumWorkspace } from '@/lib/curriculum/server';
import { curriculumClient } from '@/lib/curriculum/types';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function OPTIONS(request: Request) {
  return new NextResponse(null, { status: 204, headers: activityHeaders(request) });
}

/** Staff curriculum workspace: modules, official outcomes, topics, revisions and history. */
export async function GET(request: Request) {
  const reply = (body: unknown, status = 200) => NextResponse.json(body, { status, headers: activityHeaders(request) });
  try {
    const actor = await activityActor(request);
    if (!actor) return reply({ error: 'Sign in with an active staff account.' }, 401);
    if (actor.role !== 'admin' && actor.role !== 'instructor') return reply({ error: 'Curriculum authoring is available to instructors and admins.' }, 403);
    return reply(await loadCurriculumWorkspace(actor));
  } catch {
    return reply({ error: 'The curriculum could not be loaded. Try again.' }, 503);
  }
}

/** Workflow actions; manage_curriculum_content re-checks every role and transition. */
export async function POST(request: Request) {
  const reply = (body: unknown, status = 200) => NextResponse.json(body, { status, headers: activityHeaders(request) });
  try {
    if (!activityWriteOriginAllowed(request)) return reply({ error: 'Origin not allowed.' }, 403);
    if (Number(request.headers.get('content-length') ?? 0) > MAX_CURRICULUM_REQUEST_BYTES) return reply({ error: 'Request too large.' }, 413);
    const actor = await activityActor(request);
    // Answer 401/403 before reading a (possibly chunked) body.
    const raw = actor?.role === 'admin' || actor?.role === 'instructor' ? await request.text() : '';
    const result = await handleStaffCurriculumPost(actor, raw, async (action, payload) => {
      const { data, error } = await curriculumClient(actor!.service).rpc('manage_curriculum_content', {
        p_actor: actor!.id, p_action: action, p_payload: payload as Json,
      });
      return { data, error };
    });
    return reply(result.body, result.status);
  } catch {
    return reply({ error: 'The curriculum change could not be saved. Refresh to check its status before retrying.' }, 503);
  }
}
