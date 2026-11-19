import Link from "next/link";
import { Activity, CheckCircle2, ClipboardCheck, Clock3, Scale } from "lucide-react";
import { DashboardLayout } from "@/components/layout/dashboard-layout";
import { MetricStrip, type Metric } from "@/components/dashboard/MetricStrip";
import { PageHeader } from "@/components/dashboard/PageHeader";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { requireStaffProfile } from "@/lib/auth/server";
import { createServerSupabaseClient } from "@/lib/supabase/server";
import { cn } from "@/lib/utils";

export const dynamic = "force-dynamic";

// Objective 4 stages for technical attempts.
const STAGES = [
  { key: "all", label: "All", statuses: null },
  { key: "evaluate", label: "Evaluate", statuses: ["evaluated"] },
  { key: "finalize", label: "Finalize", statuses: ["under_review"] },
  { key: "release", label: "Release", statuses: ["finalized"] },
  { key: "released", label: "Released", statuses: ["released"] },
  { key: "active", label: "In progress", statuses: ["in_progress", "submitted"] },
] as const;
const STATUS_LABEL: Record<string, string> = {
  in_progress: "In progress", submitted: "Submitted", evaluated: "Evaluated (automatic)",
  under_review: "Evaluation recorded", finalized: "Finalized", released: "Released",
};

function formatTimestamp(value: string | null) {
  if (!value) return "Not submitted";
  return new Intl.DateTimeFormat("en-PH", {
    dateStyle: "medium",
    timeStyle: "short",
    timeZone: "Asia/Manila",
  }).format(new Date(value));
}

export default async function AttemptsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  await requireStaffProfile(["instructor", "admin"]);
  const params = await searchParams;
  const requested = Array.isArray(params.stage) ? params.stage[0] : params.stage;
  const stage = STAGES.find((item) => item.key === requested) ?? STAGES[0];
  const supabase = await createServerSupabaseClient();
  const { data: attempts, error } = await supabase
    .from("attempts")
    .select("id,learner_id,class_id,assignment_id,status,started_at,submitted_at,released_at")
    .order("started_at", { ascending: false });

  const all = attempts ?? [];
  const count = (statuses: readonly string[] | null) => statuses ? all.filter((row) => statuses.includes(row.status)).length : all.length;
  const rows = stage.statuses ? all.filter((row) => (stage.statuses as readonly string[]).includes(row.status)) : all;
  const learnerIds = [...new Set(rows.map((row) => row.learner_id))];
  const classIds = [...new Set(rows.map((row) => row.class_id))];
  const assignmentIds = [...new Set(rows.map((row) => row.assignment_id))];
  const [profiles, classes, assignments] = await Promise.all([
    learnerIds.length
      ? supabase.from("profiles").select("user_id,full_name,email").in("user_id", learnerIds)
      : Promise.resolve({ data: [] }),
    classIds.length
      ? supabase.from("classes").select("id,title").in("id", classIds)
      : Promise.resolve({ data: [] }),
    assignmentIds.length
      ? supabase.from("assignments").select("id,title,assignment_type").in("id", assignmentIds)
      : Promise.resolve({ data: [] }),
  ]);
  const profileById = new Map((profiles.data ?? []).map((row) => [row.user_id, row]));
  const classById = new Map((classes.data ?? []).map((row) => [row.id, row]));
  const assignmentById = new Map((assignments.data ?? []).map((row) => [row.id, row]));
  const pendingCount = count(["evaluated", "under_review", "finalized"]);
  const releasedCount = count(["released"]);
  const activeCount = count(["in_progress", "submitted"]);
  const metrics: Metric[] = [
    { label: "Awaiting a decision", value: pendingCount, helper: pendingCount ? "Evaluate, finalize or release in the Evaluation Center" : "Review queue is clear", icon: ClipboardCheck, tone: pendingCount ? "attention" : "neutral", href: "/evaluations", linkLabel: "Open the Evaluation Center", featured: pendingCount > 0 },
    { label: "Released results", value: releasedCount, helper: "Instructor-final results visible to learners", icon: CheckCircle2, tone: "positive", href: "/attempts?stage=released", linkLabel: "View released attempts" },
    { label: "Active attempts", value: activeCount, helper: "Learner work not yet evaluated", icon: Activity, tone: "informational", href: "/attempts?stage=active", linkLabel: "View active attempts" },
    { label: "Total attempts", value: all.length, helper: "Authoritative attempts in your scope", icon: Clock3, tone: "neutral", href: "/attempts", linkLabel: "View all attempts" },
  ];

  return (
    <DashboardLayout>
      <div className="mx-auto max-w-7xl space-y-7">
        <PageHeader
          title="Attempt review"
          description="Review chronological evidence and criterion-level evaluation for learners in your classes. Each result moves Evaluate → Finalize → Release."
          actions={<Button asChild className="min-h-11"><Link href="/evaluations"><Scale className="mr-2 h-4 w-4" aria-hidden="true" />Evaluation Center</Link></Button>}
        />
        <MetricStrip metrics={metrics} ariaLabel="Attempt review metrics" />
        <nav aria-label="Filter attempts by stage" className="flex flex-wrap gap-2">
          {STAGES.map((item) => {
            const active = item.key === stage.key;
            return (
              <Link
                key={item.key}
                href={item.key === "all" ? "/attempts" : `/attempts?stage=${item.key}`}
                aria-current={active ? "page" : undefined}
                className={cn(
                  "inline-flex min-h-11 items-center gap-2 rounded-full border px-4 text-sm font-medium transition-colors duration-150 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
                  active ? "border-primary bg-primary text-primary-foreground" : "border-border bg-card hover:border-primary/40",
                )}
              >
                {item.label}
                <span className={cn("rounded-full px-2 text-xs tabular-nums", active ? "bg-primary-foreground/20" : "bg-muted")}>{count(item.statuses)}</span>
              </Link>
            );
          })}
        </nav>
        <section id="attempt-list" className="overflow-hidden rounded-xl border border-border bg-card">
          {error ? (
            <p role="alert" className="px-5 py-12 text-center text-sm text-destructive">Attempts could not be loaded. Refresh to try again.</p>
          ) : rows.length ? (
            <div className="divide-y divide-border">
              {rows.map((attempt) => {
                const learner = profileById.get(attempt.learner_id);
                const classroom = classById.get(attempt.class_id);
                const assignment = assignmentById.get(attempt.assignment_id);
                const needsReview = ["evaluated", "under_review", "finalized"].includes(attempt.status);
                return (
                  <Link key={attempt.id} href={`/attempts/${attempt.id}`} className="grid gap-3 px-5 py-4 transition-colors hover:bg-muted/35 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring md:grid-cols-[minmax(0,1fr)_minmax(0,0.8fr)_auto] md:items-center">
                    <div className="min-w-0"><p className="truncate text-sm font-medium">{learner?.full_name ?? "Learner"}</p><p className="mt-0.5 truncate text-xs text-muted-foreground">{learner?.email ?? "Email unavailable"} · {classroom?.title ?? "Class"}</p></div>
                    <div className="min-w-0"><p className="truncate text-sm">{assignment?.title ?? "Versioned assignment"}</p><p className="mt-0.5 text-xs text-muted-foreground">{formatTimestamp(attempt.submitted_at)}</p></div>
                    <Badge variant={needsReview ? "default" : attempt.status === "released" ? "secondary" : "outline"}>{STATUS_LABEL[attempt.status] ?? attempt.status.replaceAll("_", " ")}</Badge>
                  </Link>
                );
              })}
            </div>
          ) : (
            <div className="px-5 py-16 text-center"><ClipboardCheck className="mx-auto h-7 w-7 text-muted-foreground" aria-hidden="true" /><p className="mt-3 text-sm font-medium">{stage.key === "all" ? "No authoritative attempts yet." : `No attempts in ${stage.label}.`}</p><p className="mt-1 text-sm text-muted-foreground">{stage.key === "all" ? "The queue will populate after approved content is assigned and submitted from mobile." : "Choose another stage or open the Evaluation Center."}</p></div>
          )}
        </section>
      </div>
    </DashboardLayout>
  );
}
