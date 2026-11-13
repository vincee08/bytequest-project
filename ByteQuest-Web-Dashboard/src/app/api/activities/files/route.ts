import { createHash } from 'node:crypto';
import { NextResponse } from 'next/server';
import { z } from 'zod';
import { activityActor, activityError, activityHeaders, activityWriteOriginAllowed } from '@/lib/activities/server';
import { isAllowedLearningResourceMime, matchesResourceContent } from '@/lib/resources/policy';
import { readResourceForm, UploadSizeError } from '@/lib/resources/upload-form';

export const runtime = 'nodejs';
const maxBytes = 10 * 1024 * 1024;
const uuid = z.string().uuid();
const extensions: Record<string, string[]> = {
  'application/pdf': ['pdf'], 'image/jpeg': ['jpg','jpeg'], 'image/png': ['png'], 'image/webp': ['webp'], 'text/plain': ['txt'],
};
export async function OPTIONS(request: Request) { return new NextResponse(null, { status: 204, headers: activityHeaders(request) }); }
export async function GET(request: Request) {
  const reply = (body: unknown, status = 200) => NextResponse.json(body, { status, headers: activityHeaders(request) });
  try {
    const actor = await activityActor(request); if (!actor) return reply({ error: 'Sign in to open this file.' }, 401);
    const id = new URL(request.url).searchParams.get('id'); if (!uuid.safeParse(id).success) return reply({ error: 'Choose a valid file.' }, 400);
    const { data: file, error } = await actor.client.from('homework_files').select('*').eq('id', id!).maybeSingle();
    if (error || !file) return reply({ error: 'File not found or access denied.' }, 404);
    const { data, error: signError } = await actor.client.storage.from('homework-files').createSignedUrl(file.object_path, 120, { download: file.filename });
    if (signError) return reply({ error: 'File temporarily unavailable. Try again.' }, 503);
    return reply({ url: data.signedUrl });
  } catch { return reply({ error: 'File temporarily unavailable.' }, 503); }
}
export async function POST(request: Request) {
  const reply = (body: unknown, status = 200) => NextResponse.json(body, { status, headers: activityHeaders(request) });
  try {
    if (!activityWriteOriginAllowed(request)) return reply({ error: 'Origin not allowed.' }, 403);
    const actor = await activityActor(request);
    if (!actor || !['learner','instructor'].includes(actor.role)) return reply({ error: 'Sign in to upload homework files.' }, 401);
    const assignmentId = new URL(request.url).searchParams.get('assignment');
    if (!uuid.safeParse(assignmentId).success) return reply({ error: 'Choose a valid homework assignment.' }, 400);
    const { data: homework } = await actor.client.from('homework_assignments').select('*').eq('id', assignmentId!).maybeSingle();
    if (!homework) return reply({ error: 'Assignment not found or access denied.' }, 404);
    const kind = actor.role === 'instructor' ? 'instruction' : 'answer';
    if ((kind === 'instruction' && (homework.status !== 'draft' || homework.instructor_id !== actor.id)) ||
        (kind === 'answer' && homework.status !== 'published')) return reply({ error: 'Files cannot be added at this stage.' }, 409);
    if (kind === 'answer') {
      const { data: submitted } = await actor.client.from('homework_submissions').select('id').eq('assignment_id', homework.id).eq('learner_id', actor.id).maybeSingle();
      if (submitted) return reply({ error: 'This homework has already been submitted.' }, 409);
    }
    let form: FormData;
    try { form = await readResourceForm(request, maxBytes + 65536); }
    catch (error) { return reply({ error: error instanceof UploadSizeError ? 'Files must be no more than 10 MB.' : 'The upload was incomplete. Choose the file and retry.' }, error instanceof UploadSizeError ? 413 : 400); }
    const file = form.get('file');
    if (!(file instanceof File) || file.size < 1 || file.size > maxBytes) return reply({ error: 'Choose a nonempty file up to 10 MB.' }, 413);
    const filename = file.name.replace(/[\\/\u0000-\u001f\u007f]/g, '_').slice(0, 200);
    const extension = filename.split('.').pop()?.toLowerCase() ?? '';
    if (!extensions[file.type]?.includes(extension)) return reply({ error: 'Use PDF, JPG, PNG, WebP, or TXT files with the matching extension.' }, 415);
    const bytes = Buffer.from(await file.arrayBuffer());
    const valid = file.type === 'text/plain'
      ? (() => { try { const text = new TextDecoder('utf-8', { fatal: true }).decode(bytes); return !/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(text); } catch { return false; } })()
      : isAllowedLearningResourceMime(file.type) && matchesResourceContent(file.type, bytes);
    if (!valid) return reply({ error: 'The file content does not match its format.' }, 415);
    const digest = createHash('sha256').update(JSON.stringify([actor.id, homework.id, kind, filename, file.type])).update(bytes).digest('hex');
    const fileId = `${digest.slice(0,8)}-${digest.slice(8,12)}-5${digest.slice(13,16)}-a${digest.slice(17,20)}-${digest.slice(20,32)}`;
    const objectPath = `${homework.id}/${actor.id}/${fileId}.${extension}`;
    const { error: uploadError } = await actor.service.storage.from('homework-files').upload(objectPath, bytes, { contentType: file.type, upsert: false });
    if (uploadError && !['409','Duplicate'].includes(String(uploadError.statusCode))) return reply({ error: 'The file could not be uploaded. Try again.' }, 503);
    const { data, error } = await actor.service.rpc('manage_homework', { p_actor: actor.id, p_action: 'attach', p_payload: {
      assignment_id: homework.id, file_id: fileId, kind, filename, object_path: objectPath, mime_type: file.type, size_bytes: file.size,
    } });
    // Never remove a content-addressed object after an uncertain response: a
    // concurrent retry may already have attached it. Unreferenced objects have
    // no read policy; the same file identity safely recovers an upload retry.
    if (error) { const result = activityError(error); return reply({ error: result.error }, result.status); }
    return reply({ file: data });
  } catch { return reply({ error: 'Upload could not be confirmed. Refresh and retry the same file.' }, 503); }
}
