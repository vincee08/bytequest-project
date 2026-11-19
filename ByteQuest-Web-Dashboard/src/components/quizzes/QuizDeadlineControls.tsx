"use client";

import { useEffect, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { manilaDate, manilaInputToUtc, utcToManilaInput } from '@/lib/activities/dates';

export type QuizDeadlineAssignment = { id: string; classTitle: string; dueAt: string | null };
type Mode = 'deadline' | 'reopen' | 'close';

async function postDeadline(body: Record<string, unknown>) {
  const response = await fetch('/api/activities/quiz-deadline', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body), signal: AbortSignal.timeout(30000) });
  const result = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(result.error || 'Deadline could not be saved.');
}

export function QuizDeadlineControls({ assignments, quizTitle, serverNow }: { assignments: QuizDeadlineAssignment[]; quizTitle: string; serverNow: string }) {
  const router = useRouter();
  const [now, setNow] = useState(new Date(serverNow).getTime());
  useEffect(() => { const start = performance.now(); const server = new Date(serverNow).getTime(); const timer = setInterval(() => setNow(server + performance.now() - start), 1000); return () => clearInterval(timer); }, [serverNow]);
  const [selected, setSelected] = useState<QuizDeadlineAssignment | null>(null);
  const [mode, setMode] = useState<Mode>('deadline'); const [deadline, setDeadline] = useState('');
  const [busy, setBusy] = useState(false); const busyRef = useRef(false); const [error, setError] = useState('');
  if (!assignments.length) return null;
  const open = (assignment: QuizDeadlineAssignment, next: Mode) => { setSelected(assignment); setMode(next); setDeadline(next === 'deadline' ? utcToManilaInput(assignment.dueAt) : ''); setError(''); };
  async function submit(event?: React.FormEvent) {
    event?.preventDefault();
    if (!selected || busyRef.current) return;
    busyRef.current = true; setBusy(true); setError('');
    try {
      await postDeadline(mode === 'close'
        ? { assignment_id: selected.id, deadline_at: null, reopen: false, close_now: true }
        : { assignment_id: selected.id, deadline_at: manilaInputToUtc(deadline), reopen: mode === 'reopen' });
      setSelected(null); router.refresh();
    } catch (err) { setError(err instanceof Error ? err.message : 'Deadline could not be saved.'); }
    finally { busyRef.current = false; setBusy(false); }
  }
  return <div className="space-y-3"><ul className="space-y-2">{assignments.map(a => { const expired = a.dueAt !== null && new Date(a.dueAt).getTime() <= now; return <li key={a.id} className="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-border p-3"><div className="min-w-0"><p className="break-words text-sm font-medium">{a.classTitle}</p><p className="mt-1 text-xs text-muted-foreground">{manilaDate(a.dueAt)}</p>{expired ? <p className="mt-1 text-xs font-medium">Quiz Closed — Deadline Passed</p> : a.dueAt ? <p className="mt-1 text-xs text-muted-foreground">Open until deadline · {Math.max(1, Math.ceil((new Date(a.dueAt).getTime() - now) / 60000))} minutes remaining</p> : <p className="mt-1 text-xs text-muted-foreground">Open · no deadline</p>}</div><div className="flex flex-wrap gap-2">{!expired ? <Button className="min-h-11" variant="outline" onClick={() => open(a, 'close')}>Close now</Button> : null}<Button className="min-h-11" variant={expired ? 'default' : 'outline'} onClick={() => open(a, expired ? 'reopen' : 'deadline')}>{expired ? 'Reopen Quiz' : 'Set deadline'}</Button></div></li>; })}</ul>
    <Dialog open={selected !== null} onOpenChange={value => { if (!value && !busy) setSelected(null); }}><DialogContent><DialogHeader><DialogTitle>{mode === 'close' ? 'Close this quiz now?' : mode === 'reopen' ? 'Reopen Quiz' : 'Quiz deadline'}</DialogTitle><DialogDescription>{quizTitle} · {selected?.classTitle}. This changes only this class assignment. {mode === 'close' ? 'The deadline becomes the current server time. Attempts in progress are submitted automatically with their saved answers; learners who have not started can no longer start.' : mode === 'reopen' ? 'Attempts already submitted or auto-submitted stay final. Learners who never started can take the quiz.' : 'An extension before the deadline also extends attempts in progress.'}</DialogDescription></DialogHeader>
      <p className="text-sm">Current deadline: {manilaDate(selected?.dueAt ?? null)}</p>
      {mode === 'close' ? <div className="space-y-3">{error ? <p role="alert" className="text-sm text-destructive">{error}</p> : null}<div className="flex flex-wrap justify-end gap-2"><Button variant="outline" className="min-h-11" disabled={busy} onClick={() => setSelected(null)}>Cancel</Button><Button className="min-h-11" variant="destructive" disabled={busy} onClick={() => submit()}>{busy ? 'Closing…' : 'Close quiz now'}</Button></div></div>
      : <form className="space-y-4" onSubmit={submit}><div className="space-y-2"><Label htmlFor="quiz-new-deadline">{mode === 'reopen' ? 'New future deadline' : 'Deadline (optional)'} — Asia/Manila</Label><Input id="quiz-new-deadline" className="min-h-11" type="datetime-local" required={mode === 'reopen'} disabled={busy} value={deadline} onChange={e => setDeadline(e.target.value)} /><p className="text-xs text-muted-foreground">{mode === 'reopen' ? 'A future date and time is required. No publication reason is needed.' : 'Leave blank for no deadline. At the deadline, saved answers are submitted automatically.'}</p></div>{error ? <p role="alert" className="text-sm text-destructive">{error}</p> : null}<Button className="min-h-11" disabled={busy} type="submit">{busy ? 'Saving…' : mode === 'reopen' ? 'Confirm reopening' : 'Save deadline'}</Button></form>}
    </DialogContent></Dialog>
  </div>;
}
