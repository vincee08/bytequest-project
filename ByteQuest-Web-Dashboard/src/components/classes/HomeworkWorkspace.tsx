"use client";

import { useEffect, useRef, useState } from 'react';
import { directUpload } from '@/lib/uploads/client';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Badge } from '@/components/ui/badge';
import { manilaDate, manilaInputToUtc, utcToManilaInput, latenessDuration } from '@/lib/activities/dates';
import type { Homework, HomeworkFile, HomeworkSubmission } from '@/lib/activities/types';
import { homeworkRequest } from './HomeworkManager';

function FileLink({ file }: { file: HomeworkFile }) {
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  return <div><Button variant="link" className="h-auto min-h-11 max-w-full whitespace-normal break-all px-0 text-left" disabled={busy} onClick={async () => { setBusy(true); setError(''); try { const response = await fetch(`/api/activities/files?id=${file.id}`, { cache: 'no-store', signal: AbortSignal.timeout(30000) }); const result = await response.json(); if (!response.ok) throw new Error(result.error); const link = document.createElement('a'); link.href = result.url; link.target = '_blank'; link.rel = 'noopener noreferrer'; link.click(); } catch { setError('File could not be opened. Retry.'); } finally { setBusy(false); } }}>{file.filename} ({Math.ceil(file.size_bytes / 1024)} KB)</Button>{error ? <p role="alert" className="text-sm text-destructive">{error}</p> : null}</div>;
}
function GradeForm({ submission, assignmentId, disabled }: { submission: HomeworkSubmission; assignmentId: string; disabled: boolean }) {
  const router = useRouter();
  const [feedback, setFeedback] = useState(''); const [score, setScore] = useState('');
  const [busy, setBusy] = useState(false); const [error, setError] = useState('');
  return <form className="mt-4 space-y-3" onSubmit={async e => { e.preventDefault(); if (busy) return; setBusy(true); setError(''); try { await homeworkRequest({ action: 'grade', assignment_id: assignmentId, submission_id: submission.id, feedback, score: score === '' ? null : Number(score) }); router.refresh(); } catch (err) { setError(err instanceof Error ? err.message : 'Grading could not be saved.'); } finally { setBusy(false); } }}>
    <fieldset disabled={busy || disabled} className="space-y-3"><div className="space-y-2"><Label htmlFor={`feedback-${submission.id}`}>Feedback (optional)</Label><Textarea id={`feedback-${submission.id}`} maxLength={10000} value={feedback} onChange={e => setFeedback(e.target.value)} /></div><div className="space-y-2"><Label htmlFor={`score-${submission.id}`}>Score (optional, 0–100)</Label><Input id={`score-${submission.id}`} type="number" min={0} max={100} step="0.01" className="min-h-11 max-w-40" value={score} onChange={e => setScore(e.target.value)} /></div><Button className="min-h-11" type="submit">{busy ? 'Saving…' : 'Mark Graded'}</Button></fieldset>{error ? <p role="alert" className="text-sm text-destructive">{error}</p> : null}
  </form>;
}
export function HomeworkWorkspace({ homework: h, classTitle, active, files, submissions, learners }: { homework: Homework; classTitle: string; active: boolean; files: HomeworkFile[]; submissions: HomeworkSubmission[]; learners: { id: string; name: string; email: string; active: boolean }[] }) {
  const router = useRouter();
  const [title, setTitle] = useState(h.title); const [instructions, setInstructions] = useState(h.instructions);
  const [deadline, setDeadline] = useState(utcToManilaInput(h.deadline_at));
  const [busy, setBusy] = useState(false); const busyRef = useRef(false); const [message, setMessage] = useState(''); const [error, setError] = useState('');
  const [selected, setSelected] = useState<string | null>(null);
  const draft = h.status === 'draft';
  const dirty = title !== h.title || instructions !== h.instructions || deadline !== utcToManilaInput(h.deadline_at);
  useEffect(() => {
    if (draft || dirty) return;
    // Keep local QA useful when its optional Realtime container is stopped.
    // Server reads remain authoritative; never overwrite a pending draft.
    const timer = setInterval(() => {
      if (document.visibilityState === 'visible' && !busyRef.current) router.refresh();
    }, 20000);
    return () => clearInterval(timer);
  }, [draft, dirty, router]);
  const [uploadProgress,setUploadProgress]=useState<number|null>(null);
  const submission = submissions.find(s => s.learner_id === selected);
  const run = async (work: () => Promise<unknown>, text: string) => { if (busyRef.current) return; busyRef.current = true; setBusy(true); setError(''); setMessage(''); try { await work(); setMessage(text); router.refresh(); } catch (err) { setError(err instanceof Error ? err.message : 'The action could not be saved.'); } finally { busyRef.current = false; setBusy(false); } };
  return <div className="space-y-5"><Link className="inline-flex min-h-11 items-center text-sm text-primary" href={`/classes/${h.class_id}?tab=assignments`}>← {classTitle} / Assignments</Link>
    <header className="flex flex-wrap items-center gap-3"><h1 className="min-w-0 break-words text-2xl font-bold">{h.title}</h1><Badge>{h.status}</Badge></header>
    <p className="text-sm text-muted-foreground">Homework · {classTitle} · Late submissions allowed</p>
    {error ? <p role="alert" className="rounded-lg border border-destructive p-3 text-sm text-destructive">{error}</p> : null}{message ? <p role="status" className="text-sm">{message}</p> : null}
    <section className="space-y-4 rounded-xl border border-border bg-card p-4 sm:p-5"><h2 className="font-semibold">{draft ? 'Assignment draft' : 'Assignment details'}</h2>
      <form className="space-y-4" onSubmit={e => { e.preventDefault(); void run(() => homeworkRequest(draft ? { action: 'edit', assignment_id: h.id, title, instructions, deadline_at: manilaInputToUtc(deadline) } : { action: 'deadline', assignment_id: h.id, deadline_at: manilaInputToUtc(deadline) }), draft ? 'Draft saved.' : 'Deadline updated. Existing submissions retain their original deadline and lateness.'); }}>
        <fieldset disabled={busy || !active} className="space-y-4">
          {draft ? <><div className="space-y-2"><Label htmlFor="edit-homework-title">Assignment title</Label><Input id="edit-homework-title" required minLength={2} maxLength={300} value={title} onChange={e => setTitle(e.target.value)} /></div><div className="space-y-2"><Label htmlFor="edit-homework-instructions">Instructions</Label><Textarea id="edit-homework-instructions" required rows={6} maxLength={20000} value={instructions} onChange={e => setInstructions(e.target.value)} /></div></> : <p className="whitespace-pre-wrap break-words text-sm">{h.instructions}</p>}
          <div className="max-w-sm space-y-2"><Label htmlFor="edit-homework-deadline">Deadline (optional, Asia/Manila)</Label><Input className="min-h-11" id="edit-homework-deadline" type="datetime-local" value={deadline} onChange={e => setDeadline(e.target.value)} /><p className="text-xs text-muted-foreground">{manilaDate(h.deadline_at)}. At the deadline is on time. Later submissions are accepted and marked late.</p></div>
          <Button type="submit" className="min-h-11" disabled={!dirty}>{busy ? 'Saving…' : draft ? 'Save draft' : 'Update deadline'}</Button>
        </fieldset>
      </form>
      <div className="space-y-2 border-t border-border pt-4"><h3 className="text-sm font-semibold">Instruction attachments</h3>{files.filter(f => f.kind === 'instruction').map(file => <FileLink key={file.id} file={file} />)}
        {draft && active ? <><Label htmlFor="instruction-file">Add supporting file (PDF, image, or TXT; up to 10 MB; 5 files)</Label><Input id="instruction-file" type="file" accept=".pdf,.jpg,.jpeg,.png,.webp,.txt" disabled={busy} className="min-h-11" onChange={e => { const file = e.target.files?.[0]; e.target.value = ''; if (!file) return; if (file.size > 10485760) { setError('Choose a file up to 10 MB.'); return; } void run(async () => { setUploadProgress(0); try { await directUpload(file, {purpose:'homework',target_id:h.id},setUploadProgress); } finally { setUploadProgress(null); } }, 'Instruction file attached.'); }} /></> : null}
        {uploadProgress !== null ? <div role="status" aria-live="polite"><progress aria-label="File upload progress" className="w-full" value={uploadProgress} max={100} /><p className="text-xs">{uploadProgress >= 95 ? 'Verifying file...' : `Uploading ${uploadProgress}%`}</p></div> : null}
      </div>
      {draft && active ? <div className="border-t border-border pt-4"><p className="mb-3 text-sm text-muted-foreground">Review the instructions, files, target class and deadline. Publication makes this homework visible to active learners.</p><Button className="min-h-11" disabled={busy || dirty} onClick={() => void run(() => homeworkRequest({ action: 'publish', assignment_id: h.id }), 'Homework published to the class.')}>Publish Assignment</Button>{dirty ? <p className="mt-2 text-xs text-muted-foreground">Save draft changes before publishing.</p> : null}</div> : null}
    </section>
    {!draft ? <section className="rounded-xl border border-border bg-card p-4 sm:p-5"><h2 className="font-semibold">Submissions</h2><p className="mt-1 text-sm text-muted-foreground">{submissions.length} submitted · {submissions.filter(s => s.status === 'graded').length} graded. A score is optional.</p>
      <ul className="mt-4 divide-y divide-border">{learners.map(learner => { const s = submissions.find(row => row.learner_id === learner.id); return <li key={learner.id} className="py-3"><button type="button" disabled={!s} className="flex min-h-12 w-full flex-wrap items-start justify-between gap-3 rounded-md text-left focus-visible:ring-2 focus-visible:ring-ring disabled:cursor-default" onClick={() => setSelected(learner.id)}><span className="min-w-0 flex-1"><span className="block break-words text-sm font-medium">{learner.name}{learner.active ? '' : ' (previous enrollment)'}</span><span className="block break-all text-xs text-muted-foreground">{learner.email}</span>{s ? <><span className="mt-1 block text-xs">Submitted {manilaDate(s.submitted_at)}</span><span className="block text-xs">Deadline: {manilaDate(s.effective_deadline_at)}</span><span className="block text-xs">{Number(s.lateness_seconds) > 0 ? `Late by ${latenessDuration(Number(s.lateness_seconds))}` : 'On time'}</span></> : null}</span><Badge variant={s?.status === 'graded' ? 'secondary' : 'outline'}>{!s ? 'Assigned' : s.status === 'graded' ? 'Graded' : 'Submitted for Grading'}</Badge>{s ? <span className="text-sm text-primary">Open submission</span> : null}</button></li>; })}</ul>
      {submission ? <article className="mt-5 space-y-3 rounded-lg border border-border bg-muted/20 p-4"><h3 className="font-semibold">{learners.find(l => l.id === selected)?.name} — submission</h3><p className="whitespace-pre-wrap break-words text-sm">{submission.answer || 'File submission'}</p>{files.filter(f => f.submission_id === submission.id).map(file => <FileLink key={file.id} file={file} />)}
        {submission.status === 'graded' ? <div role="status"><p className="font-medium">Graded</p><p className="text-xs text-muted-foreground">{manilaDate(submission.graded_at)} · Instructor {submission.graded_by}</p>{submission.feedback ? <p className="mt-2 whitespace-pre-wrap break-words text-sm">{submission.feedback}</p> : null}{submission.score !== null ? <p className="mt-2 text-sm">Score: {submission.score}/100</p> : null}</div> : <GradeForm key={submission.id} submission={submission} assignmentId={h.id} disabled={!active} />}
      </article> : <p className="mt-4 text-sm text-muted-foreground">Select a submitted learner to read their work and grade it.</p>}
    </section> : null}
  </div>;
}
