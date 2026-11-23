"use client";

import Link from "next/link";
import { useTransition } from "react";
import { usePathname, useRouter } from "next/navigation";
import { AlertTriangle, Download, FileText } from "lucide-react";
import { AnalyticsFilterBar } from "@/components/analytics/performance/AnalyticsFilterBar";
import { AnalyticsLiveRefresh } from "@/components/analytics/performance/AnalyticsLiveRefresh";
import { ClassesPanel } from "@/components/analytics/performance/ClassesPanel";
import { CriteriaPanel } from "@/components/analytics/performance/CriteriaPanel";
import { LearnersPanel } from "@/components/analytics/performance/LearnersPanel";
import { MissionsPanel } from "@/components/analytics/performance/MissionsPanel";
import { OverviewPanel } from "@/components/analytics/performance/OverviewPanel";
import { QuizzesPanel } from "@/components/analytics/performance/QuizzesPanel";
import { PageHeader } from "@/components/dashboard/PageHeader";
import { Button } from "@/components/ui/button";
import type { LearnerStatusState } from "@/lib/analytics/learner-status";
import type { AnalyticsTabData, AnalyticsViewResult } from "@/lib/analytics/performance-csv";
import type { AnalyticsErrorCode } from "@/lib/analytics/performance-types";
import {
  ANALYTICS_TABS,
  ANALYTICS_TAB_LABELS,
  analyticsHref,
  analyticsSearchParams,
  type AnalyticsQuery,
} from "@/lib/analytics/query";
import { cn } from "@/lib/utils";

const ERROR_COPY: Record<AnalyticsErrorCode, { title: string; body: string }> = {
  ANALYTICS_SCOPE_DENIED: {
    title: "This selection is outside your analytics scope",
    body: "The class, quiz or learner in these filters does not belong to a class you can analyse. Clear the filters to return to your classes.",
  },
  ANALYTICS_FILTER_INVALID: {
    title: "These filters cannot be applied",
    body: "One filter value is not valid (for example a period longer than 366 days). Clear the filters and choose them again.",
  },
  ANALYTICS_ACCESS_DENIED: {
    title: "Analytics require an active instructor or admin account",
    body: "Sign in again with an active staff account.",
  },
  ANALYTICS_UNAVAILABLE: {
    title: "Analytics are temporarily unavailable",
    body: "The analytics request did not complete. No learner or assessment data was changed. Try again in a moment.",
  },
};

export function PerformanceAnalyticsWorkspace({
  query,
  result,
  role,
}: {
  query: AnalyticsQuery;
  result: AnalyticsViewResult;
  role: "instructor" | "admin";
}) {
  const router = useRouter();
  const pathname = usePathname();
  const [pending, startTransition] = useTransition();
  const navigate = (href: string) => startTransition(() => router.push(href, { scroll: false }));
  const exportHref = `/api/reports/export?${analyticsSearchParams(query).toString()}`;
  const scopeLabel = role === "admin" ? "every active class" : "your active classes";

  return (
    <div className="mx-auto max-w-[1500px] space-y-6">
      <PageHeader
        title="Performance analytics"
        description={`Monitor learner progress, competency achievement, scores and assessment results for ${scopeLabel}. Every value is a live PostgreSQL aggregate; pending evaluations are shown separately and never averaged in.`}
        actions={
          <>
            {result.ok ? <AnalyticsLiveRefresh generatedAt={result.view.data.generated_at} /> : null}
            <Button asChild variant="outline" disabled={!result.ok}>
              <a href={exportHref} download aria-disabled={!result.ok}>
                <Download className="mr-2 h-4 w-4" aria-hidden="true" />Export {ANALYTICS_TAB_LABELS[query.tab]} CSV
              </a>
            </Button>
            {role === "instructor" ? (
              <Button asChild variant="ghost"><Link href="/reports"><FileText className="mr-2 h-4 w-4" aria-hidden="true" />Reports</Link></Button>
            ) : null}
          </>
        }
      />

      {result.options ? (
        <AnalyticsFilterBar query={query} options={result.options} pathname={pathname} pending={pending} navigate={navigate} />
      ) : null}

      <nav aria-label="Analytics sections" className="overflow-x-auto">
        <ul className="inline-flex min-h-11 items-center gap-1 rounded-xl border border-border/70 bg-muted/55 p-1">
          {ANALYTICS_TABS.map((tab) => {
            const active = tab === query.tab;
            return (
              <li key={tab}>
                <Link
                  href={analyticsHref(pathname, query, { tab })}
                  scroll={false}
                  aria-current={active ? "page" : undefined}
                  onClick={(event) => {
                    event.preventDefault();
                    navigate(analyticsHref(pathname, query, { tab }));
                  }}
                  className={cn(
                    "inline-flex min-h-9 items-center whitespace-nowrap rounded-lg px-3.5 text-sm font-medium transition-[background-color,color,box-shadow] duration-150 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
                    active ? "bg-card text-foreground shadow-xs" : "text-muted-foreground hover:text-foreground",
                  )}
                >
                  {ANALYTICS_TAB_LABELS[tab]}
                </Link>
              </li>
            );
          })}
        </ul>
      </nav>

      <div aria-busy={pending} className={cn("transition-opacity duration-200 motion-reduce:transition-none", pending && "pointer-events-none opacity-60")}>
        {result.ok ? (
          <TabContent view={result.view} learnerStatus={result.learnerStatus} query={query} pathname={pathname} scopeLabel={scopeLabel} />
        ) : (
          <AnalyticsErrorPanel code={result.code} resetHref={`${pathname}?tab=${query.tab}&range=30`} onRetry={() => startTransition(() => router.refresh())} />
        )}
      </div>
    </div>
  );
}

function TabContent({ view, learnerStatus, query, pathname, scopeLabel }: { view: AnalyticsTabData; learnerStatus?: LearnerStatusState; query: AnalyticsQuery; pathname: string; scopeLabel: string }) {
  switch (view.tab) {
    case "overview": return <OverviewPanel data={view.data} learnerStatus={learnerStatus} query={query} pathname={pathname} scopeLabel={scopeLabel} />;
    case "classes": return <ClassesPanel data={view.data} query={query} pathname={pathname} />;
    case "learners": return <LearnersPanel data={view.data} query={query} />;
    case "quizzes": return <QuizzesPanel data={view.data} query={query} pathname={pathname} />;
    case "missions": return <MissionsPanel data={view.data} query={query} />;
    case "criteria": return <CriteriaPanel data={view.data} query={query} />;
  }
}

export function AnalyticsErrorPanel({ code, resetHref, onRetry }: { code: AnalyticsErrorCode; resetHref: string; onRetry?: () => void }) {
  const copy = ERROR_COPY[code];
  return (
    <div role="alert" className="mx-auto max-w-2xl rounded-xl border border-destructive/25 bg-card p-7 text-center">
      <AlertTriangle className="mx-auto h-7 w-7 text-destructive" aria-hidden="true" />
      <h2 className="mt-4 text-lg font-semibold">{copy.title}</h2>
      <p className="mt-2 text-sm leading-6 text-muted-foreground">{copy.body}</p>
      <div className="mt-5 flex flex-wrap justify-center gap-2">
        <Button asChild variant="outline"><Link href={resetHref}>Clear filters</Link></Button>
        {onRetry && code === "ANALYTICS_UNAVAILABLE" ? <Button type="button" onClick={onRetry}>Try again</Button> : null}
      </div>
    </div>
  );
}
