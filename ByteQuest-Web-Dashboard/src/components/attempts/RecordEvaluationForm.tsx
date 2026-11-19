"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Loader2 } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { buildCriterionAdjustment, type ReviewCriterion } from "@/lib/attempts/criterion-adjustment";
import type { Json } from "@/types/database.generated";

type Outcome = "competent" | "not_yet_competent";

/**
 * Evaluate step (evaluated -> under_review). The server rescores any
 * criterion override from the approved rubric; this form only states which
 * criteria the instructor reviewed differently, the outcome and why.
 */
export function RecordEvaluationForm({
  attemptId,
  provisional,
  scoringMethod,
  passingMethod,
  criteria,
}: {
  attemptId: string;
  provisional: { totalValue: number | null; maxValue: number | null; outcome: Outcome | "pending_tesda_validation"; criterionValues: Json };
  scoringMethod: string | null;
  passingMethod: string | null;
  criteria: ReviewCriterion[];
}) {
  const router = useRouter();
  const automatedOutcome = provisional.outcome === "pending_tesda_validation" ? "" : provisional.outcome;
  const [outcome, setOutcome] = useState<Outcome | "">(automatedOutcome);
  const [overrides, setOverrides] = useState<Partial<Record<string, "satisfied" | "not_satisfied">>>({});
  const [reason, setReason] = useState("");
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const adjustment = buildCriterionAdjustment(provisional.criterionValues, criteria, overrides);
  const canEditCriteria = scoringMethod === "binary_sum" && passingMethod === "all_required" && adjustment !== null;
  const original = new Map(Array.isArray(provisional.criterionValues)
    ? provisional.criterionValues
      .filter((value): value is { [key: string]: Json | undefined } => value !== null && typeof value === "object" && !Array.isArray(value))
      .map((value) => [String(value.criterion_id), String(value.observation ?? "not_evaluated")])
    : []);
  const changedCriteria = Object.entries(overrides).filter(([id, observation]) => observation && observation !== original.get(id));
  const changed = changedCriteria.length > 0 || (outcome !== "" && outcome !== automatedOutcome);

  const choose = (criterionId: string, observation: "satisfied" | "not_satisfied") => {
    const next = { ...overrides, [criterionId]: observation };
    setOverrides(next);
    const recalculated = buildCriterionAdjustment(provisional.criterionValues, criteria, next);
    if (recalculated) setOutcome(recalculated.suggestedOutcome);
  };

  const submit = async (event: React.FormEvent) => {
    event.preventDefault();
    if (busy) return;
    setError("");
    if (!outcome) { setError("Select the instructor-reviewed competency outcome."); return; }
    if (changed && reason.trim().length < 5) { setError("Give a clear reason (at least 5 characters) for changing the automated result."); return; }
    setBusy(true);
    try {
      const response = await fetch("/api/evaluations", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        signal: AbortSignal.timeout(35000),
        body: JSON.stringify({
          kind: "technical",
          action: "record_evaluation",
          attempt_id: attemptId,
          criterion_overrides: changedCriteria.map(([criterion_id, observation]) => ({ criterion_id, observation })),
          outcome,
          ...(reason.trim() ? { reason: reason.trim() } : {}),
          ...(note.trim() ? { note: note.trim() } : {}),
        }),
      });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error ?? "The evaluation could not be recorded.");
      toast.success(changed ? "Evaluation recorded with your reasoned adjustment. Finalize it next." : "Evaluation recorded. Finalize it next.");
      router.refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "The evaluation could not be recorded.");
      setBusy(false);
    }
  };

  return (
    <form onSubmit={submit} className="space-y-4">
      <div className="rounded-lg border border-border bg-muted/25 p-4">
        <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Automated evaluation</p>
        <p className="mt-2 text-lg font-bold tabular-nums">{provisional.totalValue ?? "—"} / {provisional.maxValue ?? "—"}</p>
        <p className="text-sm capitalize text-muted-foreground">{provisional.outcome.replaceAll("_", " ")}</p>
      </div>
      {canEditCriteria ? (
        <fieldset className="space-y-3">
          <legend className="text-sm font-semibold">Review each criterion</legend>
          <p className="text-xs text-muted-foreground">Change a criterion only when the recorded evidence was judged incorrectly. The score is recalculated from the approved rubric; the automated result stays in the history.</p>
          {criteria.map((criterion) => {
            const automated = original.get(criterion.id) ?? "not_evaluated";
            const selected = overrides[criterion.id] ?? automated;
            return (
              <div key={criterion.id} className="grid gap-2 rounded-lg border border-border p-3 sm:grid-cols-[minmax(0,1fr)_13rem] sm:items-center">
                <div>
                  <p className="text-sm font-medium">{criterion.code} · {criterion.title}</p>
                  <p className="text-xs text-muted-foreground">Automated: {automated.replaceAll("_", " ")}</p>
                </div>
                <div className="space-y-1">
                  <Label htmlFor={`evaluate-${criterion.id}`}>Reviewed observation</Label>
                  <select
                    id={`evaluate-${criterion.id}`}
                    value={selected}
                    onChange={(event) => choose(criterion.id, event.target.value as "satisfied" | "not_satisfied")}
                    className="h-11 w-full rounded-lg border border-input bg-card px-3 text-sm"
                  >
                    <option value="satisfied">Satisfied</option>
                    <option value="not_satisfied">Not satisfied</option>
                    {selected === "not_evaluated" || selected === "requires_review" ? <option value={selected} disabled>{selected.replaceAll("_", " ")}</option> : null}
                  </select>
                </div>
              </div>
            );
          })}
          <p className="text-sm font-medium" aria-live="polite">Reviewed total: {adjustment?.totalValue} / {adjustment?.maxValue} · {adjustment?.percentage}%</p>
        </fieldset>
      ) : null}
      <div className="space-y-2">
        <Label htmlFor="evaluate-outcome">Instructor-reviewed outcome</Label>
        <select id="evaluate-outcome" value={outcome} onChange={(event) => setOutcome(event.target.value as Outcome)} className="h-11 w-full rounded-lg border border-input bg-card px-3 text-sm">
          <option value="" disabled>Select outcome</option>
          <option value="competent">Competent</option>
          <option value="not_yet_competent">Not yet competent</option>
        </select>
      </div>
      <div className="space-y-2">
        <Label htmlFor="evaluate-reason">Reason for any change {changed ? "(required)" : "(only if you change the result)"}</Label>
        <Textarea id="evaluate-reason" value={reason} onChange={(event) => setReason(event.target.value)} rows={3} maxLength={1000} />
      </div>
      <div className="space-y-2">
        <Label htmlFor="evaluate-note">Evaluation note (optional)</Label>
        <Textarea id="evaluate-note" value={note} onChange={(event) => setNote(event.target.value)} rows={2} maxLength={2000} />
      </div>
      {error ? <p role="alert" className="text-sm text-destructive">{error}</p> : null}
      <Button type="submit" className="min-h-11" disabled={busy}>
        {busy ? <Loader2 className="mr-2 h-4 w-4 animate-spin" aria-hidden="true" /> : null}
        Record evaluation
      </Button>
    </form>
  );
}
