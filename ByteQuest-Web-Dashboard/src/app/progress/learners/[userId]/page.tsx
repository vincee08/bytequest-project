import { notFound } from "next/navigation";
import { LearnerProfileView } from "@/components/analytics/performance/LearnerProfileView";
import { AnalyticsErrorPanel } from "@/components/analytics/performance/PerformanceAnalyticsWorkspace";
import { DashboardLayout } from "@/components/layout/dashboard-layout";
import { AnalyticsRequestError, loadLearnerProfile } from "@/lib/analytics/performance-server";
import { parseAnalyticsQuery } from "@/lib/analytics/query";
import { requireStaffProfile } from "@/lib/auth/server";

export const dynamic = "force-dynamic";

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export default async function LearnerProgressPage({
  params,
  searchParams,
}: {
  params: Promise<{ userId: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  await requireStaffProfile(["instructor", "admin"]);
  const [{ userId }, rawQuery] = await Promise.all([params, searchParams]);
  if (!UUID_PATTERN.test(userId)) notFound();
  const query = { ...parseAnalyticsQuery(rawQuery, new Date(), { tab: "learners", range: "365" }), learnerId: null };

  try {
    const profile = await loadLearnerProfile(userId.toLowerCase(), query);
    return (
      <DashboardLayout>
        <LearnerProfileView profile={profile} query={query} />
      </DashboardLayout>
    );
  } catch (error) {
    if (error instanceof AnalyticsRequestError) {
      // A learner outside the caller's classes is indistinguishable from an unknown learner.
      if (error.code === "ANALYTICS_SCOPE_DENIED") notFound();
      return (
        <DashboardLayout>
          <AnalyticsErrorPanel code={error.code} resetHref={`/progress/learners/${userId}`} />
        </DashboardLayout>
      );
    }
    throw error;
  }
}
