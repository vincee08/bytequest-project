import Link from "next/link";
import { ArrowRight, CheckCircle2, ClipboardCheck, GraduationCap, Users } from "lucide-react";
import { DashboardLayout } from "@/components/layout/dashboard-layout";
import { MetricStrip, type Metric } from "@/components/dashboard/MetricStrip";
import { PageHeader } from "@/components/dashboard/PageHeader";
import { InstructorOverviewPanels } from "@/components/dashboard/InstructorOverviewPanels";
import { buildUpcomingTasks } from "@/components/dashboard/upcoming-tasks";
import { LearnerStatusBoard } from "@/components/analytics/performance/LearnerStatusBoard";
import { Button } from "@/components/ui/button";
import { activitiesClient } from "@/lib/activities/types";
import { loadLearnerStatus } from "@/lib/analytics/performance-server";
import { parseAnalyticsQuery } from "@/lib/analytics/query";
import { requireStaffProfile } from "@/lib/auth/server";
import { createServerSupabaseClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

const PENDING_REVIEW_PREVIEW = 5;

export default async function InstructorDashboardPage() {
  const profile = await requireStaffProfile(["instructor"]);
  const supabase = await createServerSupabaseClient();
  const now = new Date();
  const nowIso = now.toISOString();
  // Same rules and default 30-day period as the analytics Learners tab; loads in parallel.
  const learnerStatus = loadLearnerStatus(parseAnalyticsQuery({}, now, { tab: "learners" }));

  const [classes, memberships, attempts, pendingReviews, pendingAttemptCount, releasedAttemptCount, assignments, revisions, quizDeadlines, homeworkDeadlines] = await Promise.all([
    supabase
      .from("classes")
      .select("id,title,class_code,status,created_at")
      .order("created_at", { ascending: false }),
    supabase
      .from("class_memberships")
      .select("id,status,learner_id,class_id")
      .eq("status", "active"),
    supabase
      .from("attempts")
      .select("id,status,class_id,assignment_id,learner_id,submitted_at,created_at")
      .order("created_at", { ascending: false })
      .limit(8),
    // The review queue reads pending attempts directly (oldest first), so it
    // never depends on which attempts happen to be the most recent.
    supabase
      .from("attempts")
      .select("id,status,class_id,assignment_id,learner_id,submitted_at,created_at")
      .in("status", ["evaluated", "under_review"])
      .order("submitted_at", { ascending: true, nullsFirst: false })
      .order("created_at", { ascending: true })
      .limit(PENDING_REVIEW_PREVIEW),
    supabase
      .from("attempts")
      .select("id", { count: "exact", head: true })
      .in("status", ["evaluated", "under_review"]),
    supabase
      .from("attempts")
      .select("id", { count: "exact", head: true })
      .eq("status", "released"),
    supabase
      .from("assignments")
      .select("id,class_id,title,assignment_type,status,due_at")
      .order("due_at", { ascending: true, nullsFirst: false }),
    supabase
      .from("score_revisions")
      .select("attempt_id,percentage,outcome")
      .eq("revision_type", "instructor_final"),
    supabase
      .from("quiz_assignments")
      .select("id,class_id,due_at,status,quiz_versions(status,quizzes(title))")
      .eq("status", "active")
      .gte("due_at", nowIso)
      .order("due_at", { ascending: true })
      .limit(20),
    activitiesClient(supabase)
      .from("homework_assignments")
      .select("id,class_id,title,status,deadline_at")
      .eq("status", "published")
      .gte("deadline_at", nowIso)
      .order("deadline_at", { ascending: true })
      .limit(20),
  ]);

  if (
    classes.error ||
    memberships.error ||
    attempts.error ||
    pendingReviews.error ||
    pendingAttemptCount.error ||
    releasedAttemptCount.error ||
    assignments.error ||
    revisions.error ||
    quizDeadlines.error ||
    homeworkDeadlines.error
  ) {
    throw new Error("The Instructor dashboard summary could not be loaded.");
  }

  const classRows = classes.data ?? [];
  const membershipRows = memberships.data ?? [];
  const attemptRows = attempts.data ?? [];
  const reviewRows = pendingReviews.data ?? [];
  const pendingTotal = pendingAttemptCount.count ?? 0;

  const learnerIds = [...new Set([...attemptRows, ...reviewRows].map((attempt) => attempt.learner_id))];
  const { data: learners, error: learnersError } = learnerIds.length
    ? await supabase
        .from("profiles")
        .select("user_id,full_name")
        .in("user_id", learnerIds)
    : { data: [], error: null };
  if (learnersError) {
    throw new Error("Recent learner details could not be loaded.");
  }
  const learnerNames = new Map(
    (learners ?? []).map((learner) => [learner.user_id, learner.full_name]),
  );
  const upcoming = buildUpcomingTasks({
    now,
    classes: classRows,
    quizzes: quizDeadlines.data ?? [],
    homework: homeworkDeadlines.data ?? [],
    assignments: assignments.data ?? [],
  });

  const metrics: Metric[] = [
    {
      label: "Active learners",
      value: membershipRows.length,
      helper: "Current active class memberships",
      icon: Users,
      featured: true,
      href: "/progress",
      linkLabel: "Open learner monitoring",
    },
    {
      label: "Awaiting review",
      value: pendingTotal,
      helper: pendingTotal ? "Evaluated attempts waiting for your review" : "No evaluated attempt needs review",
      icon: ClipboardCheck,
      tone: pendingTotal ? "attention" : "neutral",
      href: "/evaluations",
      linkLabel: "Open the Evaluation Center",
    },
    {
      label: "Released results",
      value: releasedAttemptCount.count ?? 0,
      helper: "Instructor-final results released",
      icon: CheckCircle2,
      tone: "positive",
      href: "/reports?type=released_results",
      linkLabel: "Open released results report",
    },
    {
      label: "Active classes",
      value: classRows.filter((row) => row.status === "active").length,
      helper: "Classes currently open for teaching",
      icon: GraduationCap,
      href: "/classes",
      linkLabel: "Open active classes",
    },
  ];

  return (
    <DashboardLayout>
      <div className="mx-auto max-w-7xl space-y-7">
        <PageHeader title={`Welcome, ${profile.fullName}`} description="Review what needs attention, then move into your classes and evidence workflow without losing Instructor scope." actions={<><Button asChild variant="outline"><Link href="/analytics">Open analytics</Link></Button><Button asChild><Link href="/classes">Manage classes</Link></Button></>} />

        <MetricStrip metrics={metrics} ariaLabel="Instructor overview metrics" />

        {pendingTotal > 0 ? (
          <section className="flex flex-col gap-3 rounded-xl border border-amber-200 bg-amber-50 px-5 py-4 text-amber-950 shadow-xs sm:flex-row sm:items-center sm:justify-between">
            <div className="flex items-start gap-3">
              <span className="mt-0.5 flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-amber-100">
                <ClipboardCheck className="h-4 w-4" aria-hidden="true" />
              </span>
              <div>
                <h2 className="text-sm font-semibold">{pendingTotal} assessment{pendingTotal === 1 ? "" : "s"} waiting for review</h2>
                <p className="mt-1 text-xs leading-5 text-amber-900">Review ordered evidence before finalization and release.</p>
              </div>
            </div>
            <Button asChild variant="outline" size="sm" className="border-amber-300 bg-white text-amber-950 hover:bg-amber-100">
              <Link href="/evaluations">Open review queue <ArrowRight className="ml-1 h-4 w-4" aria-hidden="true" /></Link>
            </Button>
          </section>
        ) : null}

        <LearnerStatusBoard status={await learnerStatus} scopeLabel="your active classes" limit={4}
          allHref="/analytics?tab=learners" className="rounded-2xl border-border/75 shadow-card" />

        <InstructorOverviewPanels
          classes={classRows}
          assignments={assignments.data ?? []}
          reviewRows={reviewRows}
          pendingReviewTotal={pendingTotal}
          recentAttempts={attemptRows}
          learnerNames={learnerNames}
          revisions={revisions.data ?? []}
          upcoming={upcoming}
        />

      </div>
    </DashboardLayout>
  );
}
