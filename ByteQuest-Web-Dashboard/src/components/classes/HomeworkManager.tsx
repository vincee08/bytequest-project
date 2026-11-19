"use client";

import { useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { Plus, Loader2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Badge } from '@/components/ui/badge';
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { manilaDate, manilaInputToUtc } from '@/lib/activities/dates';
import type { Homework } from '@/lib/activities/types';
import { curriculumPayload, emptyCurriculum } from '@/lib/evaluations/homework';
import type { HomeworkRecord } from '@/lib/evaluations/types';
import { HomeworkCurriculumFields, useCurriculumOptions } from './HomeworkCurriculumFields';

export async function homeworkRequest(body: unknown) {
  const response = await fetch('/api/activities/homework', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body), signal: AbortSignal.timeout(35000) });
  const result = await response.json();
  if (!response.ok) throw new Error(result.error ?? 'Homework could not be saved.');
  return result.record;
}

function CreateHomeworkForm({ classId, onCreated }: { classId: string; onCreated: (id: string) => void }) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [title, setTitle] = useState('');
  const [instructions, setInstructions] = useState('');
  const [deadline, setDeadline] = useState('');
  const [curriculum, setCurriculum] = useState(emptyCurriculum);
  const { options, error: optionsError, retry } = useCurriculumOptions();
  return <form className="space-y-4" onSubmit={async event => { event.preventDefault(); if (busy) return; setError(''); setBusy(true); try { const h = await homeworkRequest({ action: 'create', class_id: classId, title, instructions, deadline_at: manilaInputToUtc(deadline), ...curriculumPayload(curriculum) }); onCreated(h.id); } catch (err) { setError(err instanceof Error ? err.message : 'Draft could not be saved.'); setBusy(false); } }}>
    <fieldset disabled={busy} className="space-y-4"><div className="space-y-2"><Label htmlFor="homework-title">Assignment title</Label><Input id="homework-title" className="min-h-11" required minLength={2} maxLength={300} value={title} onChange={e => setTitle(e.target.value)} /></div>
      <div className="space-y-2"><Label htmlFor="homework-instructions">Instructions</Label><Textarea id="homework-instructions" required rows={5} maxLength={20000} value={instructions} onChange={e => setInstructions(e.target.value)} /></div>
      <div className="space-y-2"><Label htmlFor="homework-deadline">Deadline (optional, Asia/Manila)</Label><Input id="homework-deadline" className="min-h-11" type="datetime-local" value={deadline} onChange={e => setDeadline(e.target.value)} /><p className="text-xs text-muted-foreground">Leave blank for no deadline. Late homework remains submittable.</p></div>
      {options ? <HomeworkCurriculumFields idPrefix="create-homework" value={curriculum} onChange={setCurriculum} options={options} />
        : optionsError ? <div role="alert" className="rounded-lg border border-destructive/40 p-3 text-sm"><p>COC and mission options could not be loaded. You can still save an unlinked draft.</p><Button type="button" variant="outline" className="mt-2 min-h-11" onClick={retry}>Try again</Button></div>
        : <p role="status" className="text-sm text-muted-foreground">Loading COC and mission options…</p>}
    </fieldset>{error ? <p role="alert" className="text-sm text-destructive">{error}</p> : null}
    <Button type="submit" className="min-h-11" disabled={busy}>{busy ? <Loader2 className="mr-2 h-4 w-4 animate-spin" aria-hidden="true" /> : null}Save draft</Button>
  </form>;
}

export function HomeworkManager({ classId, classTitle, active, homework }: { classId: string; classTitle: string; active: boolean; homework: Homework[] }) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [formKey, setFormKey] = useState(0);
  const rows = homework as HomeworkRecord[];
  return <section className="rounded-xl border border-border bg-card p-4 sm:p-5">
    <div className="flex flex-wrap items-center justify-between gap-3"><div><h2 className="font-semibold">Homework assignments</h2><p className="mt-1 text-sm text-muted-foreground">Work completed outside ByteQuest, organised by COC and mission with criteria and a maximum score. Grades move Evaluate → Finalize → Release; learners see them only after release. Late submissions are allowed.</p></div>
      <div className="flex flex-wrap gap-2"><Button asChild variant="outline" className="min-h-11"><Link href={`/submissions?class=${classId}`}>View submissions</Link></Button>{active ? <Button className="min-h-11" onClick={() => { setFormKey(key => key + 1); setOpen(true); }}><Plus className="mr-2 h-4 w-4" aria-hidden="true" />Create Assignment</Button> : null}</div></div>
    {rows.length ? <ul className="mt-4 divide-y divide-border">{rows.map(h => <li key={h.id} className="py-3"><Link className="flex min-h-12 flex-wrap items-center justify-between gap-3 rounded-md focus-visible:ring-2 focus-visible:ring-ring" href={`/classes/${classId}/assignments/${h.id}`}><span className="min-w-0 flex-1"><span className="block break-words text-sm font-semibold">{h.title}</span><span className="mt-1 block text-xs text-muted-foreground">{manilaDate(h.deadline_at)} · Max score {Number(h.max_score ?? 100)}{h.mission_code ? ` · ${h.mission_code.toUpperCase().replace('_', ' ')}` : ''}</span></span><Badge variant={h.status === 'published' ? 'secondary' : 'outline'}>{h.status}</Badge><span className="text-sm text-primary">{h.status === 'draft' ? 'Edit draft' : 'View submissions'}</span></Link></li>)}</ul> : <p className="mt-4 py-5 text-center text-sm text-muted-foreground">No homework assignments yet.</p>}
    <Dialog open={open} onOpenChange={setOpen}><DialogContent className="max-h-[90dvh] overflow-y-auto sm:max-w-3xl"><DialogHeader><DialogTitle>Create Assignment</DialogTitle><DialogDescription>Save a draft for {classTitle}. Link it to a COC and mission, add objectives and criteria, then review it before publishing.</DialogDescription></DialogHeader>
      <CreateHomeworkForm key={formKey} classId={classId} onCreated={id => { router.push(`/classes/${classId}/assignments/${id}`); router.refresh(); }} />
    </DialogContent></Dialog>
  </section>;
}
