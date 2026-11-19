import { NextRequest } from "next/server";
import { getInstructorAnalytics, parseAnalyticsFilters } from "@/lib/analytics/server";
import { prepareReport, reportToCsv } from "@/lib/analytics/reports";
import { reportTypeSchema } from "@/lib/analytics/types";
import { analyticsCsvFilename, analyticsTable, learnerProfileTable, tableToCsv } from "@/lib/analytics/performance-csv";
import { AnalyticsRequestError, loadAnalyticsTab, loadLearnerProfile } from "@/lib/analytics/performance-server";
import { ANALYTICS_TABS, parseAnalyticsQuery, type AnalyticsTab } from "@/lib/analytics/query";
import { getServerProfile } from "@/lib/auth/server";

export const dynamic = "force-dynamic";

function csvResponse(csv: string, filename: string) {
  return new Response(csv, {
    headers: {
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": `attachment; filename="${filename}"`,
      "Cache-Control": "private, no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

export async function GET(request: NextRequest) {
  const profile = await getServerProfile();
  if (!profile) {
    return Response.json({ error: "Authentication required." }, { status: 401 });
  }

  // Analytics tab export: /api/reports/export?tab=<tab>&<analytics filters>
  // Learner activity export: /api/reports/export?tab=profile&learner=<id>&<filters>
  const tab = request.nextUrl.searchParams.get("tab");
  if (tab !== null) {
    if (tab !== "profile" && !(ANALYTICS_TABS as readonly string[]).includes(tab)) {
      return Response.json({ error: "Unknown analytics tab." }, { status: 400 });
    }
    if (profile.status !== "active" || (profile.role !== "instructor" && profile.role !== "admin")) {
      return Response.json({ error: "Instructor or Admin access required." }, { status: 403 });
    }
    const query = parseAnalyticsQuery(request.nextUrl.searchParams);
    try {
      if (tab === "profile") {
        if (!query.learnerId) return Response.json({ error: "A learner is required." }, { status: 400 });
        const learnerProfile = await loadLearnerProfile(query.learnerId, { ...query, learnerId: null });
        return csvResponse(tableToCsv(learnerProfileTable(learnerProfile)), analyticsCsvFilename("learner"));
      }
      const view = await loadAnalyticsTab(query, tab as AnalyticsTab);
      return csvResponse(tableToCsv(analyticsTable(view)), analyticsCsvFilename(tab as AnalyticsTab));
    } catch (error) {
      if (error instanceof AnalyticsRequestError) {
        if (error.code === "ANALYTICS_SCOPE_DENIED" || error.code === "ANALYTICS_ACCESS_DENIED") {
          return Response.json({ error: "The requested analytics scope is not available to this account." }, { status: 403 });
        }
        if (error.code === "ANALYTICS_FILTER_INVALID") {
          return Response.json({ error: "The analytics filters are not valid." }, { status: 400 });
        }
      }
      return Response.json({ error: "Analytics export is temporarily unavailable." }, { status: 500 });
    }
  }

  // Legacy report export used by /reports.
  if (profile.status !== "active" || profile.role !== "instructor") {
    return Response.json({ error: "Instructor access required." }, { status: 403 });
  }
  const params = Object.fromEntries(request.nextUrl.searchParams.entries());
  const filters = parseAnalyticsFilters(params);
  const reportType = reportTypeSchema.catch("class_performance").parse(request.nextUrl.searchParams.get("type"));
  const analytics = await getInstructorAnalytics(filters);
  const report = prepareReport(reportType, analytics);
  const date = new Date().toISOString().slice(0, 10);
  return csvResponse(reportToCsv(report), `bytequest-${reportType}-${date}.csv`);
}
