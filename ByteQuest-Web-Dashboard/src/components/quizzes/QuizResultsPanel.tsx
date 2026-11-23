"use client";

import React, { useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { Bar, BarChart, CartesianGrid, XAxis, YAxis } from "recharts";
import { CheckCircle2, ClipboardCheck, Loader2, Send } from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  ChartContainer,
  ChartTooltip,
  ChartTooltipContent,
  type ChartConfig,
} from "@/components/ui/chart";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { useReducedMotion } from "@/hooks/use-reduced-motion";
import { itemTypeLabels, type RubricRow } from "@/lib/quizzes/authoring";
import { formatDateTime } from "@/lib/analytics/format";
import {
  evaluationStatusLabels,
  questionCorrectness,
  quizResultStats,
  submissionKindLabels,
} from "@/lib/quizzes/results";
import type {
  EvaluationStatus,
  QuizItemResultJson,
  SubmissionKind,
} from "@/lib/quizzes/types";

export interface EssayForScoring {
  itemId: string;
  prompt: string;
  scenario: string | null;
  rubric: RubricRow[];
  points: number;
  answer: string | null;
  latest: {
    criterionScores: Record<string, number>;
    total: number;
    feedback: string | null;
    evaluatedAt: string;
  } | null;
  scoreCount: number;
}

export interface ResultAttempt {
  id: string;
  learnerId: string;
  learner: string;
  /** Shown under the name; null when the name line already is the email. */
  learnerEmail: string | null;
  classTitle: string;
  versionNumber: number;
  status: "in_progress" | "submitted" | "completed";
  evaluationStatus: EvaluationStatus;
  submissionKind: SubmissionKind;
  submittedAt: string | null;
  /** Final percent for statistics (null while evaluation is pending). */
  percent: number | null;
  score: number | null;
  maxScore: number | null;
  items: QuizItemResultJson[];
  essays: EssayForScoring[];
}

const distributionConfig = {
  count: { label: "Learners", color: "hsl(var(--chart-1))" },
} satisfies ChartConfig;

const stageVariant: Record<EvaluationStatus, "default" | "secondary" | "outline"> = {
  not_required: "secondary",
  pending: "default",
  evaluated: "default",
  finalized: "outline",
  released: "secondary",
};

const formatNumber = (value: number | null, suffix = "") =>
  value === null ? "—" : `${Number.isInteger(value) ? value : value.toFixed(1)}${suffix}`;

async function postEvaluation(body: Record<string, unknown>) {
  const response = await fetch("/api/quizzes/evaluation", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(30000),
  });
  const result = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(result.error || "The evaluation could not be saved.");
  return result.result as Record<string, unknown>;
}

function Stat({ label, value, note }: { label: string; value: string; note: string }) {
  return (
    <div className="rounded-lg border border-border p-3">
      <p className="text-xs font-medium text-muted-foreground">{label}</p>
      <p className="mt-1 text-xl font-semibold tabular-nums">{value}</p>
      <p className="mt-1 text-xs text-muted-foreground">{note}</p>
    </div>
  );
}

export function QuizResultsPanel({
  attempts,
  enrolled,
  initialAttemptId,
}: {
  attempts: ResultAttempt[];
  enrolled: number;
  initialAttemptId?: string;
}) {
  const router = useRouter();
  const reducedMotion = useReducedMotion();
  const [selected, setSelected] = useState<string[]>([]);
  const [scoring, setScoring] = useState<ResultAttempt | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const busyRef = useRef(false);
  const [message, setMessage] = useState<{ error: boolean; text: string } | null>(null);
  const opened = useRef(false);
  useEffect(() => {
    if (opened.current || !initialAttemptId) return;
    opened.current = true;
    const attempt = attempts.find((item) => item.id === initialAttemptId);
    if (attempt?.essays.length) setScoring(attempt);
    document
      .getElementById(`quiz-attempt-${initialAttemptId}`)
      ?.scrollIntoView({ block: "center" });
  }, [attempts, initialAttemptId]);
  useEffect(() => {
    // Keep an open scoring dialog in sync after a refresh.
    setScoring((current) =>
      current ? (attempts.find((item) => item.id === current.id) ?? null) : null,
    );
  }, [attempts]);

  const stats = useMemo(() => quizResultStats(attempts, enrolled), [attempts, enrolled]);
  const completed = attempts.filter((attempt) => attempt.status === "completed");
  const essayScores = useMemo(() => {
    const map = new Map<string, { points: number; max: number }[]>();
    for (const attempt of completed) {
      for (const essay of attempt.essays) {
        if (!essay.latest) continue;
        map.set(essay.itemId, [
          ...(map.get(essay.itemId) ?? []),
          { points: essay.latest.total, max: essay.points },
        ]);
      }
    }
    return map;
  }, [completed]);
  const questions = useMemo(
    () => questionCorrectness(completed, essayScores),
    [completed, essayScores],
  );
  const finalizable = selected.filter(
    (id) => attempts.find((attempt) => attempt.id === id)?.evaluationStatus === "evaluated",
  );
  const releasable = selected.filter(
    (id) => attempts.find((attempt) => attempt.id === id)?.evaluationStatus === "finalized",
  );

  async function run(key: string, body: Record<string, unknown>, success: string) {
    if (busyRef.current) return false;
    busyRef.current = true;
    setBusy(key);
    setMessage(null);
    try {
      await postEvaluation(body);
      setMessage({ error: false, text: success });
      toast.success(success);
      router.refresh();
      return true;
    } catch (error) {
      const text = error instanceof Error ? error.message : "The evaluation could not be saved.";
      setMessage({ error: true, text });
      toast.error(text);
      return false;
    } finally {
      busyRef.current = false;
      setBusy(null);
    }
  }

  async function bulk(action: "finalize" | "release", ids: string[]) {
    if (!ids.length) return;
    const verb = action === "finalize" ? "Finalize" : "Release";
    if (
      !window.confirm(
        `${verb} ${ids.length} result${ids.length === 1 ? "" : "s"}? ${
          action === "finalize"
            ? "Final totals are locked."
            : "Learners will see their scores and feedback."
        }`,
      )
    )
      return;
    if (
      await run(
        action,
        { action, attempt_ids: ids },
        `${ids.length} result${ids.length === 1 ? "" : "s"} ${action === "finalize" ? "finalized" : "released"}.`,
      )
    )
      setSelected([]);
  }

  if (!attempts.length) {
    return (
      <p className="mt-5 text-sm text-muted-foreground">
        No learner attempts yet. Published assignments appear in enrolled
        learners’ quizzes.
      </p>
    );
  }

  return (
    <div className="space-y-6">
      {message ? (
        <p
          role={message.error ? "alert" : "status"}
          className={`rounded-lg border p-3 text-sm ${message.error ? "border-destructive/40 text-destructive" : "border-border bg-muted/30"}`}
        >
          {message.text}
        </p>
      ) : null}
      <section aria-labelledby="quiz-stats-heading" className="space-y-3">
        <h3 id="quiz-stats-heading" className="text-sm font-semibold">
          Class performance
        </h3>
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <Stat label="Participants" value={String(stats.participants)} note={`${stats.inProgress} still in progress`} />
          <Stat
            label="Completion rate"
            value={formatNumber(stats.completionRate, "%")}
            note={`${stats.submitted} of ${stats.enrolled} enrolled learners submitted`}
          />
          <Stat
            label="Average score"
            value={formatNumber(stats.average, "%")}
            note={`Final scores only (${stats.finalScores})`}
          />
          <Stat
            label="Highest · lowest"
            value={`${formatNumber(stats.highest, "%")} · ${formatNumber(stats.lowest, "%")}`}
            note={`${stats.pendingEvaluation} awaiting evaluation excluded`}
          />
        </div>
        {stats.autoSubmitted ? (
          <p className="text-xs text-muted-foreground">
            {stats.autoSubmitted} attempt{stats.autoSubmitted === 1 ? " was" : "s were"} submitted automatically at the deadline or time limit with saved answers.
          </p>
        ) : null}
      </section>

      <section aria-labelledby="quiz-distribution-heading" className="space-y-2">
        <h3 id="quiz-distribution-heading" className="text-sm font-semibold">
          Score distribution
        </h3>
        {stats.finalScores ? (
          <>
            <ChartContainer
              config={distributionConfig}
              className="h-[240px] w-full aspect-auto"
              aria-label="Number of learners in each score band"
            >
              <BarChart data={stats.distribution} margin={{ left: 4, right: 12, top: 8, bottom: 0 }} accessibilityLayer>
                <CartesianGrid vertical={false} strokeDasharray="3 3" />
                <XAxis dataKey="label" tickLine={false} axisLine={false} />
                <YAxis allowDecimals={false} tickLine={false} axisLine={false} width={28} />
                <ChartTooltip content={<ChartTooltipContent hideLabel />} />
                <Bar dataKey="count" fill="var(--color-count)" radius={[6, 6, 0, 0]} maxBarSize={52} isAnimationActive={!reducedMotion} />
              </BarChart>
            </ChartContainer>
            <details className="text-xs text-muted-foreground">
              <summary className="cursor-pointer font-medium text-foreground">View distribution data</summary>
              <table className="mt-2 w-full text-left">
                <thead><tr><th className="py-1">Score band</th><th className="py-1">Learners</th></tr></thead>
                <tbody>
                  {stats.distribution.map((band) => (
                    <tr key={band.label} className="border-t border-border">
                      <td className="py-1">{band.label}</td>
                      <td className="py-1 tabular-nums">{band.count}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </details>
          </>
        ) : (
          <p className="text-sm text-muted-foreground">
            The distribution appears once results are final (immediate results,
            or instructor-release results after Finalize).
          </p>
        )}
      </section>

      <section aria-labelledby="quiz-question-heading" className="space-y-2">
        <h3 id="quiz-question-heading" className="text-sm font-semibold">
          Per-question results
        </h3>
        <div className="overflow-x-auto rounded-lg border border-border">
          <table className="w-full min-w-[560px] text-left text-sm">
            <thead className="bg-muted/40 text-xs text-muted-foreground">
              <tr>
                <th className="px-3 py-2">#</th>
                <th className="px-3 py-2">Question</th>
                <th className="px-3 py-2">Type</th>
                <th className="px-3 py-2">Correct / score</th>
                <th className="px-3 py-2">Answered</th>
              </tr>
            </thead>
            <tbody>
              {questions.map((question, index) => (
                <tr key={question.itemId} className="border-t border-border align-top">
                  <td className="px-3 py-2 tabular-nums">{index + 1}</td>
                  <td className="max-w-md px-3 py-2"><span className="line-clamp-2 break-words">{question.prompt}</span></td>
                  <td className="px-3 py-2">{itemTypeLabels[question.type as keyof typeof itemTypeLabels] ?? question.type}</td>
                  <td className="px-3 py-2 tabular-nums">
                    {question.type === "scenario_essay"
                      ? question.rate === null ? "Not scored yet" : `${formatNumber(question.rate, "%")} of rubric points`
                      : `${formatNumber(question.rate, "%")} (${question.correct}/${question.responses})`}
                  </td>
                  <td className="px-3 py-2 tabular-nums">{question.answered}/{question.responses}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      <section aria-labelledby="quiz-attempts-heading" className="space-y-3">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <h3 id="quiz-attempts-heading" className="text-sm font-semibold">
            Learner attempts · Evaluate → Finalize → Release
          </h3>
          <div className="flex flex-wrap gap-2">
            <Button
              variant="outline"
              className="min-h-11"
              disabled={busy !== null || !finalizable.length}
              onClick={() => bulk("finalize", finalizable)}
            >
              <ClipboardCheck className="mr-2 h-4 w-4" aria-hidden="true" />
              Finalize selected ({finalizable.length})
            </Button>
            <Button
              className="min-h-11"
              disabled={busy !== null || !releasable.length}
              onClick={() => bulk("release", releasable)}
            >
              <Send className="mr-2 h-4 w-4" aria-hidden="true" />
              Release selected ({releasable.length})
            </Button>
          </div>
        </div>
        <ul className="divide-y divide-border rounded-lg border border-border">
          {attempts.map((attempt) => {
            const selectable =
              attempt.evaluationStatus === "evaluated" || attempt.evaluationStatus === "finalized";
            return (
              <li
                key={attempt.id}
                id={`quiz-attempt-${attempt.id}`}
                className={`flex flex-wrap items-center gap-3 p-3 ${attempt.id === initialAttemptId ? "bg-primary/5" : ""}`}
              >
                <label className="flex min-h-11 min-w-11 items-center justify-center">
                  <input
                    type="checkbox"
                    className="h-4 w-4 accent-primary"
                    disabled={!selectable}
                    checked={selected.includes(attempt.id)}
                    onChange={(event) =>
                      setSelected((current) =>
                        event.target.checked
                          ? [...current, attempt.id]
                          : current.filter((id) => id !== attempt.id),
                      )
                    }
                    aria-label={`Select ${attempt.learner} for finalize or release`}
                  />
                </label>
                <div className="min-w-0 flex-1">
                  <p className="break-words text-sm font-medium">{attempt.learner}</p>
                  {attempt.learnerEmail ? (
                    <p className="break-all text-xs text-muted-foreground">{attempt.learnerEmail}</p>
                  ) : null}
                  <p className="text-xs text-muted-foreground">
                    {attempt.classTitle} · v{attempt.versionNumber}
                    {attempt.submittedAt ? ` · ${formatDateTime(attempt.submittedAt)}` : ""}
                  </p>
                  {attempt.status === "completed" && attempt.submissionKind !== "learner" ? (
                    <p className="text-xs font-medium text-amber-800 dark:text-amber-300">
                      {submissionKindLabels[attempt.submissionKind]}
                    </p>
                  ) : null}
                </div>
                <div className="flex flex-wrap items-center gap-2 text-sm">
                  {attempt.status === "completed" ? (
                    <>
                      <span className="tabular-nums">
                        {attempt.score !== null && attempt.maxScore
                          ? `${formatNumber(attempt.score)}/${formatNumber(attempt.maxScore)}`
                          : "Score pending"}
                      </span>
                      <Badge variant={stageVariant[attempt.evaluationStatus]}>
                        {evaluationStatusLabels[attempt.evaluationStatus]}
                      </Badge>
                    </>
                  ) : (
                    <Badge variant="outline">In progress</Badge>
                  )}
                  {attempt.essays.length && attempt.status === "completed" ? (
                    <Button
                      variant={attempt.evaluationStatus === "pending" ? "default" : "outline"}
                      className="min-h-11"
                      onClick={() => setScoring(attempt)}
                    >
                      {attempt.evaluationStatus === "pending" ? "Score essays" : "View essay scores"}
                    </Button>
                  ) : null}
                </div>
              </li>
            );
          })}
        </ul>
      </section>

      {scoring ? (
        <EssayScoringDialog
          attempt={scoring}
          busy={busy !== null}
          onClose={() => setScoring(null)}
          onScore={(essay, scores, feedback) =>
            run(
              `score-${essay.itemId}`,
              {
                action: "score_essay",
                attempt_id: scoring.id,
                item_id: essay.itemId,
                criterion_scores: scores,
                feedback: feedback || undefined,
              },
              "Essay score saved. Earlier scores stay in the history.",
            )
          }
          onFinalize={() =>
            run("finalize", { action: "finalize", attempt_ids: [scoring.id] }, "Result finalized.")
          }
          onRelease={() =>
            run("release", { action: "release", attempt_ids: [scoring.id] }, "Result released to the learner.")
          }
        />
      ) : null}
    </div>
  );
}

function EssayScoringDialog({
  attempt,
  busy,
  onClose,
  onScore,
  onFinalize,
  onRelease,
}: {
  attempt: ResultAttempt;
  busy: boolean;
  onClose: () => void;
  onScore: (essay: EssayForScoring, scores: Record<string, number>, feedback: string) => Promise<boolean>;
  onFinalize: () => Promise<boolean>;
  onRelease: () => Promise<boolean>;
}) {
  const editable = attempt.evaluationStatus === "pending" || attempt.evaluationStatus === "evaluated";
  return (
    <Dialog open onOpenChange={(open) => { if (!open && !busy) onClose(); }}>
      <DialogContent className="max-h-[90dvh] max-w-3xl overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Essay evaluation · {attempt.learner}</DialogTitle>
          {attempt.learnerEmail ? <p className="break-all text-xs text-muted-foreground">{attempt.learnerEmail}</p> : null}
          <DialogDescription>
            Score each criterion and give feedback. Every score is kept in the
            history; the latest score counts. Learners see nothing until you
            finalize and release.
          </DialogDescription>
        </DialogHeader>
        <p className="text-sm">
          Stage: <strong>{evaluationStatusLabels[attempt.evaluationStatus]}</strong>
          {attempt.submissionKind !== "learner" ? ` · ${submissionKindLabels[attempt.submissionKind]}` : ""}
        </p>
        <div className="space-y-6">
          {attempt.essays.map((essay) => (
            <EssayScoreForm key={`${essay.itemId}-${essay.scoreCount}`} essay={essay} editable={editable} busy={busy} onScore={onScore} />
          ))}
        </div>
        <div className="flex flex-wrap justify-end gap-2 border-t border-border pt-4">
          <Button variant="outline" className="min-h-11" disabled={busy} onClick={onClose}>
            Close
          </Button>
          {attempt.evaluationStatus === "evaluated" ? (
            <Button className="min-h-11" disabled={busy} onClick={() => { if (window.confirm("Finalize this result? Final totals are locked.")) void onFinalize(); }}>
              <ClipboardCheck className="mr-2 h-4 w-4" aria-hidden="true" />
              Finalize
            </Button>
          ) : null}
          {attempt.evaluationStatus === "finalized" ? (
            <Button className="min-h-11" disabled={busy} onClick={() => { if (window.confirm("Release this result to the learner?")) void onRelease(); }}>
              <Send className="mr-2 h-4 w-4" aria-hidden="true" />
              Release
            </Button>
          ) : null}
          {attempt.evaluationStatus === "released" ? (
            <p className="flex items-center gap-2 text-sm text-muted-foreground">
              <CheckCircle2 className="h-4 w-4 text-emerald-700" aria-hidden="true" />
              Released to the learner
            </p>
          ) : null}
        </div>
      </DialogContent>
    </Dialog>
  );
}

function EssayScoreForm({
  essay,
  editable,
  busy,
  onScore,
}: {
  essay: EssayForScoring;
  editable: boolean;
  busy: boolean;
  onScore: (essay: EssayForScoring, scores: Record<string, number>, feedback: string) => Promise<boolean>;
}) {
  const [scores, setScores] = useState<Record<string, string>>(
    Object.fromEntries(
      essay.rubric.map((row) => [row.id, essay.latest ? String(essay.latest.criterionScores[row.id] ?? "") : ""]),
    ),
  );
  const [feedback, setFeedback] = useState(essay.latest?.feedback ?? "");
  const [error, setError] = useState("");
  const total = essay.rubric.reduce((sum, row) => sum + (Number(scores[row.id]) || 0), 0);
  async function submit(event: React.FormEvent) {
    event.preventDefault();
    const parsed: Record<string, number> = {};
    for (const row of essay.rubric) {
      const value = Number(scores[row.id]);
      if (scores[row.id] === "" || !Number.isFinite(value) || value < 0 || value > row.maxPoints) {
        setError(`Give ${row.criterion} a score from 0 to ${row.maxPoints}.`);
        return;
      }
      parsed[row.id] = value;
    }
    setError("");
    await onScore(essay, parsed, feedback.trim());
  }
  return (
    <form onSubmit={submit} className="space-y-3 rounded-lg border border-border p-4">
      {essay.scenario ? (
        <p className="whitespace-pre-wrap rounded-md bg-muted/40 p-3 text-sm"><strong>Scenario:</strong> {essay.scenario}</p>
      ) : null}
      <p className="whitespace-pre-wrap text-sm font-medium">{essay.prompt}</p>
      <div className="rounded-md border border-border p-3">
        <p className="text-xs font-medium text-muted-foreground">Learner answer</p>
        <p className="mt-1 whitespace-pre-wrap break-words text-sm">
          {essay.answer ?? "No answer was saved before submission. This essay scores zero and needs no score."}
        </p>
      </div>
      {essay.answer === null ? null : (
      <fieldset disabled={!editable || busy} className="space-y-3">
        <legend className="text-sm font-medium">
          Rubric · {total}/{essay.points} points
          {essay.latest ? ` · last scored ${formatDateTime(essay.latest.evaluatedAt)} (${essay.scoreCount} in history)` : ""}
        </legend>
        {essay.rubric.map((row) => (
          <div key={row.id} className="grid gap-2 sm:grid-cols-[minmax(0,1fr)_7rem] sm:items-center">
            <div className="min-w-0">
              <Label htmlFor={`score-${essay.itemId}-${row.id}`}>{row.criterion} (max {row.maxPoints})</Label>
              {row.description ? <p className="text-xs text-muted-foreground">{row.description}</p> : null}
            </div>
            <Input
              id={`score-${essay.itemId}-${row.id}`}
              className="min-h-11"
              type="number"
              min={0}
              max={row.maxPoints}
              step={0.5}
              required
              value={scores[row.id] ?? ""}
              onChange={(event) => setScores((current) => ({ ...current, [row.id]: event.target.value }))}
            />
          </div>
        ))}
        <div className="space-y-1">
          <Label htmlFor={`feedback-${essay.itemId}`}>Feedback to the learner</Label>
          <Textarea
            id={`feedback-${essay.itemId}`}
            rows={3}
            maxLength={5000}
            value={feedback}
            onChange={(event) => setFeedback(event.target.value)}
            placeholder="What was done well and what to improve, tied to the rubric."
          />
        </div>
        {error ? <p role="alert" className="text-sm text-destructive">{error}</p> : null}
        {editable ? (
          <Button type="submit" className="min-h-11">
            {busy ? <Loader2 className="mr-2 h-4 w-4 animate-spin" aria-hidden="true" /> : null}
            {essay.latest ? "Save new score" : "Save score"}
          </Button>
        ) : (
          <p className="text-xs text-muted-foreground">Scores are locked after finalization.</p>
        )}
      </fieldset>
      )}
    </form>
  );
}
