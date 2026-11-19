"use client";

import React, { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { Clock3, Loader2, XCircle } from "lucide-react";
import { toast } from "sonner";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from "@/components/ui/alert-dialog";
import { Button } from "@/components/ui/button";

export type PendingRosterEntry = {
  id: string;
  name: string;
  email: string;
  studentId: string | null;
  courseSection: string | null;
  createdAt: string;
};

const dateFormat = new Intl.DateTimeFormat("en-PH", { dateStyle: "medium", timeZone: "Asia/Manila" });

/** Pending roster entries of one class, each cancellable by the owning instructor. */
export function PendingRosterEntries({ classId, entries, canManage }: { classId: string; entries: PendingRosterEntry[]; canManage: boolean }) {
  const router = useRouter();
  const busyRef = useRef(false);
  const [busyId, setBusyId] = useState<string | null>(null);

  async function cancel(entry: PendingRosterEntry) {
    if (busyRef.current) return;
    busyRef.current = true; setBusyId(entry.id);
    try {
      const response = await fetch(`/api/roster/${classId}/entries`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "cancel", entry_id: entry.id }),
        signal: AbortSignal.timeout(20_000),
      });
      const data = await response.json().catch(() => null);
      if (!response.ok) throw new Error(data?.error ?? "The roster entry could not be cancelled.");
      toast.success(`${entry.email} will no longer be enrolled automatically.`);
      router.refresh();
    } catch (cause) {
      toast.error(cause instanceof Error ? cause.message : "The roster entry could not be cancelled.");
    } finally {
      busyRef.current = false; setBusyId(null);
    }
  }

  if (!entries.length) {
    return <p className="px-5 py-8 text-center text-sm text-muted-foreground">No pending roster entries. Imported emails without an account appear here until the learner signs up.</p>;
  }

  return (
    <ul className="divide-y divide-border">
      {entries.map((entry) => (
        <li key={entry.id} className="flex flex-col gap-3 px-5 py-3.5 sm:flex-row sm:items-center sm:justify-between">
          <div className="flex min-w-0 items-start gap-3">
            <Clock3 className="mt-0.5 h-4 w-4 shrink-0 text-primary" aria-hidden="true" />
            <div className="min-w-0">
              <p className="text-sm font-medium">{entry.name}</p>
              <p className="mt-0.5 break-all text-xs text-muted-foreground">
                {entry.email}{entry.studentId ? ` · ID ${entry.studentId}` : ""}{entry.courseSection ? ` · ${entry.courseSection}` : ""} · imported {dateFormat.format(new Date(entry.createdAt))}
              </p>
            </div>
          </div>
          {canManage ? (
            <AlertDialog>
              <AlertDialogTrigger asChild>
                <Button type="button" variant="ghost" size="sm" className="min-h-11 self-start text-destructive hover:text-destructive sm:self-auto" disabled={busyId !== null}>
                  {busyId === entry.id ? <Loader2 className="mr-2 h-4 w-4 animate-spin" aria-hidden="true" /> : <XCircle className="mr-2 h-4 w-4" aria-hidden="true" />}
                  Cancel entry
                </Button>
              </AlertDialogTrigger>
              <AlertDialogContent>
                <AlertDialogHeader>
                  <AlertDialogTitle>Cancel this pending roster entry?</AlertDialogTitle>
                  <AlertDialogDescription>
                    {entry.name} ({entry.email}) will not be enrolled automatically when signing up. The entry stays in the class history and can be restored by importing the roster again.
                  </AlertDialogDescription>
                </AlertDialogHeader>
                <AlertDialogFooter>
                  <AlertDialogCancel>Keep entry</AlertDialogCancel>
                  <AlertDialogAction onClick={() => void cancel(entry)}>Cancel entry</AlertDialogAction>
                </AlertDialogFooter>
              </AlertDialogContent>
            </AlertDialog>
          ) : null}
        </li>
      ))}
    </ul>
  );
}
