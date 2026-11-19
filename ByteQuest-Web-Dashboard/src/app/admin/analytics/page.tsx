import { AdminSystemAnalyticsDashboard } from "@/components/analytics/AdminSystemAnalyticsDashboard";
import { AdminPerformanceOverview } from "@/components/analytics/performance/AdminPerformanceOverview";
import { DashboardLayout } from "@/components/layout/dashboard-layout";
import { AnalyticsRequestError, loadAnalyticsTab } from "@/lib/analytics/performance-server";
import type { AnalyticsErrorCode, AnalyticsOverview } from "@/lib/analytics/performance-types";
import { parseAnalyticsQuery } from "@/lib/analytics/query";
import { getAdminAnalytics, parseAnalyticsFilters } from "@/lib/analytics/server";
import { requireStaffProfile } from "@/lib/auth/server";

export const dynamic = "force-dynamic";

export default async function AdminAnalyticsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  await requireStaffProfile(["admin"]);
  const params = await searchParams;
  const filters = parseAnalyticsFilters(params);
  // The system period filter (7/30/90 days) also scopes the performance overview.
  const query = parseAnalyticsQuery({ range: filters.range === "custom" ? "30" : filters.range }, new Date(), { tab: "overview" });

  const [data, overviewResult] = await Promise.all([
    getAdminAnalytics(filters),
    loadAnalyticsTab(query, "overview").then(
      (view) => ({ overview: view.tab === "overview" ? view.data : null, errorCode: null as AnalyticsErrorCode | null }),
      (error: unknown) => {
        if (error instanceof AnalyticsRequestError) return { overview: null as AnalyticsOverview | null, errorCode: error.code };
        throw error;
      },
    ),
  ]);

  return (
    <DashboardLayout>
      <AdminSystemAnalyticsDashboard data={data} range={filters.range} />
      <AdminPerformanceOverview overview={overviewResult.overview} errorCode={overviewResult.errorCode} query={query} />
    </DashboardLayout>
  );
}
