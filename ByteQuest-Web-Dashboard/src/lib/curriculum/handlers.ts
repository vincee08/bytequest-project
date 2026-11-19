import { adminOnlyActions, curriculumError, learnerActionSchema, staffActionSchema } from './workflow';

/**
 * Route-independent request handling for the curriculum API, with the
 * database calls injected so validation and authorisation can be unit tested.
 * The service-only database function re-checks every role and transition.
 */
export type RpcError = { code?: string; message?: string } | null;
export type CurriculumRpc = (action: string, payload: Record<string, unknown>) => Promise<{ data: unknown; error: RpcError }>;
export type HandlerResult = { status: number; body: Record<string, unknown> };

export const MAX_CURRICULUM_REQUEST_BYTES = 100_000;

function parseJson(raw: string): { ok: true; value: unknown } | { ok: false } {
  try {
    return { ok: true, value: JSON.parse(raw) };
  } catch {
    return { ok: false };
  }
}

export async function handleStaffCurriculumPost(
  actor: { role: string } | null,
  raw: string,
  rpc: CurriculumRpc,
): Promise<HandlerResult> {
  if (!actor) return { status: 401, body: { error: 'Sign in with an active staff account.' } };
  if (actor.role !== 'admin' && actor.role !== 'instructor') {
    return { status: 403, body: { error: 'Curriculum authoring is available to instructors and admins.' } };
  }
  if (raw.length > MAX_CURRICULUM_REQUEST_BYTES) return { status: 413, body: { error: 'Request too large.' } };
  const json = parseJson(raw);
  if (!json.ok) return { status: 400, body: { error: 'Invalid curriculum request.' } };
  const parsed = staffActionSchema.safeParse(json.value);
  if (!parsed.success) {
    return { status: 400, body: { error: parsed.error.issues[0]?.message ?? 'Check the curriculum fields.' } };
  }
  const { action, ...payload } = parsed.data;
  if (adminOnlyActions.has(action) && actor.role !== 'admin') {
    return { status: 403, body: { error: 'Only an admin can evaluate, approve, publish, unpublish or archive content.' } };
  }
  const { data, error } = await rpc(action, payload);
  if (error) {
    const mapped = curriculumError(error);
    return { status: mapped.status, body: { error: mapped.error } };
  }
  return { status: 200, body: { record: data } };
}

export async function handleLearnerCurriculumPost(
  actor: { role: string } | null,
  raw: string,
  deps: { rpc: CurriculumRpc; projection: () => Promise<{ data: unknown; error: RpcError }> },
): Promise<HandlerResult> {
  if (!actor) return { status: 401, body: { error: 'Sign in with an active learner account.' } };
  if (actor.role !== 'learner') return { status: 403, body: { error: 'Only learners record lesson completion.' } };
  if (raw.length > 4096) return { status: 413, body: { error: 'Request too large.' } };
  const json = parseJson(raw);
  if (!json.ok) return { status: 400, body: { error: 'Invalid lesson request.' } };
  const parsed = learnerActionSchema.safeParse(json.value);
  if (!parsed.success) return { status: 400, body: { error: 'Choose a valid lesson.' } };
  const { data, error } = await deps.rpc('complete_topic', { topic_id: parsed.data.topic_id });
  if (error) {
    const mapped = curriculumError(error);
    return { status: mapped.status, body: { error: mapped.error } };
  }
  // Return the refreshed projection so the app updates locks in one round trip.
  const projection = await deps.projection();
  return { status: 200, body: { record: data, curriculum: projection.error ? null : projection.data } };
}

export async function handleLearnerCurriculumGet(
  actor: { role: string } | null,
  projection: () => Promise<{ data: unknown; error: RpcError }>,
): Promise<HandlerResult> {
  if (!actor) return { status: 401, body: { error: 'Sign in with an active learner account.' } };
  if (actor.role !== 'learner') return { status: 403, body: { error: 'The learning path is available to learners.' } };
  const { data, error } = await projection();
  if (error) {
    const mapped = curriculumError(error);
    return { status: mapped.status, body: { error: mapped.status === 503 ? 'The learning path could not be loaded. Try again.' : mapped.error } };
  }
  return { status: 200, body: { curriculum: data } };
}
