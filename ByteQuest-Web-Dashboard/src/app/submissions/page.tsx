import Link from "next/link";
import { AlertTriangle, ClipboardList, Inbox, UserX } from "lucide-react";
import { PageHeader } from "@/components/dashboard/PageHeader";
import { QueryFilters } from "@/components/evaluations/QueryFilters";
import { DashboardLayout } from "@/components/layout/dashboard-layout";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { manilaDate, latenessDuration } from "@/lib/activities/dates";
import { requireStaffProfile } from "@/lib/auth/server";
import { homeworkStatusLabel } from "@/lib/evaluations/homework";
import { loadCurriculumOptions, namesFor } from "@/lib/evaluations/server";
import { evaluationsClient, type HomeworkStatus } from "@/lib/evaluations/types";
import { createServerSupabaseClient } from "@/lib/supabase/server";
import { cn } from "@/lib/utils";

export const dynamic = "force-dynamic";
const STATUSES: HomeworkStatus[] = ["submitted", "graded", "finalized", "released"];
const ROW_LIMIT = 500;

export default async function SubmissionsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  await requireStaffProfile(["instructor", "admin"]);
  const params = await searchParams;
  const value = (name: string) => { const raw = params[name]; return (Array.isArray(raw) ? raw[0] : raw) ?? ""; };
  const view = value("view") === "missing" ? "missing" : "all";
  const filter = { class: value("class"), learner: value("learner"), coc: value("coc"), mission: value("mission"), status: value("status"), late: value("late") === "1" };
  const client = evaluationsClient(await createServerSupabaseClient());
  const [assignmentResult, classResult, catalog] = await Promise.all([
    client.from("homework_assignments").select("id,class_id,title,status,deadline_at,coc_module_id,mission_code,max_score").eq("status", "published").order("created_at", { ascending: false }),
    client.from("classes").select("id,title,status").order("title"),
    loadCurriculumOptions(client).catch(() => null),
  ]);
  const failed = Boolean(assignmentResult.error || classResult.error);
  const classes = classResult.data ?? [];
  const classById = new Map(classes.map((c) => [c.id, c]));
  const cocById = new Map((catalog?.cocs ?? []).map((c) => [c.id, c]));
  const assignments = (assignmentResult.data ?? []).filter((h) =>
    (!filter.class || h.class_id === filter.class)
    && (!filter.coc || (h.coc_module_id && cocById.get(h.coc_module_id)?.coc_code === filter.coc))
    && (!filter.mission || h.mission_code === filter.mission));
  const assignmentById = new Map(assignments.map((h) => [h.id, h]));
  const ids = assignments.map((h) => h.id);
  const classIds = [...new Set(assignments.map((h) => h.class_id))];
  const [submissionResult, membershipResult] = await Promise.all([
    ids.length ? client.from("homework_submissions").select("id,assignment_id,learner_id,submitted_at,lateness_seconds,status,score").in("assignment_id", ids).order("submitted_at", { ascending: false }) : Promise.resolve({ data: [], error: null }),
    classIds.length ? client.from("class_memberships").select("class_id,learner_id,status").in("class_id", classIds).eq("status", "active") : Promise.resolve({ data: [], error: null }),
  ]);
  const loadFailed = failed || Boolean(submissionResult.error || membershipResult.error);
  const allSubmissions = submissionResult.data ?? [];
  const submissions = allSubmissions.filter((s) =>
    (!filter.learner || s.learner_id === filter.learner)
    && (!filter.status || s.status === filter.status)
    && (!filter.late || Number(s.lateness_seconds) > 0));
  const submitted = new Set(allSubmissions.map((s) => `${s.assignment_id}:${s.learner_id}`));
  const now = Date.now();
  const missing = assignments.flatMap((h) => (membershipResult.data ?? [])
    .filter((m) => m.class_id === h.class_id && !submitted.has(`${h.id}:${m.learner_id}`) && (!filter.learner || m.learner_id === filter.learner))
    .map((m) => ({ assignment: h, learnerId: m.learner_id, pastDue: Boolean(h.deadline_at && new Date(h.deadline_at).getTime() < now) })))
    .sort((a, b) => Number(b.pastDue) - Number(a.pastDue) || (a.assignment.deadline_at ?? "9999").localeCompare(b.assignment.deadline_at ?? "9999"));
  const people = await namesFor([...allSubmissions.map((s) => s.learner_id), ...(membershipResult.data ?? []).map((m) => m.learner_id)]).catch(() => new Map<string, { name: string; email: string }>());
  const learnerOptions = [...new Set((membershipResult.data ?? []).map((m) => m.learner_id).concat(allSubmissions.map((s) => s.learner_id)))]
    .map((learnerId) => ({ value: learnerId, label: people.get(learnerId)?.name ?? "Learner" }))
    .sort((a, b) => a.label.localeCompare(b.label));
  const late = allSubmissions.filter((s) => Number(s.lateness_seconds) > 0).length;
  const awaiting = allSubmissions.filter((s) => s.status === "submitted").length;
  const viewHref = (next: "all" | "missing") => {
    const query = new URLSearchParams();
    for (const [key, val] of Object.entries({ class: filter.class, learner: filter.learner, coc: filter.coc, mission: filter.mission })) if (val) query.set(key, val);
    if (next === "missing") query.set("view", "missing");
    return `/submissions${query.toString() ? `?${query.toString()}` : ""}`;
  };
  const competency = (h: { coc_module_id: string | null; mission_code: string | null }) => [
    h.coc_module_id ? cocById.get(h.coc_module_id)?.coc_code.toUpperCase() : null,
    h.mission_code ? h.mission_code.toUpperCase().replace("_", " ") : null,
  ].filter(Boolean) as string[];

  return (
    <DashboardLayout>
      <div className="mx-auto max-w-7xl space-y-6">
        <PageHeader
          title="Homework submissions"
          description="Every homework submission across your classes, organised by COC and mission, plus the work still missing. Grades move Evaluate → Finalize → Release in each assignment or the Evaluation Center."
          actions={<Button asChild variant="outline" className="min-h-11"><Link href="/evaluations?kind=homework">Evaluation Center</Link></Button>}
        />
        <nav aria-label="Submission views" className="flex flex-wrap gap-2">
          {(["all", "missing"] as const).map((item) => (
            <Link key={item} href={viewHref(item)} aria-current={view === item ? "page" : undefined}
              className={cn("inline-flex min-h-11 items-center gap-2 rounded-full border px-4 text-sm font-medium transition-colors duration-150 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
                view === item ? "border-primary bg-primary text-primary-foreground" : "border-border bg-card hover:border-primary/40")}>
              {item === "all" ? <Inbox className="h-4 w-4" aria-hidden="true" /> : <UserX className="h-4 w-4" aria-hidden="true" />}
              {item === "all" ? `All submissions (${allSubmissions.length})` : `Missing work (${missing.length})`}
            </Link>
          ))}
        </nav>
        <p className="text-sm text-muted-foreground">{awaiting} awaiting evaluation · {late} late · {missing.length} missing across {assignments.length} published assignment{assignments.length === 1 ? "" : "s"}.</p>
        <QueryFilters
          ariaLabel="Submission filters"
          keep={["view"]}
          selects={[
            { name: "class", label: "Class", allLabel: "All classes", value: filter.class, options: classes.map((c) => ({ value: c.id, label: c.status === "active" ? c.title : `${c.title} (archived)` })) },
            { name: "learner", label: "Learner", allLabel: "All learners", value: filter.learner, options: learnerOptions },
            { name: "coc", label: "COC", allLabel: "All COCs", value: filter.coc, options: (catalog?.cocs ?? []).map((c) => ({ value: c.coc_code, label: `${c.coc_code.toUpperCase()} · ${c.title}` })) },
            { name: "mission", label: "Mission", allLabel: "All missions", value: filter.mission, parentName: "coc",
              options: (catalog?.missions ?? []).map((m) => ({ value: m.mission_code, label: `${m.mission_code.toUpperCase().replace("_", " ")} · ${m.title}`, parent: cocById.get(m.coc_id)?.coc_code })) },
            ...(view === "all" ? [{ name: "status", label: "Status", allLabel: "Any status", value: filter.status, options: STATUSES.map((s) => ({ value: s, label: homeworkStatusLabel(s) })) }] : []),
          ]}
          toggles={view === "all" ? [{ name: "late", label: "Late only", checked: filter.late }] : []}
        />
        {loadFailed ? (
          <div role="alert" className="rounded-xl border border-destructive/40 bg-card px-5 py-12 text-center">
            <AlertTriangle className="mx-auto h-7 w-7 text-destructive" aria-hidden="true" />
            <p className="mt-3 text-sm font-semibold">Submissions could not be loaded.</p>
            <p className="mt-1 text-sm text-muted-foreground">Refresh the page to try again.</p>
          </div>
        ) : view === "all" ? (
          <section aria-label="Homework submissions" className="overflow-hidden rounded-xl border border-border bg-card">
            {submissions.length ? (
              <ul className="divide-y divide-border">
                {submissions.slice(0, ROW_LIMIT).map((s) => {
                  const h = assignmentById.get(s.assignment_id)!;
                  return (
                    <li key={s.id}>
                      <Link href={`/classes/${h.class_id}/assignments/${h.id}?submission=${s.id}`} className="grid gap-3 px-4 py-4 transition-colors hover:bg-muted/35 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring md:grid-cols-[minmax(0,1fr)_minmax(0,1.2fr)_minmax(0,0.8fr)_auto] md:items-center">
                        <div className="min-w-0"><p className="truncate text-sm font-medium">{people.get(s.learner_id)?.name ?? "Learner"}</p><p className="truncate text-xs text-muted-foreground">{classById.get(h.class_id)?.title ?? "Class"}</p></div>
                        <div className="min-w-0"><p className="break-words text-sm">{h.title}</p><div className="mt-1 flex flex-wrap gap-1.5">{competency(h).map((label) => <Badge key={label} variant="outline">{label}</Badge>)}</div></div>
                        <div className="text-xs"><p>{manilaDate(s.submitted_at)}</p><p className={Number(s.lateness_seconds) > 0 ? "font-medium text-amber-800" : "text-muted-foreground"}>{Number(s.lateness_seconds) > 0 ? `Late by ${latenessDuration(Number(s.lateness_seconds))}` : "On time"}</p></div>
                        <div className="flex flex-wrap items-center gap-2"><Badge variant={s.status === "released" ? "secondary" : s.status === "submitted" ? "outline" : "default"}>{homeworkStatusLabel(s.status)}</Badge><span className="text-sm tabular-nums">{s.score === null ? "—" : `${Number(s.score)} / ${Number(h.max_score)}`}</span></div>
                      </Link>
                    </li>
                  );
                })}
              </ul>
            ) : (
              <div className="px-5 py-14 text-center"><ClipboardList className="mx-auto h-7 w-7 text-muted-foreground" aria-hidden="true" /><p className="mt-3 text-sm font-semibold">No submissions match these filters.</p><p className="mt-1 text-sm text-muted-foreground">Learner submissions appear here as soon as they are submitted from the app.</p></div>
            )}
            {submissions.length > ROW_LIMIT ? <p className="border-t border-border px-4 py-3 text-sm text-muted-foreground">Showing the newest {ROW_LIMIT} of {submissions.length}. Filter by class or learner to narrow the list.</p> : null}
          </section>
        ) : (
          <section aria-label="Missing work" className="overflow-hidden rounded-xl border border-border bg-card">
            {missing.length ? (
              <ul className="divide-y divide-border">
                {missing.slice(0, ROW_LIMIT).map(({ assignment: h, learnerId, pastDue }) => (
                  <li key={`${h.id}:${learnerId}`} className="grid gap-3 px-4 py-4 md:grid-cols-[minmax(0,1fr)_minmax(0,1.2fr)_minmax(0,0.8fr)_auto] md:items-center">
                    <div className="min-w-0"><p className="truncate text-sm font-medium">{people.get(learnerId)?.name ?? "Learner"}</p><p className="truncate text-xs text-muted-foreground">{classById.get(h.class_id)?.title ?? "Class"}</p></div>
                    <div className="min-w-0"><p className="break-words text-sm">{h.title}</p><div className="mt-1 flex flex-wrap gap-1.5">{competency(h).map((label) => <Badge key={label} variant="outline">{label}</Badge>)}</div></div>
                    <p className="text-xs text-muted-foreground">Deadline: {manilaDate(h.deadline_at)}</p>
                    <div className="flex items-center gap-2"><Badge variant="outline" className={pastDue ? "border-amber-300 text-amber-900" : undefined}>{!h.deadline_at ? "No deadline" : pastDue ? "Past deadline" : "Upcoming"}</Badge><Button asChild variant="ghost" className="min-h-11"><Link href={`/classes/${h.class_id}/assignments/${h.id}`}>Open</Link></Button></div>
                  </li>
                ))}
              </ul>
            ) : (
              <div className="px-5 py-14 text-center"><UserX className="mx-auto h-7 w-7 text-muted-foreground" aria-hidden="true" /><p className="mt-3 text-sm font-semibold">No missing work.</p><p className="mt-1 text-sm text-muted-foreground">Every enrolled learner has submitted each published assignment in this view.</p></div>
            )}
            {missing.length > ROW_LIMIT ? <p className="border-t border-border px-4 py-3 text-sm text-muted-foreground">Showing {ROW_LIMIT} of {missing.length}. Filter by class or COC to narrow the list.</p> : null}
          </section>
        )}
        {(assignmentResult.data ?? []).length === 0 && !loadFailed ? <p className="text-sm text-muted-foreground">No published homework yet. Create and publish an assignment from a class&apos;s Assignments tab.</p> : null}
      </div>
    </DashboardLayout>
  );
}
