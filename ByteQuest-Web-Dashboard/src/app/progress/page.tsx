import Link from "next/link";
import { Activity, FileSpreadsheet } from "lucide-react";
import { DashboardLayout } from "@/components/layout/dashboard-layout";
import { PageHeader } from "@/components/dashboard/PageHeader";
import { DirectorySearchControls } from "@/components/learners/DirectorySearchControls";
import { DirectoryError, LearnerDirectoryTable } from "@/components/learners/LearnerDirectoryTable";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { requireStaffProfile } from "@/lib/auth/server";
import { learnerSearchHref, learnerSortDefaults, learnerStatusFilters, learnerStatusLabels, parseLearnerSearchParams } from "@/lib/learners/search";
import { runLearnerSearch } from "@/lib/learners/search-server";
import { createServerSupabaseClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Summary = { attempts: number; released: number; latestOutcome: string | null; needsReview: boolean };

export default async function ProgressPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  await requireStaffProfile(["instructor"]);
  const filters = parseLearnerSearchParams(await searchParams);
  const supabase = await createServerSupabaseClient();
  const [search, classes] = await Promise.all([
    runLearnerSearch(supabase, filters),
    supabase.from("classes").select("id,title").eq("status", "active").order("title"),
  ]);

  // Assessment state for the learners on this page only, scoped by RLS to the
  // instructor's own classes (and to the selected class when filtered).
  const ids = search.data?.rows.map((row) => row.user_id) ?? [];
  const summaries = new Map<string, Summary>();
  let summaryError = false;
  if (ids.length) {
    let attemptQuery = supabase.from("attempts").select("id,learner_id,class_id,status,started_at").in("learner_id", ids).order("started_at", { ascending: false });
    if (filters.classId) attemptQuery = attemptQuery.eq("class_id", filters.classId);
    const attempts = await attemptQuery;
    const attemptIds = (attempts.data ?? []).map((row) => row.id);
    const finals = attemptIds.length
      ? await supabase.from("score_revisions").select("attempt_id,outcome").eq("revision_type", "instructor_final").in("attempt_id", attemptIds)
      : { data: [], error: null };
    summaryError = Boolean(attempts.error || finals.error);
    const outcomeByAttempt = new Map((finals.data ?? []).map((row) => [row.attempt_id, row.outcome as string]));
    for (const attempt of attempts.data ?? []) {
      const summary = summaries.get(attempt.learner_id) ?? { attempts: 0, released: 0, latestOutcome: null, needsReview: false };
      summary.attempts += 1;
      if (attempt.status === "evaluated" || attempt.status === "under_review") summary.needsReview = true;
      const outcome = attempt.status === "released" ? outcomeByAttempt.get(attempt.id) : undefined;
      if (outcome) {
        summary.released += 1;
        summary.latestOutcome ??= outcome;
      }
      summaries.set(attempt.learner_id, summary);
    }
  }

  const hidden: Record<string, string> = {};
  if (filters.sort !== "name") hidden.sort = filters.sort;
  if (filters.direction !== learnerSortDefaults[filters.sort]) hidden.dir = filters.direction;
  const classOptions = classes.data ?? [];

  return (
    <DashboardLayout>
      <div className="mx-auto max-w-7xl space-y-7">
        <PageHeader
          title="Learner monitoring"
          description="Search learners in your classes by name, email, student ID or class. Review enrollment-scoped activity, assessment state and released competency outcomes. XP remains separate from official evaluation."
          actions={filters.classId && classOptions.some((row) => row.id === filters.classId)
            ? <Button asChild variant="outline" className="min-h-11"><Link href={`/classes/${filters.classId}/import`}><FileSpreadsheet className="mr-2 h-4 w-4" aria-hidden="true" />Import a roster into this class</Link></Button>
            : null}
        />
        <DirectorySearchControls
          action="/progress"
          label="Search your learners"
          placeholder="Name, email, student ID or class"
          query={filters.q}
          hidden={hidden}
          clearHref="/progress"
          filtered={Boolean(filters.q || filters.classId || filters.status !== "all")}
          selects={[
            { name: "class", label: "Class", value: filters.classId ?? "all", options: [{ value: "all", label: "All my classes" }, ...classOptions.map((row) => ({ value: row.id, label: row.title }))] },
            { name: "status", label: "Account status", value: filters.status, options: learnerStatusFilters.map((value) => ({ value, label: learnerStatusLabels[value] })) },
          ]}
        />
        {summaryError ? <p role="status" className="rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-950">Assessment summaries could not be loaded; learner details are still shown.</p> : null}
        {search.data ? (
          <LearnerDirectoryTable
            basePath="/progress"
            filters={filters}
            result={search.data}
            rowHref={(row) => `/progress/learners/${row.user_id}${filters.classId ? `?class=${filters.classId}` : ""}`}
            emptyTitle="No learners in your classes yet."
            emptyText="Enroll registered learners or import a roster from a class workspace."
            extra={{
              header: "Assessments",
              render: (row) => {
                const summary = summaries.get(row.user_id);
                const intervention = summary?.latestOutcome === "not_yet_competent";
                return (
                  <div className="space-y-1.5 text-xs">
                    <p className="tabular-nums text-muted-foreground"><span className="font-semibold text-foreground">{summary?.attempts ?? 0}</span> attempts · <span className="font-semibold text-foreground">{summary?.released ?? 0}</span> released</p>
                    <Badge variant={intervention ? "destructive" : summary?.needsReview ? "default" : summary?.latestOutcome === "competent" ? "secondary" : "outline"}>
                      {intervention ? "intervention" : summary?.needsReview ? "review pending" : summary?.latestOutcome?.replaceAll("_", " ") ?? "no released result"}
                    </Badge>
                  </div>
                );
              },
            }}
          />
        ) : <DirectoryError message={search.error} retryHref={learnerSearchHref("/progress", filters, {})} />}
        <p className="flex items-center gap-2 text-xs text-muted-foreground"><Activity className="h-3.5 w-3.5" aria-hidden="true" />Intervention is an operational flag, not an invented TESDA decision rule.</p>
      </div>
    </DashboardLayout>
  );
}
