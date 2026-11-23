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
import {
  AlertDialog, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from '@/components/ui/alert-dialog';
import { manilaDate, manilaInputToUtc, utcToManilaInput, latenessDuration } from '@/lib/activities/dates';
import type { HomeworkFile } from '@/lib/activities/types';
import { criteriaTotal, curriculumFromHomework, curriculumPayload, homeworkStatusLabel, submissionRuleSummary } from '@/lib/evaluations/homework';
import type { CurriculumOptions, HomeworkRecord, HomeworkSubmissionRecord } from '@/lib/evaluations/types';
import { homeworkRequest } from './HomeworkManager';
import { HomeworkCurriculumFields } from './HomeworkCurriculumFields';

type Learner = { id: string; name: string; email: string; active: boolean };
type Confirm = { action: 'finalize' | 'release'; ids: string[]; label: string } | null;

function FileLink({ file }: { file: HomeworkFile }) {
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  return <div><Button variant="link" className="h-auto min-h-11 max-w-full whitespace-normal break-all px-0 text-left" disabled={busy} onClick={async () => { setBusy(true); setError(''); try { const response = await fetch(`/api/activities/files?id=${file.id}`, { cache: 'no-store', signal: AbortSignal.timeout(30000) }); const result = await response.json(); if (!response.ok) throw new Error(result.error); const link = document.createElement('a'); link.href = result.url; link.target = '_blank'; link.rel = 'noopener noreferrer'; link.click(); } catch { setError('File could not be opened. Retry.'); } finally { setBusy(false); } }}>{file.filename} ({Math.ceil(file.size_bytes / 1024)} KB)</Button>{error ? <p role="alert" className="text-sm text-destructive">{error}</p> : null}</div>;
}

const statusVariant = (status?: string) => status === 'released' ? 'secondary' : status === 'finalized' || status === 'graded' ? 'default' : 'outline';

/** Evaluate stage: a draft grade by criteria (or a single score), editable until finalized. */
function GradeForm({ submission, homework, onSaved, disabled }: { submission: HomeworkSubmissionRecord; homework: HomeworkRecord; onSaved: () => void; disabled: boolean }) {
  const byCriteria = homework.criteria.length > 0;
  const [scores, setScores] = useState<Record<string, string>>(Object.fromEntries(homework.criteria.map(c => [c.id, submission.criterion_scores?.[c.id] !== undefined ? String(submission.criterion_scores[c.id]) : ''])));
  const [score, setScore] = useState(submission.score !== null && !byCriteria ? String(submission.score) : '');
  const [feedback, setFeedback] = useState(submission.feedback ?? '');
  const [busy, setBusy] = useState(false); const [error, setError] = useState('');
  const total = criteriaTotal(homework.criteria.map(c => ({ max_points: Number(scores[c.id] || 0) })));
  const incomplete = byCriteria && homework.criteria.some(c => scores[c.id] === '');
  return <form className="mt-4 space-y-3" onSubmit={async e => { e.preventDefault(); if (busy) return; if (incomplete && homework.criteria.some(c => scores[c.id] !== '')) { setError('Score every criterion, or leave all criteria blank to save feedback only.'); return; } setBusy(true); setError(''); try {
      const criterionScores = byCriteria && !incomplete ? Object.fromEntries(homework.criteria.map(c => [c.id, Number(scores[c.id])])) : null;
      await homeworkRequest({ action: 'grade', assignment_id: homework.id, submission_id: submission.id, feedback, score: byCriteria ? (criterionScores ? total : null) : score === '' ? null : Number(score), criterion_scores: criterionScores });
      onSaved();
    } catch (err) { setError(err instanceof Error ? err.message : 'Grading could not be saved.'); } finally { setBusy(false); } }}>
    <fieldset disabled={busy || disabled} className="space-y-3">
      <legend className="text-sm font-semibold">Evaluate · grade (not visible to the learner until released)</legend>
      {byCriteria ? <div className="space-y-2">{homework.criteria.map(c => <div key={c.id} className="grid gap-2 rounded-lg border border-border p-3 sm:grid-cols-[minmax(0,1fr)_9rem] sm:items-center"><div><p className="text-sm font-medium">{c.criterion}</p>{c.description ? <p className="text-xs text-muted-foreground">{c.description}</p> : null}</div><div className="space-y-1"><Label htmlFor={`score-${submission.id}-${c.id}`}>Score (0–{Number(c.max_points)})</Label><Input id={`score-${submission.id}-${c.id}`} type="number" min={0} max={Number(c.max_points)} step="0.5" className="min-h-11" value={scores[c.id]} onChange={e => setScores(current => ({ ...current, [c.id]: e.target.value }))} /></div></div>)}
        <p className="text-sm font-semibold" aria-live="polite">Total: {incomplete ? '—' : total} / {Number(homework.max_score)}</p></div>
        : <div className="space-y-2"><Label htmlFor={`score-${submission.id}`}>Score (optional, 0–{Number(homework.max_score)})</Label><Input id={`score-${submission.id}`} type="number" min={0} max={Number(homework.max_score)} step="0.01" className="min-h-11 max-w-40" value={score} onChange={e => setScore(e.target.value)} /></div>}
      <div className="space-y-2"><Label htmlFor={`feedback-${submission.id}`}>Feedback (optional)</Label><Textarea id={`feedback-${submission.id}`} maxLength={10000} value={feedback} onChange={e => setFeedback(e.target.value)} /></div>
      <Button className="min-h-11" type="submit">{busy ? 'Saving…' : submission.status === 'graded' ? 'Update grade' : 'Save grade'}</Button>
    </fieldset>{error ? <p role="alert" className="text-sm text-destructive">{error}</p> : null}
  </form>;
}

function GradeSummary({ submission, homework, names }: { submission: HomeworkSubmissionRecord; homework: HomeworkRecord; names: Record<string, string> }) {
  const who = (id: string | null) => (id && names[id]) || 'Instructor';
  return <div className="space-y-2 text-sm">
    {submission.score !== null ? <p className="text-base font-semibold">Score: {Number(submission.score)} / {Number(homework.max_score)}</p> : <p className="text-muted-foreground">No numeric score</p>}
    {submission.criterion_scores && homework.criteria.length ? <ul className="space-y-1">{homework.criteria.map(c => <li key={c.id} className="flex justify-between gap-3"><span>{c.criterion}</span><span className="font-medium tabular-nums">{submission.criterion_scores?.[c.id] ?? '—'} / {Number(c.max_points)}</span></li>)}</ul> : null}
    {submission.feedback ? <p className="whitespace-pre-wrap break-words">{submission.feedback}</p> : null}
    <p className="text-xs text-muted-foreground">Graded by {who(submission.graded_by)} · {manilaDate(submission.graded_at)}{submission.finalized_at ? ` · Finalized by ${who(submission.finalized_by)} · ${manilaDate(submission.finalized_at)}` : ''}{submission.released_at ? ` · Released by ${who(submission.released_by)} · ${manilaDate(submission.released_at)}` : ''}</p>
  </div>;
}

export function HomeworkWorkspace({ homework: h, classTitle, active, files, submissions, learners, names, options, curriculumLabels, initialSubmission, canAct = true }: {
  homework: HomeworkRecord; classTitle: string; active: boolean; files: HomeworkFile[]; submissions: HomeworkSubmissionRecord[]; learners: Learner[];
  names: Record<string, string>; options: CurriculumOptions | null; curriculumLabels: { coc?: string; mission?: string; module?: string };
  initialSubmission?: string | null; canAct?: boolean;
}) {
  const router = useRouter();
  const [title, setTitle] = useState(h.title); const [instructions, setInstructions] = useState(h.instructions);
  const [deadline, setDeadline] = useState(utcToManilaInput(h.deadline_at));
  const [curriculum, setCurriculum] = useState(() => curriculumFromHomework(h));
  const [busy, setBusy] = useState(false); const busyRef = useRef(false); const [message, setMessage] = useState(''); const [error, setError] = useState('');
  const [selected, setSelected] = useState<string | null>(() => submissions.find(s => s.id === initialSubmission)?.learner_id ?? null);
  const [editing, setEditing] = useState(false);
  const [confirm, setConfirm] = useState<Confirm>(null);
  const draft = h.status === 'draft';
  const writable = active && canAct;
  const curriculumDirty = JSON.stringify(curriculumPayload(curriculum)) !== JSON.stringify(curriculumPayload(curriculumFromHomework(h)));
  const dirty = title !== h.title || instructions !== h.instructions || deadline !== utcToManilaInput(h.deadline_at) || (draft && curriculumDirty);
  useEffect(() => {
    if (draft || dirty || editing) return;
    // Keep local QA useful when its optional Realtime container is stopped.
    // Server reads remain authoritative; never overwrite a pending draft.
    const timer = setInterval(() => {
      if (document.visibilityState === 'visible' && !busyRef.current) router.refresh();
    }, 20000);
    return () => clearInterval(timer);
  }, [draft, dirty, editing, router]);
  const [uploadProgress,setUploadProgress]=useState<number|null>(null);
  const submission = submissions.find(s => s.learner_id === selected);
  const run = async (work: () => Promise<unknown>, text: string) => { if (busyRef.current) return; busyRef.current = true; setBusy(true); setError(''); setMessage(''); try { await work(); setMessage(text); router.refresh(); } catch (err) { setError(err instanceof Error ? err.message : 'The action could not be saved.'); } finally { busyRef.current = false; setBusy(false); } };
  const transition = (action: 'finalize' | 'release', ids: string[]) => run(async () => {
    const result = await homeworkRequest({ action, submission_ids: ids });
    const failed = (result?.results ?? []).filter((r: { ok: boolean }) => !r.ok).length;
    if (failed) throw new Error(`${failed} submission${failed === 1 ? '' : 's'} could not be ${action === 'finalize' ? 'finalized' : 'released'}. Refresh and check their status.`);
  }, action === 'finalize' ? 'Finalized. Release when learners may see the result.' : 'Released. Learners can now see the score and feedback.');
  const graded = submissions.filter(s => s.status === 'graded');
  const finalized = submissions.filter(s => s.status === 'finalized');
  const counts = { submitted: submissions.filter(s => s.status === 'submitted').length, graded: graded.length, finalized: finalized.length, released: submissions.filter(s => s.status === 'released').length };
  const competency = [curriculumLabels.coc, curriculumLabels.mission, curriculumLabels.module].filter(Boolean).join(' · ');

  return <div className="space-y-5"><Link className="inline-flex min-h-11 items-center text-sm text-primary" href={`/classes/${h.class_id}?tab=assignments`}>← {classTitle} / Assignments</Link>
    <header className="flex flex-wrap items-center gap-3"><h1 className="min-w-0 break-words text-2xl font-bold">{h.title}</h1><Badge>{h.status}</Badge>{!canAct ? <Badge variant="outline">Read-only</Badge> : null}</header>
    <p className="text-sm text-muted-foreground">Homework · {classTitle} · {competency || 'Not linked to a COC'} · Max score {Number(h.max_score)} · Late submissions allowed</p>
    {error ? <p role="alert" className="rounded-lg border border-destructive p-3 text-sm text-destructive">{error}</p> : null}{message ? <p role="status" className="text-sm">{message}</p> : null}
    <section className="space-y-4 rounded-xl border border-border bg-card p-4 sm:p-5"><h2 className="font-semibold">{draft ? 'Assignment draft' : 'Assignment details'}</h2>
      <form className="space-y-4" onSubmit={e => { e.preventDefault(); void run(() => homeworkRequest(draft ? { action: 'edit', assignment_id: h.id, title, instructions, deadline_at: manilaInputToUtc(deadline), ...curriculumPayload(curriculum) } : { action: 'deadline', assignment_id: h.id, deadline_at: manilaInputToUtc(deadline) }), draft ? 'Draft saved.' : 'Deadline updated. Existing submissions retain their original deadline and lateness.'); }}>
        <fieldset disabled={busy || !writable} className="space-y-4">
          {draft ? <><div className="space-y-2"><Label htmlFor="edit-homework-title">Assignment title</Label><Input id="edit-homework-title" className="min-h-11" required minLength={2} maxLength={300} value={title} onChange={e => setTitle(e.target.value)} /></div><div className="space-y-2"><Label htmlFor="edit-homework-instructions">Instructions</Label><Textarea id="edit-homework-instructions" required rows={6} maxLength={20000} value={instructions} onChange={e => setInstructions(e.target.value)} /></div>
            {options ? <HomeworkCurriculumFields idPrefix="edit-homework" value={curriculum} onChange={setCurriculum} options={options} /> : <p role="alert" className="text-sm text-destructive">COC and mission options could not be loaded. Refresh to edit the curriculum links.</p>}</>
            : <div className="space-y-4"><p className="whitespace-pre-wrap break-words text-sm">{h.instructions}</p>
              {h.learning_objectives.length ? <div><h3 className="text-sm font-semibold">Learning objectives</h3><ul className="mt-1 list-disc space-y-1 pl-5 text-sm">{h.learning_objectives.map((o, i) => <li key={i}>{o}</li>)}</ul></div> : null}
              {h.criteria.length ? <div><h3 className="text-sm font-semibold">Evaluation criteria · {Number(h.max_score)} points</h3><ul className="mt-1 space-y-1 text-sm">{h.criteria.map(c => <li key={c.id} className="flex justify-between gap-3"><span>{c.criterion}{c.description ? <span className="text-muted-foreground"> — {c.description}</span> : null}</span><span className="font-medium tabular-nums">{Number(c.max_points)} pts</span></li>)}</ul></div> : null}
              <div><h3 className="text-sm font-semibold">Learner submission</h3><p className="text-sm" data-testid="homework-submission-rule">{submissionRuleSummary(h)}</p>{h.submission_requirements ? <p className="mt-1 whitespace-pre-wrap break-words text-sm text-muted-foreground">{h.submission_requirements}</p> : null}</div></div>}
          <div className="max-w-sm space-y-2"><Label htmlFor="edit-homework-deadline">Deadline (optional, Asia/Manila)</Label><Input className="min-h-11" id="edit-homework-deadline" type="datetime-local" value={deadline} onChange={e => setDeadline(e.target.value)} /><p className="text-xs text-muted-foreground">{manilaDate(h.deadline_at)}. At the deadline is on time. Later submissions are accepted and marked late.</p></div>
          {writable ? <Button type="submit" className="min-h-11" disabled={!dirty}>{busy ? 'Saving…' : draft ? 'Save draft' : 'Update deadline'}</Button> : null}
        </fieldset>
      </form>
      <div className="space-y-2 border-t border-border pt-4"><h3 className="text-sm font-semibold">Instruction attachments</h3>{files.filter(f => f.kind === 'instruction').map(file => <FileLink key={file.id} file={file} />)}
        {draft && writable ? <><Label htmlFor="instruction-file">Add supporting file (PDF, image, or TXT; up to 10 MB; 5 files)</Label><Input id="instruction-file" type="file" accept=".pdf,.jpg,.jpeg,.png,.webp,.txt" disabled={busy} className="min-h-11" onChange={e => { const file = e.target.files?.[0]; e.target.value = ''; if (!file) return; if (file.size > 10485760) { setError('Choose a file up to 10 MB.'); return; } void run(async () => { setUploadProgress(0); try { await directUpload(file, {purpose:'homework',target_id:h.id},setUploadProgress); } finally { setUploadProgress(null); } }, 'Instruction file attached.'); }} /></> : null}
        {uploadProgress !== null ? <div role="status" aria-live="polite"><progress aria-label="File upload progress" className="w-full" value={uploadProgress} max={100} /><p className="text-xs">{uploadProgress >= 95 ? 'Verifying file...' : `Uploading ${uploadProgress}%`}</p></div> : null}
      </div>
      {draft && writable ? <div className="border-t border-border pt-4"><p className="mb-3 text-sm text-muted-foreground">Review the instructions, competency links, criteria, files, target class and deadline. Publication makes this homework visible to active learners.</p><Button className="min-h-11" disabled={busy || dirty} onClick={() => void run(() => homeworkRequest({ action: 'publish', assignment_id: h.id }), 'Homework published to the class.')}>Publish Assignment</Button>{dirty ? <p className="mt-2 text-xs text-muted-foreground">Save draft changes before publishing.</p> : null}</div> : null}
    </section>
    {!draft ? <section className="rounded-xl border border-border bg-card p-4 sm:p-5"><div className="flex flex-wrap items-start justify-between gap-3"><div><h2 className="font-semibold">Submissions</h2><p className="mt-1 text-sm text-muted-foreground">{submissions.length} submitted · {counts.submitted} awaiting evaluation · {counts.graded} evaluated · {counts.finalized} finalized · {counts.released} released. Learners see a grade only after release.</p></div>
        {writable ? <div className="flex flex-wrap gap-2"><Button variant="outline" className="min-h-11" disabled={busy || !graded.length} onClick={() => setConfirm({ action: 'finalize', ids: graded.map(s => s.id), label: `Finalize ${graded.length} evaluated grade${graded.length === 1 ? '' : 's'}?` })}>Finalize evaluated ({graded.length})</Button><Button className="min-h-11" disabled={busy || !finalized.length} onClick={() => setConfirm({ action: 'release', ids: finalized.map(s => s.id), label: `Release ${finalized.length} finalized grade${finalized.length === 1 ? '' : 's'} to learners?` })}>Release finalized ({finalized.length})</Button></div> : null}</div>
      <ul className="mt-4 divide-y divide-border">{learners.map(learner => { const s = submissions.find(row => row.learner_id === learner.id); return <li key={learner.id} className="py-3"><button type="button" disabled={!s} aria-pressed={selected === learner.id} className="flex min-h-12 w-full flex-wrap items-start justify-between gap-3 rounded-md text-left focus-visible:ring-2 focus-visible:ring-ring disabled:cursor-default" onClick={() => { setSelected(learner.id); setEditing(false); }}><span className="min-w-0 flex-1"><span className="block break-words text-sm font-medium">{learner.name}{learner.active ? '' : ' (previous enrollment)'}</span><span className="block break-all text-xs text-muted-foreground">{learner.email}</span>{s ? <><span className="mt-1 block text-xs">Submitted {manilaDate(s.submitted_at)}</span><span className="block text-xs">Deadline: {manilaDate(s.effective_deadline_at)}</span><span className="block text-xs">{Number(s.lateness_seconds) > 0 ? `Late by ${latenessDuration(Number(s.lateness_seconds))}` : 'On time'}</span></> : null}</span><Badge variant={statusVariant(s?.status)}>{!s ? 'Not submitted' : homeworkStatusLabel(s.status)}</Badge>{s ? <span className="text-sm text-primary">Open submission</span> : null}</button></li>; })}</ul>
      {submission ? <article className="mt-5 space-y-3 rounded-lg border border-border bg-muted/20 p-4" aria-labelledby="submission-heading"><div className="flex flex-wrap items-center justify-between gap-2"><h3 id="submission-heading" className="font-semibold">{learners.find(l => l.id === selected)?.name} — submission</h3><Badge variant={statusVariant(submission.status)}>{homeworkStatusLabel(submission.status)}</Badge></div><p className="whitespace-pre-wrap break-words text-sm">{submission.answer || 'File submission'}</p>{files.filter(f => f.submission_id === submission.id).map(file => <FileLink key={file.id} file={file} />)}
        {(submission.status === 'submitted' || (submission.status === 'graded' && editing)) && writable ? <GradeForm key={`${submission.id}:${submission.graded_at}`} submission={submission} homework={h} disabled={busy} onSaved={() => { setEditing(false); setMessage('Grade saved. It stays hidden from the learner until you finalize and release it.'); router.refresh(); }} /> : null}
        {submission.status !== 'submitted' && !(submission.status === 'graded' && editing) ? <div role="status" className="space-y-3 border-t border-border pt-3"><GradeSummary submission={submission} homework={h} names={names} />
          {writable && submission.status === 'graded' ? <div className="flex flex-wrap gap-2"><Button variant="outline" className="min-h-11" disabled={busy} onClick={() => setEditing(true)}>Edit grade</Button><Button className="min-h-11" disabled={busy} onClick={() => setConfirm({ action: 'finalize', ids: [submission.id], label: 'Finalize this grade?' })}>Finalize</Button></div> : null}
          {writable && submission.status === 'finalized' ? <Button className="min-h-11" disabled={busy} onClick={() => setConfirm({ action: 'release', ids: [submission.id], label: 'Release this grade to the learner?' })}>Release to learner</Button> : null}
          {submission.status === 'graded' ? <p className="text-xs text-muted-foreground">Evaluated (draft). The learner sees “Being evaluated”.</p> : submission.status === 'finalized' ? <p className="text-xs text-muted-foreground">Finalized and locked. The learner sees it after release.</p> : <p className="text-xs text-muted-foreground">Released. The learner can see this score and feedback.</p>}
        </div> : null}
      </article> : <p className="mt-4 text-sm text-muted-foreground">Select a submitted learner to read their work and grade it.</p>}
    </section> : null}
    <AlertDialog open={confirm !== null} onOpenChange={open => { if (!open && !busy) setConfirm(null); }}>
      <AlertDialogContent>
        <AlertDialogHeader><AlertDialogTitle>{confirm?.label}</AlertDialogTitle><AlertDialogDescription>{confirm?.action === 'finalize' ? 'Finalizing locks the grade and feedback. Learners still cannot see them until you release.' : 'Learners will see the score, criterion scores and feedback immediately and receive a notification.'}</AlertDialogDescription></AlertDialogHeader>
        <AlertDialogFooter><AlertDialogCancel className="min-h-11" disabled={busy}>Cancel</AlertDialogCancel><Button className="min-h-11" disabled={busy} onClick={() => { const current = confirm; setConfirm(null); if (current) void transition(current.action, current.ids); }}>{confirm?.action === 'finalize' ? 'Finalize' : 'Release'}</Button></AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  </div>;
}
