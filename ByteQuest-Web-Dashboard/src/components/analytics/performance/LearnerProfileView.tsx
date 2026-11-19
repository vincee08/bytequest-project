"use client";

import Link from "next/link";
import { useTransition } from "react";
import { usePathname, useRouter } from "next/navigation";
import { ArrowLeft, CheckCircle2, CircleDashed, Download } from "lucide-react";
import { AnalyticsLiveRefresh } from "@/components/analytics/performance/AnalyticsLiveRefresh";
import { DataTable, EmptyState, Panel, Stat, StatusBadge } from "@/components/analytics/performance/primitives";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  describePeriod,
  formatDateTime,
  formatDuration,
  formatNumber,
  formatPercent,
  outcomeLabel,
  reasonText,
} from "@/lib/analytics/format";
import { EVALUATION_STAGES, type EvaluationStage, type LearnerProfile } from "@/lib/analytics/performance-types";
import { RANGE_LABELS, RANGE_PRESETS, analyticsHref, analyticsSearchParams, type AnalyticsQuery, type RangePreset } from "@/lib/analytics/query";
import { cn } from "@/lib/utils";

type MissionRow = LearnerProfile["missions"][number];
type QuizRow = LearnerProfile["quizzes"][number];
type HomeworkRow = LearnerProfile["assignments"][number];

const HOMEWORK_STATUS: Record<HomeworkRow["status"], string> = {
  submitted: "Submitted · awaiting evaluation",
  graded: "Graded · awaiting finalization",
  finalized: "Finalized · awaiting release",
  released: "Released",
  missing: "Missing",
  open: "Open",
};

const STAGE_LABELS: Record<EvaluationStage, string> = {
  evaluate: "Evaluate",
  finalize: "Finalize",
  release: "Release",
  released: "Released",
};

const TIMELINE_LABELS: Record<string, string> = {
  assessment_submitted: "Assessment submitted",
  assessment_released: "Assessment result released",
  quiz_submitted: "Quiz submitted",
  homework_submitted: "Homework submitted",
  practice_run: "Practice run",
  mission_verified: "Mission verified",
  topic_completed: "Topic completed",
  coc_quiz_passed: "COC practice quiz passed",
  module_completed: "Module completed",
};

function timelineDetail(kind: string, detail: Record<string, unknown>): string {
  if (kind === "assessment_released") return `${outcomeLabel(String(detail.outcome ?? ""))} · ${formatPercent(detail.percent as number | null)}`;
  if (kind === "quiz_submitted") return detail.scored ? formatPercent(detail.percent as number | null) : "Awaiting evaluation";
  if (kind === "practice_run") return `Run ${detail.run_number} · ${detail.outcome === "verified" ? "verified" : "incomplete"} · ${formatDuration(detail.duration_seconds as number | null)} · ${detail.invalid_actions} invalid actions`;
  if (kind === "homework_submitted") return detail.late ? "Late" : "On time";
  if (kind === "assessment_submitted") return String(detail.assignment ?? "");
  return "";
}

export function LearnerProfileView({ profile, query }: { profile: LearnerProfile; query: AnalyticsQuery }) {
  const router = useRouter();
  const pathname = usePathname();
  const [pending, startTransition] = useTransition();
  const backHref = analyticsHref("/analytics", query, { tab: "learners", learnerId: null });
  const exportSearch = analyticsSearchParams(query, { learnerId: profile.learner.id });
  exportSearch.set("tab", "profile");
  const exportParams = exportSearch.toString();
  const status = profile.status;

  return (
    <div className="mx-auto max-w-[1400px] space-y-6" aria-busy={pending}>
      <div className="flex flex-col gap-4 border-b border-border/70 pb-5 lg:flex-row lg:items-end lg:justify-between">
        <div className="min-w-0">
          <Button asChild variant="ghost" size="sm" className="-ml-3 mb-2"><Link href={backHref}><ArrowLeft className="mr-2 h-4 w-4" aria-hidden="true" />Learner analytics</Link></Button>
          <div className="flex flex-wrap items-center gap-3">
            <h1 className="text-[1.45rem] font-bold tracking-[-0.035em]">{profile.learner.name || "Unnamed learner"}</h1>
            {status ? <StatusBadge status={status.status} /> : null}
            <Badge variant={profile.learner.account_status === "active" ? "secondary" : "outline"}>{profile.learner.account_status}</Badge>
          </div>
          <p className="mt-1 text-sm text-muted-foreground">
            {profile.learner.student_id ?? "No student ID"} · {profile.learner.email} · {profile.classes.map((item) => item.title).join(", ") || "No class in scope"}
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-2 print-hidden">
          <AnalyticsLiveRefresh generatedAt={profile.generated_at} />
          <label className="grid gap-1 text-xs font-medium">
            <span className="sr-only">Period</span>
            <select value={query.range} disabled={pending} aria-label="Period"
              className="h-10 rounded-lg border border-input bg-card px-3 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
              onChange={(event) => startTransition(() => router.push(analyticsHref(pathname, query, { range: event.target.value as RangePreset }), { scroll: false }))}>
              {RANGE_PRESETS.filter((value) => value !== "custom" || query.range === "custom").map((value) => <option key={value} value={value}>{RANGE_LABELS[value]}</option>)}
            </select>
          </label>
          <Button asChild variant="outline"><a href={`/api/reports/export?${exportParams}`} download><Download className="mr-2 h-4 w-4" aria-hidden="true" />Export CSV</a></Button>
        </div>
      </div>

      <p className="text-xs text-muted-foreground">Period: {describePeriod(profile.period)}. Learning progress counts everything completed by the end of the period; scores count work in the period.</p>

      {status ? (
        <Panel title="Status and key measures" description={status.reasons.length ? "Reasons are computed from the documented thresholds." : "No falling-behind or struggling rule applies."}>
          {status.reasons.length ? (
            <ul className="space-y-1 border-b border-border px-5 py-3 text-sm">
              {status.reasons.map((reason) => <li key={reason.code} className="flex gap-2"><span className="mt-2 h-1.5 w-1.5 shrink-0 rounded-full bg-amber-600" aria-hidden="true" />{reasonText(reason)}</li>)}
            </ul>
          ) : null}
          <div className="grid gap-3 p-4 sm:grid-cols-2 sm:p-5 lg:grid-cols-4 2xl:grid-cols-7">
            <Stat label="Learning progress" value={formatPercent(status.progress_percent)} helper={`${profile.progress.completed_items} of ${profile.progress.total_items} required items`} />
            <Stat label="Performance score" value={formatPercent(status.performance_score)} helper="Released, scored and graded work" />
            <Stat label="Quiz average" value={formatPercent(status.quiz_avg)} />
            <Stat label="Assessments" value={`${status.assessment.competent}/${status.assessment.released}`} helper={`competent of released · ${status.assessment.pending} pending`} />
            <Stat label="Missions verified" value={status.missions_verified} helper={`${status.practice_runs} runs in period`} />
            <Stat label="Homework" value={status.assignments.submitted} helper={`${status.assignments.pending_evaluation} awaiting evaluation · ${status.assignments.missing} missing · ${status.assignments.late} late`} />
            <Stat label="Last activity" value={<span className="text-sm">{formatDateTime(status.last_activity_at)}</span>} />
          </div>
        </Panel>
      ) : null}

      <Panel title="Evaluation status" description="This learner's technical assessments, instructor-release quizzes and homework submitted in the period, by Evaluation Center stage. Only released results count in averages.">
        <dl className="grid grid-cols-2 gap-3 p-4 sm:grid-cols-4 sm:p-5">
          {EVALUATION_STAGES.map((stage) => (
            <div key={stage} className="rounded-lg border border-border/70 bg-background px-3.5 py-3">
              <dt className="text-[11px] font-semibold uppercase tracking-[0.04em] text-muted-foreground">{STAGE_LABELS[stage]}</dt>
              <dd className="mt-1 text-lg font-bold tabular-nums">{profile.evaluation[stage]}</dd>
            </div>
          ))}
        </dl>
      </Panel>

      <Panel title="Engagement" description="A6 points and level. Points reward activity; they are not a competency judgement and are not part of the performance score.">
        <div className="grid gap-4 p-4 sm:p-5 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.4fr)]">
          <div className="grid grid-cols-2 gap-3">
            <Stat label="Points" value={profile.engagement.points} helper={`+${profile.engagement.points_in_period} in the period`} />
            <Stat label="Level" value={profile.engagement.level_title ?? "—"}
              helper={profile.engagement.next_level_points === null ? "Highest level" : `${profile.engagement.level_progress_percent ?? 0}% of the way to ${profile.engagement.next_level_points} points`} />
            <Stat label="Achievements" value={profile.engagement.achievements} />
          </div>
          {profile.engagement.recent_events.length ? (
            <ul className="divide-y divide-border rounded-lg border border-border/70 text-xs">
              {profile.engagement.recent_events.map((event) => (
                <li key={`${event.event_type}-${event.awarded_at}`} className="flex items-center justify-between gap-3 px-3 py-2">
                  <span className="min-w-0"><span className="font-medium">{event.label ?? event.event_type.replaceAll("_", " ")}</span>{event.detail ? <span className="block truncate text-muted-foreground">{event.detail}</span> : null}</span>
                  <span className="shrink-0 tabular-nums">+{event.points} · {formatDateTime(event.awarded_at)}</span>
                </li>
              ))}
            </ul>
          ) : <EmptyState title="No points awarded in this period" />}
        </div>
      </Panel>

      <Panel title="Curriculum progress" description="COC → module → topic and mission completion using the shared methodology (published topics, server-verified missions, COC practice quiz).">
        {profile.progress.cocs.length ? (
          <div className="grid gap-4 p-4 sm:p-5 xl:grid-cols-2">
            {profile.progress.cocs.map((coc) => (
              <article key={coc.coc_code} className="rounded-lg border border-border/80 p-4" aria-label={`${coc.coc_code.toUpperCase()} progress`}>
                <div className="flex items-start justify-between gap-3">
                  <div><p className="text-sm font-semibold">{coc.coc_code.toUpperCase()} · {coc.title}</p><p className="mt-0.5 text-xs text-muted-foreground">{coc.completed_items} of {coc.total_items} required items · COC quiz {coc.coc_quiz_passed_at ? `passed ${formatDateTime(coc.coc_quiz_passed_at)}` : "not passed"}</p></div>
                  <span className="text-lg font-bold tabular-nums">{formatPercent(coc.percent)}</span>
                </div>
                <ProgressBar value={coc.percent} label={`${coc.coc_code.toUpperCase()} learning progress`} />
                <ul className="mt-3 divide-y divide-border">
                  {coc.modules.map((module) => (
                    <li key={module.id} className="py-2.5">
                      <div className="flex items-center justify-between gap-3 text-sm">
                        <span className="min-w-0"><span className="font-medium">{module.code}</span> <span className="text-muted-foreground">{module.title}</span></span>
                        <span className="shrink-0 text-xs font-semibold tabular-nums">{module.total_items ? formatPercent(module.percent) : "No required activities yet"}</span>
                      </div>
                      {module.total_items ? (
                        <div className="mt-1.5 flex flex-wrap gap-1.5">
                          {module.missions.map((mission) => <ItemChip key={mission.mission_code} done={Boolean(mission.verified_at)} label={mission.title} />)}
                          {module.topics.map((topic) => <ItemChip key={topic.id} done={Boolean(topic.completed_at)} label={topic.title} />)}
                        </div>
                      ) : null}
                    </li>
                  ))}
                </ul>
              </article>
            ))}
          </div>
        ) : <EmptyState title="No curriculum items match these filters." />}
      </Panel>

      <Panel title="Practice missions and runs" description="Recorded runs in the period with the steps each run missed (not completed, or incorrect attempts); verified completion and best time to date.">
        <DataTable<MissionRow>
          caption="Practice missions and runs"
          rows={profile.missions}
          rowKey={(row) => row.mission_code}
          minWidth={960}
          emptyTitle="No practice activity recorded."
          columns={[
            { key: "mission", label: "Mission", render: (row) => <div><p className="font-medium">{row.mission_code.toUpperCase().replace("_", " ")} · {row.title ?? "Mission"}</p><p className="mt-0.5 text-xs text-muted-foreground">{row.module_code ?? "No module"}</p></div> },
            { key: "verified", label: "Verified", render: (row) => row.verified_at ? <span className="text-emerald-700">{formatDateTime(row.verified_at)}</span> : <span className="text-muted-foreground">Not yet</span> },
            { key: "runs", label: "Runs", align: "right", render: (row) => `${row.runs} (${row.successful_runs} ok · ${row.failed_runs} incomplete)` },
            { key: "best", label: "Best time", align: "right", render: (row) => formatDuration(row.best_duration_seconds) },
            { key: "invalid", label: "Invalid / run", align: "right", render: (row) => formatNumber(row.avg_invalid_actions) },
            { key: "recent", label: "Recent runs", render: (row) => row.recent_runs.length ? (
              <ul className="space-y-0.5 text-xs text-muted-foreground">
                {row.recent_runs.map((run) => (
                  <li key={`${row.mission_code}-${run.run_number}`}>#{run.run_number} {run.outcome === "verified" ? "verified" : "incomplete"} · {formatDuration(run.duration_seconds)} · {run.invalid_count} invalid
                    {run.missed_steps.length ? (
                      <span className="block pl-3">Missed: {run.missed_steps.map((step) => `${step.step ? `Step ${step.step} ` : ""}${step.title}${step.done ? ` (${step.incorrect} incorrect)` : " (not completed)"}`).join("; ")}</span>
                    ) : null}
                  </li>
                ))}
              </ul>
            ) : <span className="text-xs text-muted-foreground">No run in period</span> },
          ]}
        />
      </Panel>

      <div className="grid gap-6 xl:grid-cols-2">
        <Panel title="Quizzes" description="Submitted quiz attempts in the period (published versions only). Instructor-release quizzes are scored once released.">
          <DataTable<QuizRow>
            caption="Quiz results"
            rows={profile.quizzes}
            rowKey={(row) => row.quiz_id}
            minWidth={520}
            emptyTitle="No submissions in this period"
            columns={[
              { key: "quiz", label: "Quiz", render: (row) => <div><p className="font-medium">{row.title}</p><p className="mt-0.5 text-xs text-muted-foreground">{row.class_title ?? "Class"}</p></div> },
              { key: "score", label: "Score", align: "right", render: (row) => row.status === "scored"
                ? `${formatNumber(row.score)} / ${formatNumber(row.max_score)} (${formatPercent(row.percent)})`
                : <span>Awaiting evaluation{row.stage ? <span className="block text-[11px] text-muted-foreground">{STAGE_LABELS[row.stage]} stage</span> : null}</span> },
              { key: "submitted", label: "Submitted", render: (row) => <span className="text-xs text-muted-foreground">{formatDateTime(row.submitted_at)}</span> },
            ]}
          />
        </Panel>
        <Panel title="Homework" description="Homework open in the period. Missing work is never scored as zero.">
          <DataTable<HomeworkRow>
            caption="Homework"
            rows={profile.assignments}
            rowKey={(row) => row.homework_id}
            minWidth={560}
            emptyTitle="No homework in this period."
            columns={[
              { key: "title", label: "Homework", render: (row) => <div><p className="font-medium">{row.title}</p><p className="mt-0.5 text-xs text-muted-foreground">Due {formatDateTime(row.deadline_at)}</p></div> },
              { key: "status", label: "Status", render: (row) => <span className={cn(row.status === "missing" && "font-medium text-red-800")}>{HOMEWORK_STATUS[row.status]}{row.late ? " · late" : ""}</span> },
              { key: "score", label: "Score", align: "right", render: (row) => row.score === null ? "—" : (
                <span>{formatNumber(row.score)} / {formatNumber(row.max_score)}{row.percent !== null
                  ? <span className="block text-[11px] text-muted-foreground">{formatPercent(row.percent)} released</span>
                  : <span className="block text-[11px] text-muted-foreground">not released</span>}</span>
              ) },
            ]}
          />
        </Panel>
      </div>

      <Panel title="Technical assessment results" description="Criterion outcomes are shown only for released results; pending evaluations are listed without a score. Simulation assessments name the step each criterion checks.">
        {profile.assessments.length ? (
          <ul className="divide-y divide-border">
            {profile.assessments.map((attempt) => (
              <li key={attempt.attempt_id} className="px-5 py-4">
                <div className="flex flex-wrap items-start justify-between gap-3">
                  <div>
                    <p className="font-medium">{attempt.title}{attempt.simulation ? <span className="ml-2 rounded border border-border px-1.5 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-muted-foreground">Simulation</span> : null}</p>
                    <p className="mt-0.5 text-xs text-muted-foreground">{attempt.assignment_title} · {attempt.class_title ?? "Class"} · submitted {formatDateTime(attempt.submitted_at)}</p>
                  </div>
                  <div className="text-right">
                    <p className="text-sm font-semibold">{attempt.released_at ? `${outcomeLabel(attempt.outcome)} · ${formatPercent(attempt.percent)}` : "Pending release"}</p>
                    <p className="text-xs text-muted-foreground">{attempt.released_at ? `Released ${formatDateTime(attempt.released_at)}` : attempt.stage ? `${STAGE_LABELS[attempt.stage]} stage` : attempt.status.replaceAll("_", " ")}</p>
                  </div>
                </div>
                {attempt.criteria.length ? (
                  <ul className="mt-3 grid gap-1.5 sm:grid-cols-2">
                    {attempt.criteria.map((criterion) => (
                      <li key={criterion.criterion_id} className="flex items-center justify-between gap-3 rounded-md border border-border/70 px-3 py-2 text-xs">
                        <span className="min-w-0"><span className="block truncate"><span className="font-medium">{criterion.code}</span> {criterion.title}</span>
                          {criterion.steps.length ? <span className="block truncate text-muted-foreground">{criterion.steps.map((step) => (step.step ? `Step ${step.step} · ${step.title}` : step.title)).join("; ")}</span> : null}</span>
                        <span className={cn("shrink-0 font-semibold", criterion.observation === "satisfied" ? "text-emerald-700" : "text-amber-800")}>{outcomeLabel(criterion.observation)}</span>
                      </li>
                    ))}
                  </ul>
                ) : null}
              </li>
            ))}
          </ul>
        ) : <EmptyState title="No assessment attempts in this period" />}
      </Panel>

      <Panel title="Activity timeline" description="Most recent recorded activity first (up to 100 events in the period).">
        {profile.timeline.length ? (
          <ol className="divide-y divide-border">
            {profile.timeline.map((event, index) => (
              <li key={`${event.at}-${event.kind}-${index}`} className="grid gap-1 px-5 py-3 sm:grid-cols-[170px_minmax(0,1fr)]">
                <time dateTime={event.at} className="text-xs tabular-nums text-muted-foreground">{formatDateTime(event.at)}</time>
                <div className="min-w-0 text-sm">
                  <span className="font-medium">{TIMELINE_LABELS[event.kind] ?? event.kind.replaceAll("_", " ")}</span>
                  {event.title ? <span className="text-muted-foreground"> · {event.title}</span> : null}
                  {timelineDetail(event.kind, event.detail) ? <span className="block text-xs text-muted-foreground">{timelineDetail(event.kind, event.detail)}</span> : null}
                </div>
              </li>
            ))}
          </ol>
        ) : <EmptyState title="No recorded activity in this period" />}
      </Panel>
    </div>
  );
}

function ProgressBar({ value, label }: { value: number | null; label: string }) {
  const width = Math.max(0, Math.min(100, value ?? 0));
  return (
    <div className="mt-3 h-2 overflow-hidden rounded-full bg-muted" role="progressbar" aria-label={label} aria-valuemin={0} aria-valuemax={100} aria-valuenow={value ?? undefined}>
      <div className="h-full rounded-full bg-primary transition-[width] duration-200 motion-reduce:transition-none" style={{ width: `${width}%` }} />
    </div>
  );
}

function ItemChip({ done, label }: { done: boolean; label: string }) {
  const Icon = done ? CheckCircle2 : CircleDashed;
  return (
    <span className={cn("inline-flex min-h-7 items-center gap-1 rounded-md border px-2 text-[11px]", done ? "border-emerald-200 bg-emerald-50 text-emerald-800" : "border-border bg-background text-muted-foreground")}>
      <Icon className="h-3 w-3" aria-hidden="true" />
      <span className="max-w-[220px] truncate">{label}</span>
      <span className="sr-only">{done ? "completed" : "not completed"}</span>
    </span>
  );
}
