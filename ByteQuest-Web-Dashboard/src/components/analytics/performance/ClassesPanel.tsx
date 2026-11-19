"use client";

import Link from "next/link";
import { ArrowRight } from "lucide-react";
import { PercentBarChart } from "@/components/analytics/performance/charts";
import { DataTable, EmptyState, Panel, Stat } from "@/components/analytics/performance/primitives";
import type { ChartConfig } from "@/components/ui/chart";
import { describePeriod, formatNumber, formatPercent } from "@/lib/analytics/format";
import type { ClassPerformance } from "@/lib/analytics/performance-types";
import { analyticsHref, type AnalyticsQuery } from "@/lib/analytics/query";

const COMPARISON_CONFIG = {
  avg_score: { label: "Average score", color: "hsl(var(--chart-1))" },
  quiz_avg: { label: "Quiz average", color: "hsl(var(--chart-2))" },
  progress_avg: { label: "Learning progress", color: "hsl(var(--chart-3))" },
} satisfies ChartConfig;

type ClassRow = ClassPerformance["classes"][number];

export function ClassesPanel({ data, query, pathname }: { data: ClassPerformance; query: AnalyticsQuery; pathname: string }) {
  const period = describePeriod(data.period);
  const learnerLink = (row: ClassRow) => analyticsHref(pathname, { ...query, classId: row.id, learnerId: null }, { tab: "learners" });

  if (!data.classes.length) {
    return (
      <Panel title="Class comparison">
        <EmptyState title="No active class is in scope" description="Create a class or clear the class filter to compare class performance." />
      </Panel>
    );
  }

  return (
    <div className="space-y-6">
      <Panel title="All selected classes" description={`Each learner counted once across ${data.classes.length} class${data.classes.length === 1 ? "" : "es"} · ${period}`}>
        <div className="grid gap-3 p-4 sm:grid-cols-2 sm:p-5 lg:grid-cols-4 2xl:grid-cols-7">
          <Stat label="Learners" value={data.summary.enrolled} helper={`${data.summary.active_in_period} active in period`} />
          <Stat label="Average score" value={formatPercent(data.summary.avg_score)} helper="Mean of learner performance scores" />
          <Stat label="Quiz average" value={formatPercent(data.summary.quiz_avg)} helper="Scored quiz attempts" />
          <Stat label="Competent rate" value={formatPercent(data.summary.assessment_competent_rate)} helper="Released assessments" />
          <Stat label="Mission completion" value={formatPercent(data.summary.mission_completion_rate)} helper="Verified learner-mission pairs" />
          <Stat label="Homework completion" value={formatPercent(data.summary.assignment_completion_rate)} helper="Submitted of eligible" />
          <Stat label="Learning progress" value={formatPercent(data.summary.progress_avg)} helper="Average per learner" />
        </div>
      </Panel>

      <Panel title="Class comparison" description="Average score, quiz average and learning progress per class. Results count in the class where the work was done; practice and progress belong to the learner.">
        <div className="space-y-2 p-4 sm:p-5">
          <PercentBarChart data={data.classes.map((row) => ({ class: row.title, avg_score: row.avg_score, quiz_avg: row.quiz_avg, progress_avg: row.progress_avg }))}
            config={COMPARISON_CONFIG} categoryKey="class" series={["avg_score", "quiz_avg", "progress_avg"]} categoryLabel="Class"
            valueLabel="Percent (%)" ariaLabel="Class comparison of average score, quiz average and learning progress" height={300} />
          <ul className="flex flex-wrap gap-4 text-xs text-muted-foreground" aria-label="Chart legend">
            {Object.entries(COMPARISON_CONFIG).map(([key, item]) => (
              <li key={key} className="flex items-center gap-1.5"><span className="h-2.5 w-2.5 rounded-sm" style={{ background: item.color }} aria-hidden="true" />{item.label}</li>
            ))}
          </ul>
        </div>
        <DataTable<ClassRow>
          caption="Class comparison table"
          rows={data.classes}
          rowKey={(row) => row.id}
          minWidth={1100}
          columns={[
            { key: "class", label: "Class", render: (row) => (
              <div><p className="font-medium">{row.title}</p><p className="mt-0.5 text-xs text-muted-foreground">{row.class_code ?? "No class code"}</p></div>
            ) },
            { key: "enrolled", label: "Enrolled", align: "right", render: (row) => `${row.enrolled} (${row.active_in_period} active)` },
            { key: "avg", label: "Average score", align: "right", render: (row) => formatPercent(row.avg_score) },
            { key: "quiz", label: "Quiz average", align: "right", render: (row) => formatPercent(row.quiz_avg) },
            { key: "competent", label: "Competent rate", align: "right", render: (row) => formatPercent(row.assessment_competent_rate) },
            { key: "mission", label: "Mission completion", align: "right", render: (row) => formatPercent(row.mission_completion_rate) },
            { key: "homework", label: "Homework completion", align: "right", render: (row) => formatPercent(row.assignment_completion_rate) },
            { key: "progress", label: "Learning progress", align: "right", render: (row) => formatPercent(row.progress_avg) },
            { key: "highest", label: "Highest", render: (row) => row.highest ? <span>{row.highest.name} <span className="text-muted-foreground">({formatNumber(row.highest.score)}%)</span></span> : "—" },
            { key: "lowest", label: "Lowest", render: (row) => row.lowest ? <span>{row.lowest.name} <span className="text-muted-foreground">({formatNumber(row.lowest.score)}%)</span></span> : "—" },
            { key: "drill", label: "Drill down", align: "right", render: (row) => (
              <Link href={learnerLink(row)} className="inline-flex min-h-9 items-center gap-1 text-xs font-medium text-primary hover:underline">
                Learners<ArrowRight className="h-3.5 w-3.5" aria-hidden="true" /><span className="sr-only"> in {row.title}</span>
              </Link>
            ) },
          ]}
        />
      </Panel>
    </div>
  );
}
