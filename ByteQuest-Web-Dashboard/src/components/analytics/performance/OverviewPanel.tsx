"use client";

import Link from "next/link";
import type { ComponentType, ReactNode } from "react";
import { BookOpenCheck, ClipboardCheck, FileCheck2, GraduationCap, Route, Users } from "lucide-react";
import { DataTable, EmptyState, Panel } from "@/components/analytics/performance/primitives";
import { CountBarChart, PercentBarChart, TrendLineChart } from "@/components/analytics/performance/charts";
import type { ChartConfig } from "@/components/ui/chart";
import { describePeriod, formatDuration, formatPercent, formatShortDay } from "@/lib/analytics/format";
import type { AnalyticsOverview, EvaluationStage } from "@/lib/analytics/performance-types";
import { analyticsHref, type AnalyticsQuery } from "@/lib/analytics/query";
import { cn } from "@/lib/utils";

const SOURCE_CONFIG = {
  average: { label: "Average score", color: "hsl(var(--chart-1))" },
} satisfies ChartConfig;

const COMPLETION_CONFIG = {
  completion: { label: "Completion rate", color: "hsl(var(--chart-2))" },
} satisfies ChartConfig;

const STAGE_CONFIG = {
  technical: { label: "Technical assessments", color: "hsl(var(--chart-1))" },
  homework: { label: "Homework", color: "hsl(var(--chart-4))" },
} satisfies ChartConfig;

export const STAGE_LABELS: Record<EvaluationStage, string> = {
  evaluate: "Evaluate",
  finalize: "Finalize",
  release: "Release",
  released: "Released",
};

export function OverviewPanel({
  data,
  query,
  pathname,
  scopeLabel = "your classes",
}: {
  data: AnalyticsOverview;
  query: AnalyticsQuery;
  /** Base path for tab links; null renders the overview without drill-down links (admin view). */
  pathname: string | null;
  scopeLabel?: string;
}) {
  const period = describePeriod(data.period);
  const population = `${data.population.enrolled} learner${data.population.enrolled === 1 ? "" : "s"}`;
  const footer = `${population} · ${period}`;
  const sources = [
    { source: "Assessments (released)", applicable: data.assessments.applicable, average: data.assessments.avg_percent, basis: `${data.assessments.released} released results` },
    { source: "Quizzes", applicable: data.quizzes.applicable, average: data.quizzes.avg_percent, basis: `${data.quizzes.scored} scored attempts` },
    { source: "Homework (released)", applicable: data.homework.applicable, average: data.homework.avg_percent, basis: `${data.homework.released} released grades (share of each maximum score)` },
    { source: "Learning progress", applicable: data.learning_progress.applicable, average: data.learning_progress.avg_percent, basis: `${data.learning_progress.items_total} required items` },
  ];
  const completions = [
    { measure: "Quizzes", applicable: data.quizzes.applicable, completion: data.quizzes.completion_rate, basis: `${data.quizzes.completed} of ${data.quizzes.eligible} learner-quiz pairs` },
    { measure: "Homework", applicable: data.homework.applicable, completion: data.homework.completion_rate, basis: `${data.homework.submitted} submitted, ${data.homework.missing} missing` },
    { measure: "Practice missions (to date)", applicable: data.missions.applicable, completion: data.missions.completion_rate, basis: `${data.missions.verified} verified in the period` },
  ];
  const link = (tab: "learners" | "missions" | "quizzes") => (pathname ? analyticsHref(pathname, query, { tab }) : undefined);
  const hasTrend = data.trend.length > 0;
  const trendTotals = data.trend.reduce(
    (sum, day) => sum + day.assessments + day.quizzes + day.homework + day.practice_runs + day.verified,
    0,
  );

  return (
    <div className="space-y-6">
      <p className="rounded-lg border border-border/70 bg-muted/30 px-4 py-2.5 text-xs leading-5 text-muted-foreground">
        <span className="font-semibold text-foreground">Population:</span> {data.population.description} ({population}, {data.population.active_in_period} active in the period) ·{" "}
        <span className="font-semibold text-foreground">Period:</span> {period}. Pending evaluations are counted separately and never included in averages.
      </p>

      <div className="grid gap-3.5 sm:grid-cols-2 xl:grid-cols-3">
        <SummaryCard icon={Users} label="Learners" value={String(data.population.enrolled)}
          detail={`${data.population.active_in_period} active in period · ${data.population.completed} completed all required items`}
          footer={`Active members of ${scopeLabel} · ${period}`} href={link("learners")} linkLabel="Open the learner list" />
        <SummaryCard icon={GraduationCap} label="Assessment results" applicable={data.assessments.applicable}
          value={formatPercent(data.assessments.avg_percent)}
          detail={`${data.assessments.released} released · ${formatPercent(data.assessments.competent_rate)} competent · ${data.assessments.pending_release} pending release`}
          footer={footer} href={link("missions")} linkLabel="Open mission and assessment analytics" />
        <SummaryCard icon={ClipboardCheck} label="Quiz scores" applicable={data.quizzes.applicable}
          value={formatPercent(data.quizzes.avg_percent)}
          detail={`${data.quizzes.submitted} submitted · ${formatPercent(data.quizzes.completion_rate)} completion${data.quizzes.pending ? ` · ${data.quizzes.pending} awaiting evaluation` : ""}`}
          footer={footer} href={link("quizzes")} linkLabel="Open quiz analytics" />
        <SummaryCard icon={FileCheck2} label="Homework scores" applicable={data.homework.applicable}
          value={formatPercent(data.homework.avg_percent)}
          detail={`${data.homework.submitted} submitted · ${data.homework.released} released · ${data.homework.pending_evaluation} awaiting evaluation · ${data.homework.missing} missing · ${data.homework.late} late`}
          footer={footer} />
        <SummaryCard icon={Route} label="Practice missions · completion to date" applicable={data.missions.applicable}
          value={formatPercent(data.missions.completion_rate)}
          detail={`In the period: ${data.missions.verified} verified · ${data.missions.runs} runs (${data.missions.successful_runs} verified, ${data.missions.failed_runs} incomplete) · avg ${formatDuration(data.missions.avg_duration_seconds)}`}
          footer={footer} href={link("missions")} linkLabel="Open mission analytics" />
        <SummaryCard icon={BookOpenCheck} label="Learning progress" applicable={data.learning_progress.applicable}
          value={formatPercent(data.learning_progress.avg_percent)}
          detail={data.learning_progress.definition}
          footer={`Average per learner · ${footer}`} />
      </div>

      <div className="grid gap-5 xl:grid-cols-2">
        <Panel title="Average score by source" description="Released assessment results, scored quizzes, released homework grades and learning progress. Each bar is backed by the table below.">
          {sources.some((row) => row.applicable && row.average !== null) ? (
            <div className="space-y-4 p-4 sm:p-5">
              <PercentBarChart data={sources.filter((row) => row.applicable).map((row) => ({ source: row.source, average: row.average }))}
                config={SOURCE_CONFIG} categoryKey="source" series={["average"]} categoryLabel="Source" valueLabel="Average (%)"
                ariaLabel="Average score by source" />
              <SourceTable rows={sources.map((row) => ({ name: row.source, applicable: row.applicable, value: row.average, basis: row.basis }))} valueLabel="Average" />
            </div>
          ) : <EmptyState title="No scored work in this period" description="Averages appear after results are released, quizzes are scored or homework grades are released." />}
        </Panel>
        <Panel title="Completion rates" description="Quiz and homework completion of eligible learners, and the share of learner-mission pairs verified by the server.">
          {completions.some((row) => row.applicable && row.completion !== null) ? (
            <div className="space-y-4 p-4 sm:p-5">
              <PercentBarChart data={completions.filter((row) => row.applicable).map((row) => ({ measure: row.measure, completion: row.completion }))}
                config={COMPLETION_CONFIG} categoryKey="measure" series={["completion"]} categoryLabel="Activity" valueLabel="Completion (%)"
                ariaLabel="Completion rates by activity" />
              <SourceTable rows={completions.map((row) => ({ name: row.measure, applicable: row.applicable, value: row.completion, basis: row.basis }))} valueLabel="Completion" />
            </div>
          ) : <EmptyState title="No eligible work in this period" description="Completion rates appear once quizzes, homework or missions are available to these learners." />}
        </Panel>
      </div>

      <EvaluationPanel data={data} />

      <Panel title="Daily learning activity" description="Recorded events per Manila calendar day for the filtered population.">
        {hasTrend && trendTotals > 0 ? (
          <div className="p-4 sm:p-5">
            <TrendLineChart data={data.trend} ariaLabel={`Daily learning activity, ${data.trend.length} days`} />
            <details className="mt-3 text-xs text-muted-foreground">
              <summary className="cursor-pointer font-medium text-foreground">Show the daily activity table</summary>
              <div className="relative mt-2 max-h-72 overflow-auto rounded-lg border border-border">
                <table className="w-full text-left">
                  <caption className="sr-only">Daily learning activity</caption>
                  <thead className="sticky top-0 bg-muted">
                    <tr><th className="px-3 py-2">Day</th><th className="px-3 py-2 text-right">Assessments</th><th className="px-3 py-2 text-right">Quizzes</th><th className="px-3 py-2 text-right">Homework</th><th className="px-3 py-2 text-right">Practice runs</th><th className="px-3 py-2 text-right">Verified</th></tr>
                  </thead>
                  <tbody>
                    {data.trend.filter((day) => day.assessments + day.quizzes + day.homework + day.practice_runs + day.verified > 0).map((day) => (
                      <tr key={day.date} className="border-t border-border tabular-nums">
                        <td className="px-3 py-2">{formatShortDay(day.date)}</td><td className="px-3 py-2 text-right">{day.assessments}</td><td className="px-3 py-2 text-right">{day.quizzes}</td><td className="px-3 py-2 text-right">{day.homework}</td><td className="px-3 py-2 text-right">{day.practice_runs}</td><td className="px-3 py-2 text-right">{day.verified}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </details>
          </div>
        ) : <EmptyState title="No submissions in this period" description="Choose a longer period or another class. Nothing is shown as zero activity unless it was recorded." />}
      </Panel>

      <Panel title="Classes in scope" description="Active classes included in every number on this page." action={
        pathname ? <Link className="inline-flex min-h-9 items-center text-xs font-medium text-primary hover:underline" href={analyticsHref(pathname, query, { tab: "classes" })}>Compare classes</Link> : null
      }>
        <DataTable caption="Classes in scope" minWidth={480} rows={data.classes} rowKey={(row) => row.id} emptyTitle="No active class is in scope."
          columns={[
            { key: "title", label: "Class", render: (row) => <span className="font-medium">{row.title}</span> },
            { key: "code", label: "Class code", render: (row) => row.class_code ?? "—" },
            { key: "enrolled", label: "Enrolled learners", align: "right", render: (row) => row.enrolled },
            ...(pathname ? [{ key: "drill", label: "Drill down", align: "right" as const, render: (row: AnalyticsOverview["classes"][number]) => (
              <Link className="inline-flex min-h-9 items-center text-xs font-medium text-primary hover:underline"
                href={analyticsHref(pathname, { ...query, classId: row.id, learnerId: null }, { tab: "learners" })}>Learners<span className="sr-only"> in {row.title}</span></Link>
            ) }] : []),
          ]} />
      </Panel>
    </div>
  );
}

function EvaluationPanel({ data }: { data: AnalyticsOverview }) {
  const stages = (Object.keys(STAGE_LABELS) as EvaluationStage[]);
  const total = stages.reduce((sum, stage) => sum + data.evaluation.total[stage], 0);
  return (
    <Panel title="Evaluation status (Evaluate → Finalize → Release)"
      description={`Technical assessments and homework submitted in the period, by their current stage (same stages as the Evaluation Center). Only released results enter the averages above.`}>
      {total ? (
        <div className="grid gap-5 p-4 sm:p-5 xl:grid-cols-[minmax(0,1.2fr)_minmax(320px,1fr)]">
          <CountBarChart data={stages.map((stage) => ({ stage: STAGE_LABELS[stage], technical: data.evaluation.technical[stage], homework: data.evaluation.homework[stage] }))}
            config={STAGE_CONFIG} categoryKey="stage" series={["technical", "homework"]} stacked categoryLabel="Stage" valueLabel="Items"
            ariaLabel="Submitted work by evaluation stage" height={240} />
          <table className="w-full self-start text-left text-xs">
            <caption className="sr-only">Submitted work by evaluation stage</caption>
            <thead className="text-muted-foreground"><tr><th className="py-1.5 font-medium">Stage</th><th className="py-1.5 text-right font-medium">Technical</th><th className="py-1.5 text-right font-medium">Homework</th><th className="py-1.5 text-right font-medium">Total</th></tr></thead>
            <tbody className="divide-y divide-border tabular-nums">
              {stages.map((stage) => (
                <tr key={stage}>
                  <td className="py-2 font-medium text-foreground">{STAGE_LABELS[stage]}</td>
                  <td className="py-2 text-right">{data.evaluation.technical[stage]}</td>
                  <td className="py-2 text-right">{data.evaluation.homework[stage]}</td>
                  <td className="py-2 text-right font-semibold">{data.evaluation.total[stage]}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : <EmptyState title="No submitted work in this period" description="Assessment attempts and homework appear here once learners submit them." />}
    </Panel>
  );
}

function SourceTable({ rows, valueLabel }: { rows: Array<{ name: string; applicable: boolean; value: number | null; basis: string }>; valueLabel: string }) {
  return (
    <table className="w-full text-left text-xs">
      <caption className="sr-only">{valueLabel} by source</caption>
      <thead className="text-muted-foreground"><tr><th className="py-1.5 font-medium">Source</th><th className="py-1.5 text-right font-medium">{valueLabel}</th><th className="py-1.5 pl-4 font-medium">Based on</th></tr></thead>
      <tbody className="divide-y divide-border">
        {rows.map((row) => (
          <tr key={row.name}>
            <td className="py-2 font-medium text-foreground">{row.name}</td>
            <td className="py-2 text-right font-semibold tabular-nums">{row.applicable ? formatPercent(row.value) : "Not linked"}</td>
            <td className="py-2 pl-4 text-muted-foreground">{row.applicable ? row.basis : "Not linked to the selected curriculum filter"}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

function SummaryCard({
  icon: Icon,
  label,
  value,
  detail,
  footer,
  applicable = true,
  href,
  linkLabel,
}: {
  icon: ComponentType<{ className?: string; "aria-hidden"?: boolean }>;
  label: string;
  value: string;
  detail: string;
  footer: string;
  applicable?: boolean;
  href?: string;
  linkLabel?: string;
}) {
  const body: ReactNode = (
    <>
      <div className="flex items-start justify-between gap-3">
        <p className="text-[12px] font-semibold text-muted-foreground">{label}</p>
        <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-primary/[0.08] text-primary ring-1 ring-primary/15">
          <Icon className="h-4 w-4" aria-hidden={true} />
        </span>
      </div>
      <p className="mt-2 text-[1.65rem] font-bold leading-none tabular-nums tracking-[-0.03em] text-foreground">{applicable ? value : "Not linked"}</p>
      <p className="mt-2 text-xs leading-5 text-muted-foreground">{applicable ? detail : "This source is not linked to the selected curriculum filter, so it is excluded."}</p>
      <p className="mt-auto border-t border-border/60 pt-2 text-[11px] leading-4 text-muted-foreground">{footer}</p>
    </>
  );
  const className = cn(
    "flex min-h-[176px] flex-col gap-0 rounded-xl border border-border/80 bg-card p-4 shadow-card",
    href && "transition-[border-color,box-shadow] duration-200 hover:border-primary/35 hover:shadow-card-hover focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
  );
  return href ? (
    <Link href={href} className={className} aria-label={`${label}: ${applicable ? value : "not linked"}. ${linkLabel ?? ""}`}>{body}</Link>
  ) : (
    <article className={className} aria-label={`${label}: ${applicable ? value : "not linked"}`}>{body}</article>
  );
}
