import { PerformanceAnalyticsWorkspace } from "@/components/analytics/performance/PerformanceAnalyticsWorkspace";
import { DashboardLayout } from "@/components/layout/dashboard-layout";
import { loadAnalyticsView } from "@/lib/analytics/performance-server";
import { parseAnalyticsQuery } from "@/lib/analytics/query";
import { requireStaffProfile } from "@/lib/auth/server";

export const dynamic = "force-dynamic";

export default async function AnalyticsPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const profile = await requireStaffProfile(["instructor", "admin"]);
  const query = parseAnalyticsQuery(await searchParams);
  const result = await loadAnalyticsView(query);

  return (
    <DashboardLayout>
      <PerformanceAnalyticsWorkspace query={query} result={result} role={profile.role === "admin" ? "admin" : "instructor"} />
    </DashboardLayout>
  );
}
