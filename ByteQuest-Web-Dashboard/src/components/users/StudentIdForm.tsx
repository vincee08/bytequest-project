"use client";

import React, { useId, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { Loader2, Lock, Save } from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

/**
 * Admin control for a learner's student ID. A saved value becomes
 * staff-managed (read-only in the learner app); clearing it hands control
 * back to the learner. The database audits every change.
 */
export function StudentIdForm({ userId, studentId, managed }: { userId: string; studentId: string | null; managed: boolean }) {
  const router = useRouter();
  const id = useId();
  const busyRef = useRef(false);
  const [value, setValue] = useState(studentId ?? "");
  const [busy, setBusy] = useState<"save" | "clear" | null>(null);
  const [error, setError] = useState("");

  async function submit(next: string | null, mode: "save" | "clear") {
    if (busyRef.current) return;
    busyRef.current = true; setBusy(mode); setError("");
    try {
      const response = await fetch(`/api/learners/${userId}/student-id`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ student_id: next }),
        signal: AbortSignal.timeout(20_000),
      });
      const data = await response.json().catch(() => null);
      if (!response.ok) throw new Error(data?.error ?? "The student ID could not be saved.");
      toast.success(next ? "Student ID saved and locked for the learner." : "Student ID cleared. The learner can enter it again.");
      if (!next) setValue("");
      router.refresh();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "The student ID could not be saved.");
    } finally {
      busyRef.current = false; setBusy(null);
    }
  }

  const trimmed = value.trim();
  return (
    <form
      className="space-y-3"
      onSubmit={(event) => { event.preventDefault(); if (trimmed) void submit(trimmed, "save"); }}
      aria-describedby={`${id}-help`}
    >
      <div className="flex flex-wrap items-center gap-2">
        <Label htmlFor={id}>Student ID</Label>
        {managed ? <Badge variant="default"><Lock className="mr-1 h-3 w-3" aria-hidden="true" />Staff-managed</Badge> : <Badge variant="outline">Set by learner</Badge>}
      </div>
      <Input id={id} value={value} maxLength={64} autoComplete="off" className="min-h-11 font-mono" disabled={busy !== null} onChange={(event) => setValue(event.target.value)} />
      <p id={`${id}-help`} className="text-xs leading-5 text-muted-foreground">
        Saving locks the ID in the learner app. Each student ID can belong to one learner only.
      </p>
      {error ? <p role="alert" className="text-sm text-destructive">{error}</p> : null}
      <div className="flex flex-wrap gap-2">
        <Button type="submit" className="min-h-11" disabled={busy !== null || !trimmed || (managed && trimmed === (studentId ?? ""))}>
          {busy === "save" ? <Loader2 className="mr-2 h-4 w-4 animate-spin" aria-hidden="true" /> : <Save className="mr-2 h-4 w-4" aria-hidden="true" />}
          {managed ? "Save student ID" : "Confirm and lock"}
        </Button>
        {studentId ? (
          <Button type="button" variant="outline" className="min-h-11" disabled={busy !== null} onClick={() => void submit(null, "clear")}>
            {busy === "clear" ? <Loader2 className="mr-2 h-4 w-4 animate-spin" aria-hidden="true" /> : null}
            Clear student ID
          </Button>
        ) : null}
      </div>
    </form>
  );
}
