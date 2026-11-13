import 'server-only';
import { createClient } from '@supabase/supabase-js';
import { getServerProfile } from '@/lib/auth/server';
import { createAdminSupabaseClient } from '@/lib/supabase/admin';
import { createServerSupabaseClient } from '@/lib/supabase/server';
import { activitiesClient } from './types';

/** Cookie-based instructor UI and bearer-based Flutter use the same identity checks. */
export async function activityActor(request: Request) {
  const header = request.headers.get('authorization');
  let id: string;
  let role: string;
  if (header) {
    const token = header.match(/^Bearer (\S+)$/)?.[1];
    if (!token) return null;
    const service = createAdminSupabaseClient(30000);
    const { data, error } = await service.auth.getUser(token);
    if (error || !data.user) return null;
    const { data: profile } = await service.from('profiles').select('role,status').eq('user_id', data.user.id).single();
    if (!profile || profile.status !== 'active') return null;
    id = data.user.id; role = profile.role;
    const client = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!, {
      global: { headers: { Authorization: `Bearer ${token}` } }, auth: { persistSession: false, autoRefreshToken: false },
    });
    return { id, role, client: activitiesClient(client), service: activitiesClient(service) };
  }
  const profile = await getServerProfile();
  if (!profile || profile.status !== 'active') return null;
  id = profile.userId; role = profile.role;
  return { id, role, client: activitiesClient(await createServerSupabaseClient()), service: activitiesClient(createAdminSupabaseClient(30000)) };
}

const localOrigins = new Set(['http://127.0.0.1:3009', 'http://localhost:3009']);
export function activityHeaders(request: Request) {
  const origin = request.headers.get('origin') ?? '';
  const headers: Record<string, string> = { 'Cache-Control': 'private, no-store', Vary: 'Origin' };
  // Mobile native has no browser CORS. Only explicit local preview origins are
  // allowed here; bearer auth is still mandatory for cross-origin requests.
  if (localOrigins.has(origin)) {
    headers['Access-Control-Allow-Origin'] = origin;
    headers['Access-Control-Allow-Headers'] = 'Authorization, Content-Type';
    headers['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS';
  }
  return headers;
}
export function activityWriteOriginAllowed(request: Request) {
  const origin = request.headers.get('origin');
  if (!origin) return true;
  if (request.headers.has('authorization') && localOrigins.has(origin)) return true;
  const target = new URL(request.url);
  // localhost and 127.0.0.1 are equivalent only for the local dashboard port.
  return origin === target.origin || (target.port === '3008' && ['http://localhost:3008','http://127.0.0.1:3008'].includes(origin));
}
export function activityError(error: { code?: string; message?: string }) {
  if (error.code === '42501') return { error: 'This action is not allowed for your account or class.', status: 403 };
  if (error.code === 'P0002') return { error: 'The assignment or submission was not found.', status: 404 };
  if (error.message?.includes('USE_REOPEN')) return { error: 'Use Reopen Quiz and choose a new future deadline.', status: 409 };
  if (error.message?.includes('FUTURE_DEADLINE') || error.message?.includes('EXPIRED_QUIZ')) return { error: 'Reopening requires an expired quiz and a new future deadline.', status: 422 };
  if (error.code === '55000') return { error: 'The record has changed. Refresh before editing.', status: 409 };
  if (['22023','23514','22P02','22007','22008'].includes(error.code ?? '')) return { error: 'Check the answer, files, score, and deadline, then retry.', status: 422 };
  return { error: 'The activity could not be saved. Refresh to check its status before retrying.', status: 503 };
}
