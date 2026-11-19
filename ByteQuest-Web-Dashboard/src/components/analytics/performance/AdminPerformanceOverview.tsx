"use client";

import { Download } from "lucide-react";
import { AnalyticsLiveRefresh } from "@/components/analytics/performance/AnalyticsLiveRefresh";
import { OverviewPanel } from "@/components/analytics/performance/OverviewPanel";
import { AnalyticsErrorPanel } from "@/components/analytics/performance/PerformanceAnalyticsWorkspace";
import { Button } from "@/components/ui/button";
import type { AnalyticsErrorCode, AnalyticsOverview } from "@/lib/analytics/performance-types";
import { analyticsSearchParams, type AnalyticsQuery } from "@/lib/analytics/query";

/**
 * The instructor overview, scoped by PostgreSQL to every active class for an
 * admin. Instructor-only routes (/analytics, /progress) are not linked: the
 * middleware keeps admins in the admin workspace.
 */
export function AdminPerformanceOverview({
  overview,
  errorCode,
  query,
}: {
  overview: AnalyticsOverview | null;
  errorCode: AnalyticsErrorCode | null;
  query: AnalyticsQuery;
}) {
  const exportHref = `/api/reports/export?${analyticsSearchParams(query, { tab: "overview" }).toString()}`;
  return (
    <section aria-labelledby="admin-performance-heading" className="mx-auto max-w-[1500px] space-y-5 pt-8">
      <div className="flex flex-col gap-3 border-b border-border/70 pb-4 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <h2 id="admin-performance-heading" className="text-lg font-semibold tracking-tight">Learner performance · all classes</h2>
          <p className="mt-1 max-w-3xl text-[13px] leading-6 text-muted-foreground">The overview instructors see for their classes, aggregated over every active class for the selected period.</p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          {overview ? <AnalyticsLiveRefresh generatedAt={overview.generated_at} /> : null}
          {overview ? (
            <Button asChild variant="outline"><a href={exportHref} download><Download className="mr-2 h-4 w-4" aria-hidden="true" />Export overview CSV</a></Button>
          ) : null}
        </div>
      </div>
      {overview ? (
        <OverviewPanel data={overview} query={query} pathname={null} scopeLabel="every active class" />
      ) : (
        <AnalyticsErrorPanel code={errorCode ?? "ANALYTICS_UNAVAILABLE"} resetHref="/admin/analytics?range=30" />
      )}
    </section>
  );
}
