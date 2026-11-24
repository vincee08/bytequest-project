import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft, BookOpenCheck, FileSpreadsheet, Files, ShieldCheck, Users } from "lucide-react";
import {
  ArchiveClassForm,
  AssignmentAccessPolicyForm,
  AssignActivityForm,
  CloseAssignmentForm,
  DeactivateLearnerAccountForm,
  DeactivateMembershipForm,
  EnrollLearnerForm,
  GrantBypassForm,
} from "@/components/classes/ClassManagementForms";
import {
  LearningResourceManager,
  type LearningResourceItem,
} from "@/components/classes/LearningResourceManager";
import { DashboardLayout } from "@/components/layout/dashboard-layout";
import { MetricStrip, type Metric } from "@/components/dashboard/MetricStrip";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { requireStaffProfile } from "@/lib/auth/server";
import { createServerSupabaseClient } from "@/lib/supabase/server";
import { activitiesClient } from "@/lib/activities/types";
import { HomeworkManager } from "@/components/classes/HomeworkManager";
import { QuizDeadlineControls } from "@/components/quizzes/QuizDeadlineControls";
import { PendingRosterEntries } from "@/components/roster/PendingRosterEntries";
import { classQuizDeadlineRows, classTabHref, resolveClassTab } from "@/components/dashboard/class-workspace";
import { rosterClient } from "@/lib/roster/server";
import { learnerDisplayName } from "@/lib/learners/identity";
import { deliveryKindLabel } from "@/lib/activities/assignment-options";

export const dynamic = "force-dynamic";

export default async function ClassDetailPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  await requireStaffProfile(["instructor"]);
  const { id } = await params;
  const query = await searchParams;
  const defaultTab = resolveClassTab(query.tab);
  const supabase = await createServerSupabaseClient();

  const { data: classroom } = await supabase
    .from("classes")
    .select("id,title,class_code,status,created_at,archive_reason")
    .eq("id", id)
    .maybeSingle();

  if (!classroom) notFound();

  const [homeworkResult, quizAssignmentResult, rosterResult] = await Promise.all([
    activitiesClient(supabase).from('homework_assignments').select('*').eq('class_id', id).order('created_at', { ascending: false }),
    supabase.from('quiz_assignments').select('id,due_at,status,quiz_versions(status,quizzes(title))').eq('class_id', id).eq('status', 'active'),
    rosterClient(supabase).from('class_roster_entries').select('id,email_normalized,student_id,last_name,first_name,course_section,status,created_at,claimed_user_id,claimed_at').eq('class_id', id).in('status', ['pending', 'enrolled']).order('created_at', { ascending: false }),
  ]);
  if (homeworkResult.error || quizAssignmentResult.error || rosterResult.error) throw new Error('Class activities could not be loaded.');
  const pendingRoster = (rosterResult.data ?? []).filter((entry) => entry.status === 'pending').map((entry) => ({
    id: entry.id, name: `${entry.last_name}, ${entry.first_name}`, email: entry.email_normalized,
    studentId: entry.student_id, courseSection: entry.course_section, createdAt: entry.created_at,
  }));
  // A claimed entry and the membership it created share (almost) the same timestamp.
  const rosterClaimedAt = new Map((rosterResult.data ?? []).filter((entry) => entry.status === 'enrolled' && entry.claimed_user_id && entry.claimed_at)
    .map((entry) => [entry.claimed_user_id as string, new Date(entry.claimed_at as string).getTime()]));
  const joinedViaRoster = (learnerId: string, enrolledAt: string) => {
    const claimedAt = rosterClaimedAt.get(learnerId);
    return claimedAt !== undefined && Math.abs(new Date(enrolledAt).getTime() - claimedAt) < 5 * 60 * 1000;
  };

  const [membershipResult, assignmentResult, activityResult, rubricResult, moduleResult, bypassResult, resourceResult, linkResult] =
    await Promise.all([
      supabase
        .from("class_memberships")
        .select("id,learner_id,status,enrolled_at,deactivated_at,deactivation_reason")
        .eq("class_id", id)
        .order("enrolled_at", { ascending: false }),
      supabase
        .from("assignments")
        .select("id,title,assignment_type,status,created_at,due_at,activity_version_id,attempts_allowed,retry_enabled,retry_after_seconds,prerequisite_assignment_id")
        .eq("class_id", id)
        .order("created_at", { ascending: false }),
      supabase
        .from("activity_versions")
        .select("id,title,delivery_mode,module_version_id")
        .eq("status", "published")
        .order("title"),
      supabase
        .from("rubric_versions")
        .select("id,title,activity_version_id,version_number")
        .eq("status", "approved")
        .order("title"),
      supabase
        .from("module_versions")
        .select("id,title")
        .eq("status", "published")
        .order("title"),
      supabase
        .from("coc_bypasses")
        .select("id,learner_id,module_version_id,reason,granted_at,revoked_at")
        .eq("class_id", id)
        .order("granted_at", { ascending: false }),
      supabase
        .from("learning_resources")
        .select("id,title,description,mime_type,size_bytes,status,created_at,deletion_reason")
        .eq("class_id", id)
        .order("created_at", { ascending: false }),
      // Simulation vs form-based assessment packages (spec WS2 labels).
      supabase.from("activity_curriculum_links").select("activity_version_id,delivery_kind"),
    ]);

  const memberships = membershipResult.data ?? [];
  const learnerIds = [...new Set(memberships.map((membership) => membership.learner_id))];
  const { data: profiles } = learnerIds.length
    ? await supabase
        .from("profiles")
        .select("user_id,full_name,email,status")
        .in("user_id", learnerIds)
    : { data: [] };
  const profileById = new Map((profiles ?? []).map((profile) => [profile.user_id, profile]));
  const activeLearners = memberships
    .filter((membership) => membership.status === "active")
    .map((membership) => ({
      id: membership.learner_id,
      name: learnerDisplayName(profileById.get(membership.learner_id)),
    }));
  const activityById = new Map(
    (activityResult.data ?? []).map((activity) => [activity.id, activity.title]),
  );
  const deliveryKindByActivity = new Map(
    (linkResult.data ?? []).map((link) => [link.activity_version_id, link.delivery_kind]),
  );
  const moduleById = new Map(
    (moduleResult.data ?? []).map((module) => [module.id, module.title]),
  );
  const activeAssignmentCount = (assignmentResult.data ?? []).filter((row) => row.status === "active").length;
  const activeBypassCount = (bypassResult.data ?? []).filter((row) => !row.revoked_at).length;
  const activeResourceCount = (resourceResult.data ?? []).filter((row) => row.status === "active").length;
  const quizDeadlineRows = classQuizDeadlineRows(quizAssignmentResult.data ?? [], classroom.title);
  const classMetrics: Metric[] = [
    { label: "Homework", value: (homeworkResult.data ?? []).filter(h => h.status === 'published').length, helper: "Published homework assignments", icon: BookOpenCheck, href: classTabHref(id, "assignments"), linkLabel: "View class homework" },
    { label: "Assigned quizzes", value: quizDeadlineRows.length, helper: "Separate supplementary quizzes", icon: BookOpenCheck, href: classTabHref(id, "assignments"), linkLabel: "View assigned quizzes" },
    { label: "Active learners", value: activeLearners.length, helper: "Current active memberships", icon: Users, tone: "informational", href: classTabHref(id, "learners"), linkLabel: "View class learners", featured: true },
    { label: "Technical assignments", value: activeAssignmentCount, helper: "COC practice and assessment activities", icon: BookOpenCheck, href: classTabHref(id, "assignments"), linkLabel: "View technical assignments" },
    { label: "Access bypasses", value: activeBypassCount, helper: "Practice access grants still active", icon: ShieldCheck, tone: "attention", href: classTabHref(id, "bypasses"), linkLabel: "View access bypasses" },
    { label: "Active resources", value: activeResourceCount, helper: "Private resources available to this class", icon: Files, tone: "positive", href: classTabHref(id, "resources"), linkLabel: "View class resources" },
  ];

  return (
    <DashboardLayout>
      <div className="mx-auto max-w-7xl space-y-7">
        <div className="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
          <div>
            <Button asChild variant="ghost" size="sm" className="-ml-3 mb-2">
              <Link href="/classes">
                <ArrowLeft className="mr-2 h-4 w-4" aria-hidden="true" />
                All classes
              </Link>
            </Button>
            <div className="flex flex-wrap items-center gap-3">
              <h1 className="text-2xl font-bold tracking-tight text-foreground">{classroom.title}</h1>
              <Badge variant={classroom.status === "active" ? "secondary" : "outline"}>
                {classroom.status}
              </Badge>
            </div>
            <p className="mt-1 text-sm text-muted-foreground">
              {classroom.class_code || "No class code"} · Instructor-scoped workspace
            </p>
          </div>
        </div>

        <MetricStrip metrics={classMetrics} ariaLabel="Class detail metrics" />

        {/* Keyed by the requested tab so a ?tab= link on this page switches the open tab. */}
        <Tabs key={defaultTab} defaultValue={defaultTab} className="space-y-5">
          <TabsList className="h-auto flex-wrap justify-start">
            <TabsTrigger value="learners">Learners</TabsTrigger>
            <TabsTrigger value="assignments">Assignments</TabsTrigger>
            <TabsTrigger value="resources">Resources</TabsTrigger>
            <TabsTrigger value="bypasses">Access bypass</TabsTrigger>
            <TabsTrigger value="settings">Class settings</TabsTrigger>
          </TabsList>

          <TabsContent id="learners" value="learners" className="space-y-5">
            {classroom.status === "active" ? (
              <div className="grid gap-5 lg:grid-cols-[minmax(0,1.4fr)_minmax(0,1fr)]">
                <section className="rounded-xl border border-border bg-card p-5">
                  <h2 className="font-semibold">Enroll a learner</h2>
                  <p className="mb-4 mt-1 text-sm text-muted-foreground">Find a registered learner by name or email, then select their profile. Previous enrollment records are retained.</p>
                  <EnrollLearnerForm classId={id} />
                </section>
                <section className="flex flex-col rounded-xl border border-border bg-card p-5">
                  <h2 className="font-semibold">Import a roster from Excel</h2>
                  <p className="mb-4 mt-1 text-sm text-muted-foreground">Upload a class list (.xlsx or .xls). You review a preview before anything changes; new emails enroll automatically after the learner signs up.</p>
                  <Button asChild variant="outline" className="mt-auto min-h-11 self-start">
                    <Link href={`/classes/${id}/import`}><FileSpreadsheet className="mr-2 h-4 w-4" aria-hidden="true" />Import roster</Link>
                  </Button>
                </section>
              </div>
            ) : null}
            <section className="overflow-hidden rounded-xl border border-border bg-card" aria-labelledby="pending-roster-heading">
              <div className="flex flex-col gap-1 border-b border-border px-5 py-4 sm:flex-row sm:items-center sm:justify-between">
                <h2 id="pending-roster-heading" className="font-semibold">Pending roster <span className="tabular-nums text-muted-foreground">({pendingRoster.length})</span></h2>
                <p className="text-xs text-muted-foreground">Enroll automatically when the learner signs up with the same email. Sign-up email is not verified yet, so review new joiners.</p>
              </div>
              <PendingRosterEntries classId={id} entries={pendingRoster} canManage={classroom.status === "active"} />
            </section>
            <section className="overflow-hidden rounded-xl border border-border bg-card">
              <div className="border-b border-border px-5 py-4"><h2 className="font-semibold">Membership history</h2></div>
              {memberships.length ? <div className="divide-y divide-border">{memberships.map((membership) => {
                const learner = profileById.get(membership.learner_id);
                return <div key={membership.id} className="flex flex-col gap-3 px-5 py-4 sm:flex-row sm:items-start sm:justify-between"><div className="min-w-0 [overflow-wrap:anywhere]"><p className="text-sm font-medium">{learnerDisplayName(learner)}</p><p className="mt-0.5 text-xs text-muted-foreground">{learner?.email ?? "Email unavailable"} · enrolled {new Intl.DateTimeFormat("en-PH", { dateStyle: "medium", timeZone: "Asia/Manila" }).format(new Date(membership.enrolled_at))}</p>{membership.deactivation_reason ? <p className="mt-1 text-xs text-muted-foreground">Reason: {membership.deactivation_reason}</p> : null}</div><div className="flex flex-col items-end gap-2"><div className="flex flex-wrap justify-end gap-1.5">{joinedViaRoster(membership.learner_id, membership.enrolled_at) ? <Badge variant="default">Joined via roster</Badge> : null}<Badge variant={membership.status === "active" ? "secondary" : "outline"}>{membership.status}</Badge></div>{membership.status === "active" && classroom.status === "active" ? <div className="flex flex-col items-end gap-2"><DeactivateMembershipForm membershipId={membership.id} learnerName={learnerDisplayName(learner)} /><DeactivateLearnerAccountForm learnerId={membership.learner_id} learnerName={learnerDisplayName(learner)} /></div> : null}</div></div>;
              })}</div> : <p className="px-5 py-10 text-center text-sm text-muted-foreground">No learner has been enrolled.</p>}
            </section>
          </TabsContent>

          <TabsContent id="assignments" value="assignments" className="space-y-5">
            <HomeworkManager classId={id} classTitle={classroom.title} active={classroom.status === 'active'} homework={homeworkResult.data ?? []} />
            <section className="space-y-4 rounded-xl border border-border bg-card p-5"><h2 className="font-semibold">Assigned quizzes</h2><p className="text-sm text-muted-foreground">Supplementary quizzes have their own attempts and deadlines.</p>{quizDeadlineRows.length ? <ul className="space-y-4">{quizDeadlineRows.map((row) => <li key={row.assignment.id} className="space-y-2"><h3 className="break-words text-sm font-semibold">{row.quizTitle}</h3><QuizDeadlineControls quizTitle={row.quizTitle} serverNow={new Date().toISOString()} assignments={[row.assignment]} /></li>)}</ul> : <p className="rounded-lg border border-dashed border-border px-4 py-6 text-center text-sm text-muted-foreground">No published quiz is assigned to this class yet.</p>}<Button asChild variant="outline" className="min-h-11"><Link href="/quizzes">Manage quizzes</Link></Button></section>
            {classroom.status === "active" ? <section className="rounded-xl border border-border bg-card p-5"><h2 className="font-semibold">Assign published content</h2><p className="mb-4 mt-1 text-sm text-muted-foreground">Assessment assignment remains gated by an approved source and matching approved rubric.</p><AssignActivityForm classId={id} activities={(activityResult.data ?? []).map((row) => ({ id: row.id, title: row.title, deliveryMode: row.delivery_mode, deliveryKind: deliveryKindByActivity.get(row.id) ?? null }))} rubrics={(rubricResult.data ?? []).map((row) => ({ id: row.id, title: row.title, activityVersionId: row.activity_version_id, versionNumber: row.version_number }))} /></section> : null}
            <section className="overflow-hidden rounded-xl border border-border bg-card">
              <div className="border-b border-border px-5 py-4">
                <h2 className="font-semibold">Technical assignment history</h2>
                <p className="mt-1 text-xs text-muted-foreground">
                  Retry limits and prerequisites are configurable institutional rules, not TESDA numeric requirements.
                </p>
              </div>
              {assignmentResult.data?.length ? (
                <div className="divide-y divide-border">
                  {assignmentResult.data.map((assignment) => {
                    const prerequisiteTitle = assignment.prerequisite_assignment_id
                      ? assignmentResult.data?.find((row) => row.id === assignment.prerequisite_assignment_id)?.title
                      : null;
                    const otherAssignments = (assignmentResult.data ?? [])
                      .filter((row) => row.id !== assignment.id && row.status === "active")
                      .map((row) => ({ id: row.id, title: row.title }));
                    const kind = deliveryKindLabel(deliveryKindByActivity.get(assignment.activity_version_id));
                    return (
                      <div key={assignment.id} className="px-5 py-4">
                        <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
                          <div className="min-w-0">
                            <p className="text-sm font-semibold">{assignment.title}</p>
                            <p className="mt-1 text-xs text-muted-foreground">
                              {activityById.get(assignment.activity_version_id) ?? "Versioned activity"} · {assignment.assignment_type}
                            </p>
                            {kind ? <Badge variant="outline" className="mt-2">{kind}</Badge> : null}
                            <div className="mt-3 flex flex-wrap gap-2 text-xs text-muted-foreground">
                              <span className="rounded-md border border-border px-2 py-1">
                                {assignment.attempts_allowed === null
                                  ? "No attempt limit configured"
                                  : `${assignment.attempts_allowed} attempt limit`}
                              </span>
                              <span className="rounded-md border border-border px-2 py-1">
                                {assignment.retry_enabled ? "Retry enabled" : "Retry disabled"}
                              </span>
                              {assignment.retry_after_seconds !== null ? (
                                <span className="rounded-md border border-border px-2 py-1">
                                  Retry after {Math.ceil(assignment.retry_after_seconds / 60)} min
                                </span>
                              ) : null}
                              {prerequisiteTitle ? (
                                <span className="rounded-md border border-border px-2 py-1">
                                  Requires: {prerequisiteTitle}
                                </span>
                              ) : null}
                            </div>
                          </div>
                          <div className="flex flex-wrap items-center gap-2">
                            <Badge variant={assignment.status === "active" ? "secondary" : "outline"}>
                              {assignment.status}
                            </Badge>
                            {assignment.status === "active" ? (
                              <>
                                <AssignmentAccessPolicyForm
                                  assignment={{
                                    id: assignment.id,
                                    attemptsAllowed: assignment.attempts_allowed,
                                    retryEnabled: assignment.retry_enabled,
                                    retryAfterSeconds: assignment.retry_after_seconds,
                                    prerequisiteAssignmentId: assignment.prerequisite_assignment_id,
                                  }}
                                  prerequisiteOptions={otherAssignments}
                                />
                                <CloseAssignmentForm assignmentId={assignment.id} />
                              </>
                            ) : null}
                          </div>
                        </div>
                      </div>
                    );
                  })}
                </div>
              ) : (
                <p className="px-5 py-10 text-center text-sm text-muted-foreground">No activity has been assigned.</p>
              )}
            </section>
          </TabsContent>

          <TabsContent id="resources" value="resources">
            <LearningResourceManager
              classId={id}
              classActive={classroom.status === "active"}
              resources={(resourceResult.data ?? []) as LearningResourceItem[]}
            />
          </TabsContent>

          <TabsContent id="bypasses" value="bypasses" className="space-y-5">
            <section className="rounded-xl border border-border bg-card p-5"><h2 className="font-semibold">Grant access-only bypass</h2><p className="mb-4 mt-1 text-sm leading-relaxed text-muted-foreground">A bypass unlocks access only. It never marks competency, assigns a score, or grants XP.</p><GrantBypassForm classId={id} learners={activeLearners} modules={moduleResult.data ?? []} /></section>
            <section className="overflow-hidden rounded-xl border border-border bg-card"><div className="border-b border-border px-5 py-4"><h2 className="font-semibold">Bypass audit trail</h2></div>{bypassResult.data?.length ? <div className="divide-y divide-border">{bypassResult.data.map((bypass) => <div key={bypass.id} className="px-5 py-4"><div className="flex items-start justify-between gap-4"><div><p className="text-sm font-medium">{learnerDisplayName(profileById.get(bypass.learner_id))} ·{moduleById.get(bypass.module_version_id) ?? "Module version"}</p><p className="mt-1 text-xs text-muted-foreground">{bypass.reason}</p></div><Badge variant={bypass.revoked_at ? "outline" : "secondary"}>{bypass.revoked_at ? "revoked" : "active"}</Badge></div></div>)}</div> : <p className="px-5 py-10 text-center text-sm text-muted-foreground">No access bypass has been granted.</p>}</section>
          </TabsContent>

          <TabsContent value="settings">
            <section className="rounded-xl border border-destructive/30 bg-card p-5"><h2 className="font-semibold">Archive class</h2><p className="mb-4 mt-1 max-w-2xl text-sm leading-relaxed text-muted-foreground">Archiving stops new scoped operations while retaining memberships, assignments, attempts, and audit history.</p>{classroom.status === "active" ? <ArchiveClassForm classId={id} /> : <p className="text-sm text-muted-foreground">Archived: {classroom.archive_reason}</p>}</section>
          </TabsContent>
        </Tabs>
      </div>
    </DashboardLayout>
  );
}
