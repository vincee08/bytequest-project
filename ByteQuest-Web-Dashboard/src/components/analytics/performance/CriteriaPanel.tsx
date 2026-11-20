"use client";

import { TrendingDown, TrendingUp } from "lucide-react";
import { PercentBarChart } from "@/components/analytics/performance/charts";
import { DataTable, EmptyState, Panel } from "@/components/analytics/performance/primitives";
import type { ChartConfig } from "@/components/ui/chart";
import { describePeriod, formatNumber, formatPercent } from "@/lib/analytics/format";
import type { CriteriaAnalytics, CriterionRow, CriterionSource, StepRef } from "@/lib/analytics/performance-types";
import type { AnalyticsQuery } from "@/lib/analytics/query";

const CRITERIA_CONFIG = { percent: { label: "Criterion score", color: "hsl(var(--chart-1))" } } satisfies ChartConfig;

export const CRITERION_SOURCE_LABELS: Record<CriterionSource, string> = {
  assessment: "Technical assessment",
  simulation: "Simulation step",
  homework: "Homework",
  essay: "Quiz essay",
};

const RECORD_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * The rubric code shown beside a criterion ("C1", "COC1-M2-02-…"), or null
 * when the criterion has only a record id (homework criteria): a raw id is
 * never shown, the homework title names the criterion instead.
 */
export function criterionCode(row: Pick<CriterionRow, "code">): string | null {
  return RECORD_ID.test(row.code) ? null : row.code;
}

/** "Step 2 · Prepare the motherboard" for the steps a simulation criterion checks. */
export function describeSteps(steps: StepRef[]): string {
  return steps.map((step) => (step.step ? `Step ${step.step} · ${step.title}` : step.title)).join("; ");
}

// The query is part of the shared panel signature; filters are applied by the
// server (assessment and homework criteria under a topic or quiz filter are
// not applicable, quiz essays are).
export function CriteriaPanel({ data }: { data: CriteriaAnalytics; query?: AnalyticsQuery }) {
  const period = describePeriod(data.period);
  const ranked = [...data.criteria].sort((a, b) => (b.percent ?? -1) - (a.percent ?? -1));
  return (
    <div className="space-y-6">
      <div className="grid gap-5 lg:grid-cols-2">
        <RankList title="Strongest skills" icon="up" rows={data.strongest} empty="Strengths appear after results are released." />
        <RankList title="Weakest skills" icon="down" rows={data.weakest} empty="Weaknesses appear once at least two criteria have released results." />
      </div>
      <Panel title="Criteria" description={`Released results only: technical assessment and simulation-step criteria, homework criteria and quiz essay rubric criteria. Each learner counts once per criterion (latest released result) · ${period}.`}>
        {data.criteria.length ? (
          <>
            <div className="p-4 sm:p-5">
              <PercentBarChart data={ranked.map((row) => ({ criterion: criterionCode(row) ?? row.title, percent: row.percent }))} config={CRITERIA_CONFIG}
                categoryKey="criterion" series={["percent"]} categoryLabel="Criterion" valueLabel="Average score (%)"
                ariaLabel="Average score per assessment criterion" layout="vertical" height={Math.max(200, ranked.length * 36)} />
            </div>
            <DataTable<CriterionRow>
              caption="Assessment criteria"
              rows={ranked}
              rowKey={(row) => row.criterion_id}
              minWidth={900}
              columns={[
                { key: "criterion", label: "Criterion", render: (row) => <div className="max-w-[360px]"><p className="font-medium">{row.title}</p><p className="mt-0.5 text-xs text-muted-foreground">{[criterionCode(row), row.activity_title ?? row.mission_title ?? row.mission_code ?? "Activity"].filter(Boolean).join(" · ")}{row.source === "homework" && row.mission_title ? ` · ${row.mission_title}` : ""}</p>{row.steps.length ? <p className="mt-0.5 text-xs text-muted-foreground">{describeSteps(row.steps)}</p> : null}</div> },
                { key: "source", label: "Source", render: (row) => CRITERION_SOURCE_LABELS[row.source] },
                { key: "max", label: "Maximum", align: "right", render: (row) => formatNumber(row.max) },
                { key: "avg", label: "Average", align: "right", render: (row) => formatNumber(row.avg, 2) },
                { key: "percent", label: "Percent", align: "right", render: (row) => <span className="font-semibold">{formatPercent(row.percent)}</span> },
                { key: "learners", label: "Learners", align: "right", render: (row) => row.evaluated_learners },
                { key: "satisfied", label: "Satisfied / not", align: "right", render: (row) => (row.satisfied === null ? "Points-based" : `${row.satisfied} / ${row.not_satisfied ?? 0}`) },
              ]}
            />
          </>
        ) : <EmptyState title="No released criterion results in this period" description="Criterion analysis uses released results only; pending evaluations are excluded. Under a topic or quiz filter only quiz essay criteria apply." />}
      </Panel>
    </div>
  );
}

function RankList({ title, icon, rows, empty }: { title: string; icon: "up" | "down"; rows: CriterionRow[]; empty: string }) {
  const Icon = icon === "up" ? TrendingUp : TrendingDown;
  return (
    <Panel title={title}>
      {rows.length ? (
        <ol className="divide-y divide-border">
          {rows.map((row, index) => (
            <li key={row.criterion_id} className="flex items-center justify-between gap-4 px-5 py-3.5">
              <div className="flex min-w-0 items-start gap-3">
                <span className="mt-0.5 flex h-7 w-7 shrink-0 items-center justify-center rounded-md bg-muted text-xs font-semibold" aria-hidden="true">{index + 1}</span>
                <div className="min-w-0">
                  <p className="truncate text-sm font-medium">{row.title}</p>
                  <p className="mt-0.5 text-xs text-muted-foreground">{CRITERION_SOURCE_LABELS[row.source]} · {criterionCode(row) ?? row.activity_title ?? "Criterion"} · {row.evaluated_learners} learner{row.evaluated_learners === 1 ? "" : "s"}</p>
                </div>
              </div>
              <span className={icon === "up" ? "flex items-center gap-1 text-sm font-semibold text-emerald-700" : "flex items-center gap-1 text-sm font-semibold text-amber-800"}>
                <Icon className="h-4 w-4" aria-hidden="true" />{formatPercent(row.percent)}
              </span>
            </li>
          ))}
        </ol>
      ) : <EmptyState title={empty} />}
    </Panel>
  );
}
