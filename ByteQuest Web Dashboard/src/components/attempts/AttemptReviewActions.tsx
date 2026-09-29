"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Loader2 } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { createClient } from "@/lib/supabase/client";
import { buildCriterionAdjustment, type ReviewCriterion } from "@/lib/attempts/criterion-adjustment";
import type { Json } from "@/types/database.generated";

type Outcome = "competent" | "not_yet_competent";

interface ProvisionalRevision {
  totalValue: number | null;
  maxValue: number | null;
  percentage: number | null;
  outcome: "pending_tesda_validation" | Outcome;
  criterionValues: Json;
}

export function FinalizeAttemptForm({
  attemptId,
  provisional,
  scoringMethod,
  passingMethod,
  criteria,
}: {
  attemptId: string;
  provisional: ProvisionalRevision;
  scoringMethod: string | null;
  passingMethod: string | null;
  criteria: ReviewCriterion[];
}) {
  const router = useRouter();
  const [outcome, setOutcome] = useState<Outcome | "">(
    provisional.outcome === "pending_tesda_validation" ? "" : provisional.outcome,
  );
  const [reason, setReason] = useState("");
  const [remarks, setRemarks] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [overrides, setOverrides] = useState<Partial<Record<string, "satisfied" | "not_satisfied">>>({});
  const adjustment = buildCriterionAdjustment(provisional.criterionValues, criteria, overrides);
  const canEditCriteria = scoringMethod === "binary_sum" && passingMethod === "all_required" && adjustment !== null;
  const originalById = new Map(Array.isArray(provisional.criterionValues)
    ? provisional.criterionValues.filter((value): value is { [key: string]: Json | undefined } =>
      value !== null && typeof value === "object" && !Array.isArray(value))
      .map((value) => [String(value.criterion_id), value])
    : []);

  const setCriterionObservation = (criterionId: string, observation: "satisfied" | "not_satisfied") => {
    const next = { ...overrides, [criterionId]: observation };
    setOverrides(next);
    const recalculated = buildCriterionAdjustment(provisional.criterionValues, criteria, next);
    if (recalculated) setOutcome(recalculated.suggestedOutcome);
  };

  const handleSubmit = async (event: React.FormEvent) => {
    event.preventDefault();
    if (!outcome) {
      toast.error("Select the Instructor-reviewed competency outcome.");
      return;
    }

    const totalsChanged = canEditCriteria && adjustment !== null && (
      adjustment.totalValue !== provisional.totalValue || adjustment.maxValue !== provisional.maxValue
      || adjustment.percentage !== provisional.percentage || adjustment.changed
    );
    const changed = outcome !== provisional.outcome || totalsChanged;
    if (changed && reason.trim().length < 5) {
      toast.error("A clear reason is mandatory when changing the provisional result.");
      return;
    }

    setSubmitting(true);
    const { error } = await createClient().rpc("finalize_attempt", {
      p_attempt_id: attemptId,
      p_total_value: canEditCriteria ? adjustment!.totalValue : provisional.totalValue as number,
      p_max_value: canEditCriteria ? adjustment!.maxValue : provisional.maxValue as number,
      p_percentage: canEditCriteria ? adjustment!.percentage : provisional.percentage as number,
      p_outcome: outcome,
      p_criterion_values: canEditCriteria ? adjustment!.criterionValues : provisional.criterionValues,
      p_reason: reason.trim() || undefined,
      p_remarks: remarks.trim() || undefined,
    });
    if (error) {
      toast.error(error.message);
      setSubmitting(false);
      return;
    }

    toast.success(changed ? "Adjustment recorded and result finalized." : "Result finalized.");
    router.refresh();
  };

  return (
    <form onSubmit={handleSubmit} className="grid gap-4 sm:grid-cols-2">
      <div className="rounded-lg border border-border bg-muted/25 p-4 sm:col-span-2">
        <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
          Automated provisional evidence summary
        </p>
        <div className="mt-3 grid gap-3 sm:grid-cols-3">
          <div>
            <p className="text-xs text-muted-foreground">Criteria satisfied</p>
            <p className="mt-1 text-lg font-bold tabular-nums">
              {provisional.totalValue ?? "—"} / {provisional.maxValue ?? "—"}
            </p>
          </div>
          <div>
            <p className="text-xs text-muted-foreground">Decision method</p>
            <p className="mt-1 text-sm font-semibold">
              {scoringMethod === "binary_sum" ? "All required criteria" : scoringMethod ?? "Versioned rubric"}
            </p>
          </div>
          <div>
            <p className="text-xs text-muted-foreground">Automated outcome</p>
            <p className="mt-1 text-sm font-semibold capitalize">
              {provisional.outcome.replaceAll("_", " ")}
            </p>
          </div>
        </div>
        <p className="mt-3 text-xs leading-relaxed text-muted-foreground">
          The 1/0 values are technical encodings of SATISFIED / NOT SATISFIED. They are not TESDA weights or a TESDA passing percentage.
        </p>
      </div>
      {canEditCriteria ? (
        <div className="space-y-3 sm:col-span-2" aria-label="Criterion score correction">
          <div>
            <p className="text-sm font-semibold">Criterion-level correction</p>
            <p className="mt-1 text-xs text-muted-foreground">Change only a criterion whose evidence was reviewed incorrectly. The technical score is recalculated from the approved rubric; the original evaluation stays in history.</p>
          </div>
          {criteria.map((criterion) => {
            const original = originalById.get(criterion.id);
            const originalObservation = String(original?.observation ?? "not_evaluated");
            const selected = overrides[criterion.id] ?? originalObservation;
            return (
              <div key={criterion.id} className="grid gap-2 rounded-lg border border-border p-3 sm:grid-cols-[minmax(0,1fr)_13rem] sm:items-center">
                <div>
                  <p className="text-sm font-medium">{criterion.code} · {criterion.title}</p>
                  <p className="text-xs text-muted-foreground">Original: {originalObservation.replaceAll("_", " ")} · {String(original?.score_value ?? "—")} / {criterion.maxValue}</p>
                </div>
                <div className="space-y-1">
                  <Label htmlFor={`criterion-${criterion.id}`}>Reviewed observation</Label>
                  <Select value={selected} onValueChange={(value) => setCriterionObservation(criterion.id, value as "satisfied" | "not_satisfied")}>
                    <SelectTrigger id={`criterion-${criterion.id}`} aria-label={`Reviewed observation for ${criterion.title}`}><SelectValue placeholder="Review criterion" /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="satisfied">Satisfied</SelectItem>
                      <SelectItem value="not_satisfied">Not satisfied</SelectItem>
                      {selected === "not_evaluated" || selected === "requires_review" ? <SelectItem value={selected} disabled>{selected.replaceAll("_", " ")}</SelectItem> : null}
                    </SelectContent>
                  </Select>
                </div>
              </div>
            );
          })}
          <p className="text-sm font-medium" aria-live="polite">Reviewed technical total: {adjustment?.totalValue} / {adjustment?.maxValue} · {adjustment?.percentage}% · Suggested outcome: {adjustment?.suggestedOutcome.replaceAll("_", " ")}</p>
        </div>
      ) : null}
      <div className="space-y-2 sm:col-span-2">
        <Label htmlFor="review-outcome">Instructor-reviewed outcome</Label>
        <Select value={outcome} onValueChange={(value) => setOutcome(value as Outcome)}>
          <SelectTrigger id="review-outcome"><SelectValue placeholder="Select outcome" /></SelectTrigger>
          <SelectContent>
            <SelectItem value="competent">Competent</SelectItem>
            <SelectItem value="not_yet_competent">Not yet competent</SelectItem>
          </SelectContent>
        </Select>
      </div>
      <div className="space-y-2 sm:col-span-2"><Label htmlFor="adjustment-reason">Adjustment reason</Label><Textarea id="adjustment-reason" value={reason} onChange={(event) => setReason(event.target.value)} placeholder="Required only if any provisional value is changed" rows={3} /></div>
      <div className="space-y-2 sm:col-span-2"><Label htmlFor="review-remarks">Instructor remarks</Label><Textarea id="review-remarks" value={remarks} onChange={(event) => setRemarks(event.target.value)} rows={3} /></div>
      <div className="sm:col-span-2"><Button type="submit" disabled={submitting}>{submitting ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : null}Finalize result</Button></div>
    </form>
  );
}

export function ReleaseAttemptForm({ attemptId }: { attemptId: string }) {
  const router = useRouter();
  const [reason, setReason] = useState("");
  const [submitting, setSubmitting] = useState(false);

  const handleSubmit = async (event: React.FormEvent) => {
    event.preventDefault();
    setSubmitting(true);
    const { error } = await createClient().rpc("release_attempt", {
      p_attempt_id: attemptId,
      p_release_reason: reason.trim() || undefined,
    });
    if (error) {
      toast.error(error.message);
      setSubmitting(false);
      return;
    }
    toast.success("Final result released to the learner. Projection and reward event were applied once.");
    router.refresh();
  };

  return (
    <form onSubmit={handleSubmit} className="space-y-3">
      <div className="space-y-2"><Label htmlFor="release-reason">Release note (optional)</Label><Textarea id="release-reason" value={reason} onChange={(event) => setReason(event.target.value)} rows={3} /></div>
      <Button type="submit" disabled={submitting}>{submitting ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : null}Release final result</Button>
    </form>
  );
}
