"use client";

import React, { useState } from "react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group";
import { Textarea } from "@/components/ui/textarea";

export type EvaluationResult = "passed" | "needs_revision";

/** Admin evaluation of a submitted revision: result plus notes (at least 10 characters). */
export function EvaluationDialog({
  open,
  revisionLabel,
  saving,
  onCancel,
  onSubmit,
}: {
  open: boolean;
  revisionLabel: string;
  saving: boolean;
  onCancel: () => void;
  onSubmit: (result: EvaluationResult, notes: string) => void;
}) {
  // The parent remounts this dialog (key) for each evaluation.
  const [result, setResult] = useState<EvaluationResult>("passed");
  const [notes, setNotes] = useState("");
  const notesValid = notes.trim().length >= 10;
  return (
    <Dialog open={open} onOpenChange={(next) => (!next && !saving ? onCancel() : undefined)}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>Evaluate {revisionLabel}</DialogTitle>
          <DialogDescription>
            Record whether the lesson is accurate and aligned with its learning outcomes. Notes are kept in the publication history.
          </DialogDescription>
        </DialogHeader>
        <form
          className="space-y-4"
          onSubmit={(event) => {
            event.preventDefault();
            if (notesValid) onSubmit(result, notes.trim());
          }}
        >
          <RadioGroup value={result} onValueChange={(value) => setResult(value as EvaluationResult)} aria-label="Evaluation result">
            <label className="flex min-h-11 cursor-pointer items-center gap-3 rounded-lg border border-border p-3 text-sm">
              <RadioGroupItem value="passed" id="evaluation-passed" />
              <span>
                <span className="font-semibold">Passed</span> — ready to be finalized
              </span>
            </label>
            <label className="flex min-h-11 cursor-pointer items-center gap-3 rounded-lg border border-border p-3 text-sm">
              <RadioGroupItem value="needs_revision" id="evaluation-needs-revision" />
              <span>
                <span className="font-semibold">Needs revision</span> — return it to the author
              </span>
            </label>
          </RadioGroup>
          <div className="space-y-1.5">
            <Label htmlFor="evaluation-notes">Evaluation notes</Label>
            <Textarea
              id="evaluation-notes"
              value={notes}
              rows={4}
              maxLength={4000}
              aria-invalid={notes.length > 0 && !notesValid}
              onChange={(event) => setNotes(event.target.value)}
            />
            <p className={notes.length > 0 && !notesValid ? "text-xs text-destructive" : "text-xs text-muted-foreground"}>
              At least 10 characters.
            </p>
          </div>
          <DialogFooter className="gap-2">
            <Button type="button" variant="outline" onClick={onCancel} disabled={saving}>
              Cancel
            </Button>
            <Button type="submit" disabled={saving || !notesValid}>
              {saving ? "Saving…" : "Record evaluation"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
