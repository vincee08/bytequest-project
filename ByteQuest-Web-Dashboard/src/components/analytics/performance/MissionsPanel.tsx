"use client";

import { CountBarChart, PercentBarChart } from "@/components/analytics/performance/charts";
import { DataTable, EmptyState, NotApplicable, Panel } from "@/components/analytics/performance/primitives";
import type { ChartConfig } from "@/components/ui/chart";
import { describePeriod, formatDuration, formatNumber, formatPercent } from "@/lib/analytics/format";
import type { MissionAnalytics } from "@/lib/analytics/performance-types";
import type { AnalyticsQuery } from "@/lib/analytics/query";

const RUNS_CONFIG = {
  successful_runs: { label: "Verified runs", color: "hsl(var(--chart-2))" },
  failed_runs: { label: "Incomplete runs", color: "hsl(var(--chart-4))" },
} satisfies ChartConfig;
const COMPLETION_CONFIG = { completion_rate: { label: "Learners verified", color: "hsl(var(--chart-1))" } } satisfies ChartConfig;
const ASSESSMENT_CONFIG = {
  competent: { label: "Competent", color: "hsl(var(--chart-2))" },
  not_yet_competent: { label: "Not yet competent", color: "hsl(var(--chart-4))" },
  pending: { label: "Pending release", color: "hsl(var(--chart-5))" },
} satisfies ChartConfig;

type PracticeRow = MissionAnalytics["missions"][number];
type AssessmentRow = MissionAnalytics["assessments"][number];

const missionLabel = (code: string) => code.toUpperCase().replace("_", " ");

export function MissionsPanel({ data, query }: { data: MissionAnalytics; query: AnalyticsQuery }) {
  const period = describePeriod(data.period);
  const notApplicable = Boolean(query.topicId || query.quizId);
  if (notApplicable) {
    return <Panel title="Mission performance"><NotApplicable source="Missions" /></Panel>;
  }
  return (
    <div className="space-y-6">
      <Panel title="Practice missions" description={`Recorded practice runs in the period and server-verified completions to date · ${period}. Attempt counts come from recorded runs, never from completions.`}>
        {data.missions.length ? (
          <>
            <div className="grid gap-5 p-4 sm:p-5 xl:grid-cols-2">
              <div>
                <p className="mb-2 text-xs font-semibold text-foreground">Runs per mission</p>
                <CountBarChart data={data.missions.map((row) => ({ mission: missionLabel(row.mission_code), successful_runs: row.successful_runs, failed_runs: row.failed_runs }))}
                  config={RUNS_CONFIG} categoryKey="mission" series={["successful_runs", "failed_runs"]} stacked categoryLabel="Mission" valueLabel="Runs"
                  ariaLabel="Verified and incomplete practice runs per mission" />
              </div>
              <div>
                <p className="mb-2 text-xs font-semibold text-foreground">Learners verified per mission</p>
                <PercentBarChart data={data.missions.map((row) => ({ mission: missionLabel(row.mission_code), completion_rate: row.completion_rate }))}
                  config={COMPLETION_CONFIG} categoryKey="mission" series={["completion_rate"]} categoryLabel="Mission" valueLabel="Learners verified (%)"
                  ariaLabel="Share of learners with a verified completion per mission" height={260} />
              </div>
            </div>
            <DataTable<PracticeRow>
              caption="Practice mission performance"
              rows={data.missions}
              rowKey={(row) => row.mission_code}
              minWidth={1100}
              columns={[
                { key: "mission", label: "Mission", render: (row) => <div className="min-w-[200px]"><p className="font-medium">{missionLabel(row.mission_code)} · {row.title}</p><p className="mt-0.5 text-xs text-muted-foreground">{row.module ? `${row.module.code} ${row.module.title}` : "No module"}</p></div> },
                { key: "attempted", label: "Attempted", align: "right", render: (row) => `${row.learners_attempted} / ${row.learners_in_scope}` },
                { key: "verified", label: "Verified", align: "right", render: (row) => row.learners_verified },
                { key: "completion", label: "Completion", align: "right", render: (row) => formatPercent(row.completion_rate) },
                { key: "runs", label: "Runs", align: "right", render: (row) => `${row.runs} (${row.successful_runs} ok · ${row.failed_runs} incomplete)` },
                { key: "per_learner", label: "Runs / learner", align: "right", render: (row) => formatNumber(row.avg_runs_per_learner) },
                { key: "duration", label: "Avg completion time", align: "right", render: (row) => formatDuration(row.avg_duration_seconds) },
                { key: "invalid", label: "Invalid actions / run", align: "right", render: (row) => formatNumber(row.avg_invalid_actions) },
              ]}
            />
          </>
        ) : <EmptyState title="No practice activity in this period" description="Missions appear once learners record practice runs or verified completions." />}
      </Panel>

      <Panel title="Technical assessments by mission" description="Assessment attempts in the period, labelled separately from practice. Pending results are counted but excluded from averages.">
        {data.assessments.length ? (
          <>
            <div className="p-4 sm:p-5">
              <CountBarChart data={data.assessments.map((row) => ({ mission: missionLabel(row.mission_code), competent: row.competent, not_yet_competent: row.not_yet_competent, pending: row.pending }))}
                config={ASSESSMENT_CONFIG} categoryKey="mission" series={["competent", "not_yet_competent", "pending"]} stacked categoryLabel="Mission"
                valueLabel="Attempts" ariaLabel="Assessment outcomes per mission" />
            </div>
            <DataTable<AssessmentRow>
              caption="Technical assessments by mission"
              rows={data.assessments}
              rowKey={(row) => row.mission_code}
              minWidth={900}
              columns={[
                { key: "mission", label: "Mission", render: (row) => <span className="font-medium">{missionLabel(row.mission_code)} · {row.title}</span> },
                { key: "attempts", label: "Attempts", align: "right", render: (row) => row.attempts },
                { key: "submitted", label: "Submitted", align: "right", render: (row) => row.submitted },
                { key: "released", label: "Released", align: "right", render: (row) => row.released },
                { key: "competent", label: "Competent", align: "right", render: (row) => row.competent },
                { key: "nyc", label: "Not yet competent", align: "right", render: (row) => row.not_yet_competent },
                { key: "pending", label: "Pending", align: "right", render: (row) => row.pending },
                { key: "average", label: "Average (released)", align: "right", render: (row) => formatPercent(row.avg_percent) },
              ]}
            />
          </>
        ) : <EmptyState title="No assessment attempts in this period" />}
      </Panel>
    </div>
  );
}
