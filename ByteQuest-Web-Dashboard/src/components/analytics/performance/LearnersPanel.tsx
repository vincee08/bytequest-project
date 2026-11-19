"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import { Search } from "lucide-react";
import { CountBarChart } from "@/components/analytics/performance/charts";
import { DataTable, EmptyState, Panel, StatusBadge } from "@/components/analytics/performance/primitives";
import type { ChartConfig } from "@/components/ui/chart";
import { describePeriod, formatDateTime, formatPercent, reasonText, statusPresentation } from "@/lib/analytics/format";
import { LEARNER_STATUSES, type LearnerPerformance, type LearnerRow, type LearnerStatus } from "@/lib/analytics/performance-types";
import { analyticsSearchParams, type AnalyticsQuery } from "@/lib/analytics/query";
import { cn } from "@/lib/utils";

const STATUS_CONFIG = {
  learners: { label: "Learners", color: "hsl(var(--chart-1))" },
} satisfies ChartConfig;

export function LearnersPanel({ data, query }: { data: LearnerPerformance; query: AnalyticsQuery }) {
  const [status, setStatus] = useState<LearnerStatus | "all">("all");
  const [search, setSearch] = useState("");
  const period = describePeriod(data.period);
  const profileQuery = analyticsSearchParams(query, { learnerId: null }).toString();
  const visible = useMemo(() => {
    const term = search.trim().toLowerCase();
    return data.learners.filter((row) =>
      (status === "all" || row.status === status)
      && (!term || row.name.toLowerCase().includes(term) || (row.student_id ?? "").toLowerCase().includes(term)));
  }, [data.learners, search, status]);

  return (
    <div className="space-y-6">
      <div className="grid gap-5 xl:grid-cols-[minmax(0,1fr)_minmax(320px,0.8fr)]">
        <Panel title="Learner status" description={`${data.learners.length} learner${data.learners.length === 1 ? "" : "s"} · ${period}. Select a status to filter the list.`}>
          <div className="grid gap-3 p-4 sm:grid-cols-3 sm:p-5" role="group" aria-label="Filter learners by status">
            {LEARNER_STATUSES.map((value) => {
              const presentation = statusPresentation(value);
              const active = status === value;
              return (
                <button key={value} type="button" aria-pressed={active} onClick={() => setStatus(active ? "all" : value)}
                  className={cn("min-h-[88px] rounded-lg border p-3 text-left transition-colors duration-150 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
                    active ? presentation.badgeClassName : "border-border/80 bg-background hover:bg-muted/40")}>
                  <span className="text-xs font-semibold">{presentation.label}</span>
                  <span className="mt-1 block text-2xl font-bold tabular-nums">{data.counts[value]}</span>
                  <span className="mt-1 block text-[11px] leading-4 text-muted-foreground">{presentation.description}</span>
                </button>
              );
            })}
          </div>
        </Panel>
        <Panel title="Learners by status" description="Count of learners per status in the current scope.">
          {data.learners.length ? (
            <div className="p-4 sm:p-5">
              <CountBarChart data={LEARNER_STATUSES.map((value) => ({ status: statusPresentation(value).label, learners: data.counts[value] }))}
                config={STATUS_CONFIG} categoryKey="status" series={["learners"]} categoryLabel="Status" valueLabel="Learners"
                ariaLabel="Learners by status" height={220} />
            </div>
          ) : <EmptyState title="No learners in scope" />}
        </Panel>
      </div>

      <Panel title="Learner progress and status" description={`Thresholds: inactive ${data.thresholds.inactivity_days} days, progress below ${data.thresholds.progress_ratio_of_class_median * 100}% of the class median, quiz average below ${data.thresholds.quiz_average_below}%, ${data.thresholds.incomplete_runs_on_one_mission}+ incomplete runs on one mission.`}
        action={
          <label className="relative block">
            <span className="sr-only">Search learners by name or student ID</span>
            <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" aria-hidden="true" />
            <input type="search" value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Search name or student ID"
              className="h-10 w-full rounded-lg border border-input bg-background pl-9 pr-3 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring sm:w-64" />
          </label>
        }>
        <DataTable<LearnerRow>
          caption="Learner progress and status"
          rows={visible}
          rowKey={(row) => row.id}
          minWidth={1300}
          emptyTitle={data.learners.length ? "No learner matches this status or search." : "No active learners in scope."}
          columns={[
            { key: "learner", label: "Learner", render: (row) => (
              <div className="min-w-[170px]">
                <Link href={`/progress/learners/${row.id}${profileQuery ? `?${profileQuery}` : ""}`} className="font-medium text-primary hover:underline">{row.name || "Unnamed learner"}</Link>
                <p className="mt-0.5 text-xs text-muted-foreground">{row.student_id ?? "No student ID"} · {row.classes.map((item) => item.title).join(", ")}</p>
              </div>
            ) },
            { key: "status", label: "Status", render: (row) => (
              <div className="min-w-[220px] space-y-1.5">
                <StatusBadge status={row.status} />
                {row.reasons.length ? (
                  <ul className="space-y-0.5 text-xs leading-5 text-muted-foreground">
                    {row.reasons.map((reason) => <li key={reason.code}>{reasonText(reason)}</li>)}
                  </ul>
                ) : null}
              </div>
            ) },
            { key: "progress", label: "Progress", align: "right", render: (row) => formatPercent(row.progress_percent) },
            { key: "score", label: "Performance", align: "right", render: (row) => formatPercent(row.performance_score) },
            { key: "quiz", label: "Quiz avg", align: "right", render: (row) => formatPercent(row.quiz_avg) },
            { key: "assessment", label: "Assessments", align: "right", render: (row) => (
              <span>{row.assessment.competent}/{row.assessment.released} competent{row.assessment.pending ? <span className="block text-[11px] text-muted-foreground">{row.assessment.pending} pending</span> : null}</span>
            ) },
            { key: "missions", label: "Missions", align: "right", render: (row) => (
              <span>{row.missions_verified} verified<span className="block text-[11px] text-muted-foreground">{row.practice_runs} runs</span></span>
            ) },
            { key: "homework", label: "Homework", align: "right", render: (row) => (
              <span>{row.assignments.submitted} submitted<span className="block text-[11px] text-muted-foreground">{row.assignments.pending_evaluation} awaiting evaluation · {row.assignments.missing} missing · {row.assignments.late} late</span></span>
            ) },
            { key: "activity", label: "Last activity", render: (row) => <span className="whitespace-nowrap text-xs text-muted-foreground">{formatDateTime(row.last_activity_at)}</span> },
            // Engagement points and level: engagement, not competency or a score.
            { key: "engagement", label: "Engagement", align: "right", render: (row) => (
              <span className="whitespace-nowrap">{row.engagement.points} pts
                <span className="block text-[11px] text-muted-foreground">{row.engagement.level_title ?? "No level"} · +{row.engagement.points_in_period} in period</span></span>
            ) },
          ]}
        />
        <p className="border-t border-border/70 px-5 py-2.5 text-xs text-muted-foreground">
          Engagement shows points and level. Points reward activity; they are not a competency judgement and are not part of the performance score.
        </p>
      </Panel>
    </div>
  );
}
