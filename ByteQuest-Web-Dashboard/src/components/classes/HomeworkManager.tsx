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

export async function homeworkRequest(body: unknown) {
  const response = await fetch('/api/activities/homework', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body), signal: AbortSignal.timeout(35000) });
  const result = await response.json();
  if (!response.ok) throw new Error(result.error ?? 'Homework could not be saved.');
  return result.record;
}
export function HomeworkManager({ classId, classTitle, active, homework }: { classId: string; classTitle: string; active: boolean; homework: Homework[] }) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [title, setTitle] = useState('');
  const [instructions, setInstructions] = useState('');
  const [deadline, setDeadline] = useState('');
  return <section className="rounded-xl border border-border bg-card p-4 sm:p-5">
    <div className="flex flex-wrap items-center justify-between gap-3"><div><h2 className="font-semibold">Homework assignments</h2><p className="mt-1 text-sm text-muted-foreground">Work completed outside ByteQuest, then submitted here for Instructor grading. Late submissions are allowed.</p></div>
      {active ? <Button className="min-h-11" onClick={() => setOpen(true)}><Plus className="mr-2 h-4 w-4" aria-hidden="true" />Create Assignment</Button> : null}</div>
    {homework.length ? <ul className="mt-4 divide-y divide-border">{homework.map(h => <li key={h.id} className="py-3"><Link className="flex min-h-12 flex-wrap items-center justify-between gap-3 rounded-md focus-visible:ring-2 focus-visible:ring-ring" href={`/classes/${classId}/assignments/${h.id}`}><span className="min-w-0 flex-1"><span className="block break-words text-sm font-semibold">{h.title}</span><span className="mt-1 block text-xs text-muted-foreground">{manilaDate(h.deadline_at)}</span></span><Badge variant={h.status === 'published' ? 'secondary' : 'outline'}>{h.status}</Badge><span className="text-sm text-primary">{h.status === 'draft' ? 'Edit draft' : 'View submissions'}</span></Link></li>)}</ul> : <p className="mt-4 py-5 text-center text-sm text-muted-foreground">No homework assignments yet.</p>}
    <Dialog open={open} onOpenChange={next => { if (!busy) setOpen(next); }}><DialogContent className="max-h-[90dvh] overflow-y-auto"><DialogHeader><DialogTitle>Create Assignment</DialogTitle><DialogDescription>Save a draft for {classTitle}. Add supporting files and review it before publishing.</DialogDescription></DialogHeader>
      <form className="space-y-4" onSubmit={async event => { event.preventDefault(); if (busy) return; setError(''); setBusy(true); try { const h = await homeworkRequest({ action: 'create', class_id: classId, title, instructions, deadline_at: manilaInputToUtc(deadline) }); router.push(`/classes/${classId}/assignments/${h.id}`); router.refresh(); } catch (err) { setError(err instanceof Error ? err.message : 'Draft could not be saved.'); setBusy(false); } }}>
        <fieldset disabled={busy} className="space-y-4"><div className="space-y-2"><Label htmlFor="homework-title">Assignment title</Label><Input id="homework-title" className="min-h-11" required minLength={2} maxLength={300} value={title} onChange={e => setTitle(e.target.value)} /></div>
          <div className="space-y-2"><Label htmlFor="homework-instructions">Instructions</Label><Textarea id="homework-instructions" required rows={5} maxLength={20000} value={instructions} onChange={e => setInstructions(e.target.value)} /></div>
          <div className="space-y-2"><Label htmlFor="homework-deadline">Deadline (optional, Asia/Manila)</Label><Input id="homework-deadline" className="min-h-11" type="datetime-local" value={deadline} onChange={e => setDeadline(e.target.value)} /><p className="text-xs text-muted-foreground">Leave blank for no deadline. Late homework remains submittable.</p></div>
        </fieldset>{error ? <p role="alert" className="text-sm text-destructive">{error}</p> : null}
        <Button type="submit" className="min-h-11" disabled={busy}>{busy ? <Loader2 className="mr-2 h-4 w-4 animate-spin" aria-hidden="true" /> : null}Save draft</Button>
      </form>
    </DialogContent></Dialog>
  </section>;
}
