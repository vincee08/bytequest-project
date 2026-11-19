"use client";

import Link from "next/link";
import { CountBarChart, PercentBarChart } from "@/components/analytics/performance/charts";
import { DataTable, EmptyState, NotApplicable, Panel, Stat } from "@/components/analytics/performance/primitives";
import type { ChartConfig } from "@/components/ui/chart";
import { describePeriod, formatDateTime, formatPercent } from "@/lib/analytics/format";
import type { QuizAnalytics } from "@/lib/analytics/performance-types";
import { analyticsHref, type AnalyticsQuery } from "@/lib/analytics/query";
import { cn } from "@/lib/utils";

const DISTRIBUTION_CONFIG = { learners: { label: "Learners", color: "hsl(var(--chart-1))" } } satisfies ChartConfig;
const QUESTION_CONFIG = { correct_rate: { label: "Correct", color: "hsl(var(--chart-2))" } } satisfies ChartConfig;

const RESULT_STATUS: Record<QuizAnalytics["results"][number]["status"], string> = {
  scored: "Scored",
  pending: "Awaiting evaluation",
  not_submitted: "Not submitted",
  other_class: "Taken in another class",
};

type QuizListRow = QuizAnalytics["quizzes"][number];
type QuizResultRow = QuizAnalytics["results"][number];
type QuestionRow = QuizAnalytics["per_question"][number];

export function QuizzesPanel({ data, query, pathname }: { data: QuizAnalytics; query: AnalyticsQuery; pathname: string }) {
  const period = describePeriod(data.period);
  const notApplicable = Boolean(query.moduleId || query.topicId || query.missionCode);

  return (
    <div className="space-y-6">
      <Panel title="Quizzes in scope" description={`Published quiz versions assigned to the selected classes · ${period}. Select a quiz for its distribution and per-question analysis.`}>
        {notApplicable ? <NotApplicable source="Quizzes" /> : (
          <DataTable<QuizListRow>
            caption="Quiz summary"
            rows={data.quizzes}
            rowKey={(row) => row.id}
            minWidth={900}
            emptyTitle="No submissions in this period"
            columns={[
              { key: "quiz", label: "Quiz", render: (row) => (
                <Link href={analyticsHref(pathname, query, { quizId: row.id })} aria-current={query.quizId === row.id ? "true" : undefined}
                  className={cn("font-medium text-primary hover:underline", query.quizId === row.id && "underline")}>{row.title}</Link>
              ) },
              { key: "coc", label: "COC", render: (row) => row.coc_code?.toUpperCase() ?? "Not mapped" },
              { key: "status", label: "Status", render: (row) => <span className="capitalize">{row.status}</span> },
              { key: "participants", label: "Participants", align: "right", render: (row) => `${row.participants} / ${row.eligible}` },
              { key: "completion", label: "Completion", align: "right", render: (row) => formatPercent(row.completion_rate) },
              { key: "average", label: "Average", align: "right", render: (row) => formatPercent(row.average) },
              { key: "highest", label: "Highest", align: "right", render: (row) => formatPercent(row.highest) },
              { key: "lowest", label: "Lowest", align: "right", render: (row) => formatPercent(row.lowest) },
              { key: "pending", label: "Pending", align: "right", render: (row) => row.pending },
            ]}
          />
        )}
      </Panel>

      {data.quiz ? <QuizDetail data={data} /> : (
        <Panel title="Quiz detail">
          <EmptyState title="Select a quiz" description="Choose a quiz above (or in the Quiz filter) to see participants, score distribution and per-question correctness." />
        </Panel>
      )}
    </div>
  );
}

function QuizDetail({ data }: { data: QuizAnalytics }) {
  const quiz = data.quiz!;
  const hasScores = data.distribution.length > 0;
  return (
    <div className="space-y-6">
      <Panel title={quiz.title} description={`${quiz.coc_code?.toUpperCase() ?? "Not mapped to a COC"} · ${quiz.question_count} questions · status ${quiz.status} · ${describePeriod(data.period)}`}>
        <div className="grid gap-3 p-4 sm:grid-cols-3 sm:p-5 xl:grid-cols-7">
          <Stat label="Participants" value={data.participants} helper="Submitted in the selected classes" />
          <Stat label="Eligible" value={data.eligible} helper="Learners with the quiz assigned" />
          <Stat label="Completion" value={formatPercent(data.completion_rate)} helper={`${data.completed} of ${data.eligible} learners`} />
          <Stat label="Average" value={formatPercent(data.average)} />
          <Stat label="Highest" value={formatPercent(data.highest)} />
          <Stat label="Lowest" value={formatPercent(data.lowest)} />
          <Stat label="Pending" value={data.pending} helper="Excluded from averages" />
        </div>
      </Panel>

      <div className="grid gap-5 xl:grid-cols-2">
        <Panel title="Score distribution" description="Learners per 10-point score band; the counts add up to the scored participants.">
          {hasScores ? (
            <div className="space-y-3 p-4 sm:p-5">
              <CountBarChart data={data.distribution.map((row) => ({ bucket: row.bucket, learners: row.count }))} config={DISTRIBUTION_CONFIG}
                categoryKey="bucket" series={["learners"]} categoryLabel="Score band (%)" valueLabel="Learners" ariaLabel="Quiz score distribution" />
              <table className="w-full text-left text-xs">
                <caption className="sr-only">Score distribution table</caption>
                <thead className="text-muted-foreground"><tr>{data.distribution.map((row) => <th key={row.bucket} className="px-1 py-1 text-center font-medium">{row.bucket}</th>)}</tr></thead>
                <tbody><tr>{data.distribution.map((row) => <td key={row.bucket} className="px-1 py-1 text-center font-semibold tabular-nums">{row.count}</td>)}</tr></tbody>
              </table>
            </div>
          ) : <EmptyState title="No submissions in this period" description="The distribution appears once learners submit this quiz." />}
        </Panel>
        <Panel title="Per-question correctness" description="Share of scored attempts that answered each approved question correctly.">
          {data.per_question.length ? (
            <div className="p-4 sm:p-5">
              <PercentBarChart data={data.per_question.map((row) => ({ question: row.code, correct_rate: row.correct_rate }))} config={QUESTION_CONFIG}
                categoryKey="question" series={["correct_rate"]} categoryLabel="Question" valueLabel="Correct (%)" ariaLabel="Per-question correctness"
                layout="vertical" height={Math.max(180, data.per_question.length * 38)} />
            </div>
          ) : <EmptyState title="No scored answers yet" />}
          <DataTable<QuestionRow>
            caption="Per-question correctness table"
            rows={data.per_question}
            rowKey={(row) => row.item_id}
            minWidth={560}
            emptyTitle="No scored answers yet."
            columns={[
              { key: "code", label: "Question", render: (row) => <div className="max-w-[340px]"><p className="font-medium">{row.code}</p><p className="mt-0.5 line-clamp-2 text-xs text-muted-foreground">{row.prompt}</p></div> },
              { key: "type", label: "Type", render: (row) => <span className="text-xs">{row.type.replaceAll("_", " ")}</span> },
              { key: "answered", label: "Answered", align: "right", render: (row) => row.answered },
              { key: "correct", label: "Correct", align: "right", render: (row) => `${row.correct} (${formatPercent(row.correct_rate)})` },
            ]}
          />
        </Panel>
      </div>

      <Panel title="Individual results" description="One row per eligible learner: scored, awaiting evaluation, not submitted, or taken in another class.">
        <DataTable<QuizResultRow>
          caption="Individual quiz results"
          rows={data.results}
          rowKey={(row) => row.learner_id}
          minWidth={760}
          emptyTitle="No submissions in this period"
          columns={[
            { key: "learner", label: "Learner", render: (row) => <div><p className="font-medium">{row.name}</p><p className="mt-0.5 text-xs text-muted-foreground">{row.student_id ?? "No student ID"}</p></div> },
            { key: "class", label: "Class", render: (row) => row.class_title ?? "—" },
            { key: "status", label: "Submission", render: (row) => RESULT_STATUS[row.status] },
            { key: "score", label: "Score", align: "right", render: (row) => (row.score === null ? "—" : `${row.score} / ${row.max_score}`) },
            { key: "percent", label: "Percent", align: "right", render: (row) => formatPercent(row.percent) },
            { key: "submitted", label: "Submitted", render: (row) => <span className="whitespace-nowrap text-xs text-muted-foreground">{formatDateTime(row.submitted_at)}</span> },
          ]}
        />
      </Panel>
    </div>
  );
}
