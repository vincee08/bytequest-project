"use client";

import { useEffect, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { manilaDate, manilaInputToUtc, utcToManilaInput } from '@/lib/activities/dates';

export type QuizDeadlineAssignment = { id: string; classTitle: string; dueAt: string | null };
export function QuizDeadlineControls({ assignments, quizTitle, serverNow }: { assignments: QuizDeadlineAssignment[]; quizTitle: string; serverNow: string }) {
  const router = useRouter();
  const [now, setNow] = useState(new Date(serverNow).getTime());
  useEffect(() => { const start = performance.now(); const server = new Date(serverNow).getTime(); const timer = setInterval(() => setNow(server + performance.now() - start), 1000); return () => clearInterval(timer); }, [serverNow]);
  const [selected, setSelected] = useState<QuizDeadlineAssignment | null>(null);
  const [reopen, setReopen] = useState(false); const [deadline, setDeadline] = useState('');
  const [busy, setBusy] = useState(false); const busyRef = useRef(false); const [error, setError] = useState('');
  if (!assignments.length) return null;
  return <div className="space-y-3"><ul className="space-y-2">{assignments.map(a => { const expired = a.dueAt !== null && new Date(a.dueAt).getTime() <= now; return <li key={a.id} className="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-border p-3"><div className="min-w-0"><p className="break-words text-sm font-medium">{a.classTitle}</p><p className="mt-1 text-xs text-muted-foreground">{manilaDate(a.dueAt)}</p>{expired ? <p className="mt-1 text-xs font-medium">Quiz Closed — Deadline Passed</p> : a.dueAt ? <p className="mt-1 text-xs text-muted-foreground">Open until deadline · {Math.max(1, Math.ceil((new Date(a.dueAt).getTime() - now) / 60000))} minutes remaining</p> : null}</div><Button className="min-h-11" variant={expired ? 'default' : 'outline'} onClick={() => { setSelected(a); setReopen(expired); setDeadline(expired ? '' : utcToManilaInput(a.dueAt)); setError(''); }}>{expired ? 'Reopen Quiz' : 'Set deadline'}</Button></li>; })}</ul>
    <Dialog open={selected !== null} onOpenChange={open => { if (!open && !busy) setSelected(null); }}><DialogContent><DialogHeader><DialogTitle>{reopen ? 'Reopen Quiz' : 'Quiz deadline'}</DialogTitle><DialogDescription>{quizTitle} · {selected?.classTitle}. This changes only this class assignment. Submitted attempts remain locked; unfinished attempts resume the original attempt.</DialogDescription></DialogHeader>
      <p className="text-sm">Previous deadline: {manilaDate(selected?.dueAt ?? null)}</p><form className="space-y-4" onSubmit={async e => { e.preventDefault(); if (!selected || busyRef.current) return; busyRef.current = true; setBusy(true); setError(''); try { const response = await fetch('/api/activities/quiz-deadline', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ assignment_id: selected.id, deadline_at: manilaInputToUtc(deadline), reopen }), signal: AbortSignal.timeout(30000) }); const result = await response.json(); if (!response.ok) throw new Error(result.error); setSelected(null); router.refresh(); } catch (err) { setError(err instanceof Error ? err.message : 'Deadline could not be saved.'); } finally { busyRef.current = false; setBusy(false); } }}><div className="space-y-2"><Label htmlFor="quiz-new-deadline">{reopen ? 'New future deadline' : 'Deadline (optional)'} — Asia/Manila</Label><Input id="quiz-new-deadline" className="min-h-11" type="datetime-local" required={reopen} disabled={busy} value={deadline} onChange={e => setDeadline(e.target.value)} /><p className="text-xs text-muted-foreground">{reopen ? 'A future date and time is required. No publication reason is needed.' : 'Leave blank for no deadline. The deadline is separate from any attempt timer.'}</p></div>{error ? <p role="alert" className="text-sm text-destructive">{error}</p> : null}<Button className="min-h-11" disabled={busy} type="submit">{busy ? 'Saving…' : reopen ? 'Confirm reopening' : 'Save deadline'}</Button></form>
    </DialogContent></Dialog>
  </div>;
}
