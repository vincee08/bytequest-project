"use client";

import { TrendingDown, TrendingUp } from "lucide-react";
import { PercentBarChart } from "@/components/analytics/performance/charts";
import { DataTable, EmptyState, NotApplicable, Panel } from "@/components/analytics/performance/primitives";
import type { ChartConfig } from "@/components/ui/chart";
import { describePeriod, formatNumber, formatPercent } from "@/lib/analytics/format";
import type { CriteriaAnalytics, CriterionRow } from "@/lib/analytics/performance-types";
import type { AnalyticsQuery } from "@/lib/analytics/query";

const CRITERIA_CONFIG = { percent: { label: "Criterion score", color: "hsl(var(--chart-1))" } } satisfies ChartConfig;

export function CriteriaPanel({ data, query }: { data: CriteriaAnalytics; query: AnalyticsQuery }) {
  if (query.topicId || query.quizId) {
    return <Panel title="Criterion analysis"><NotApplicable source="Assessment criteria" /></Panel>;
  }
  const period = describePeriod(data.period);
  const ranked = [...data.criteria].sort((a, b) => (b.percent ?? -1) - (a.percent ?? -1));
  return (
    <div className="space-y-6">
      <div className="grid gap-5 lg:grid-cols-2">
        <RankList title="Strongest skills" icon="up" rows={data.strongest} empty="Strengths appear after results are released." />
        <RankList title="Weakest skills" icon="down" rows={data.weakest} empty="Weaknesses appear once at least two criteria have released results." />
      </div>
      <Panel title="Assessment criteria" description={`Released technical assessment results only; each learner counts once per criterion (latest released result) · ${period}. Simulation steps and essay rubric criteria are added when those assessments are released.`}>
        {data.criteria.length ? (
          <>
            <div className="p-4 sm:p-5">
              <PercentBarChart data={ranked.map((row) => ({ criterion: row.code, percent: row.percent }))} config={CRITERIA_CONFIG}
                categoryKey="criterion" series={["percent"]} categoryLabel="Criterion" valueLabel="Average score (%)"
                ariaLabel="Average score per assessment criterion" layout="vertical" height={Math.max(200, ranked.length * 36)} />
            </div>
            <DataTable<CriterionRow>
              caption="Assessment criteria"
              rows={ranked}
              rowKey={(row) => row.criterion_id}
              minWidth={900}
              columns={[
                { key: "criterion", label: "Criterion", render: (row) => <div className="max-w-[360px]"><p className="font-medium">{row.title}</p><p className="mt-0.5 text-xs text-muted-foreground">{row.code} · {row.mission_title ?? row.mission_code ?? "Mission"}</p></div> },
                { key: "source", label: "Source", render: (row) => <span className="capitalize">{row.source}</span> },
                { key: "max", label: "Maximum", align: "right", render: (row) => formatNumber(row.max) },
                { key: "avg", label: "Average", align: "right", render: (row) => formatNumber(row.avg, 2) },
                { key: "percent", label: "Percent", align: "right", render: (row) => <span className="font-semibold">{formatPercent(row.percent)}</span> },
                { key: "learners", label: "Learners", align: "right", render: (row) => row.evaluated_learners },
                { key: "satisfied", label: "Satisfied / not", align: "right", render: (row) => `${row.satisfied} / ${row.not_satisfied}` },
              ]}
            />
          </>
        ) : <EmptyState title="No released criterion results in this period" description="Criterion analysis uses released assessment results only; pending evaluations are excluded." />}
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
                  <p className="mt-0.5 text-xs text-muted-foreground">{row.code} · {row.evaluated_learners} learner{row.evaluated_learners === 1 ? "" : "s"}</p>
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
