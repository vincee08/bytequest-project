import { Activity, GraduationCap, Users } from "lucide-react";
import { DashboardLayout } from "@/components/layout/dashboard-layout";
import { MetricStrip } from "@/components/dashboard/MetricStrip";
import { PageHeader } from "@/components/dashboard/PageHeader";
import { DirectorySearchControls } from "@/components/learners/DirectorySearchControls";
import { DirectoryError, LearnerDirectoryTable } from "@/components/learners/LearnerDirectoryTable";
import { requireStaffProfile } from "@/lib/auth/server";
import { getAdminGovernanceData } from "@/lib/admin/governance";
import { learnerSearchHref, learnerSortDefaults, learnerStatusFilters, learnerStatusLabels, parseLearnerSearchParams } from "@/lib/learners/search";
import { runLearnerSearch } from "@/lib/learners/search-server";
import { createServerSupabaseClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function AdminLearnersPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  await requireStaffProfile(["admin"]);
  const filters = parseLearnerSearchParams(await searchParams);
  const [{ profiles, classes, memberships }, search] = await Promise.all([
    getAdminGovernanceData(),
    createServerSupabaseClient().then((client) => runLearnerSearch(client, filters)),
  ]);
  const learners = profiles.filter((profile) => profile.role === "learner");
  const activeMemberships = memberships.filter((row) => row.status === "active");
  const activeClasses = classes.filter((row) => row.status === "active").sort((a, b) => a.title.localeCompare(b.title));
  const inactiveLearners = learners.filter((row) => row.status !== "active").length;
  const hidden: Record<string, string> = {};
  if (filters.sort !== "name") hidden.sort = filters.sort;
  if (filters.direction !== learnerSortDefaults[filters.sort]) hidden.dir = filters.direction;

  return <DashboardLayout><div className="mx-auto max-w-7xl space-y-7">
    <PageHeader title="Learners" description="Search learner accounts by name, email, student ID or class. Review account state and enrollment without entering Instructor assessment workflows." />
    <MetricStrip ariaLabel="Learner governance metrics" metrics={[
      { label: "Active learners", value: learners.filter((row) => row.status === "active").length, helper: "Learner accounts currently active", icon: Users, featured: true, href: "/learners?status=active", linkLabel: "Show active learners" },
      { label: "Enrolled learners", value: new Set(activeMemberships.map((row) => row.learner_id)).size, helper: "Learners with at least one active class membership", icon: GraduationCap, tone: "positive" },
      { label: "Active classes", value: activeClasses.length, helper: "Available class contexts", icon: GraduationCap },
      { label: "Needs account review", value: inactiveLearners, helper: "Deactivated or otherwise inactive learner accounts", icon: Activity, tone: inactiveLearners ? "attention" : "neutral", href: "/learners?status=inactive", linkLabel: "Review inactive learner accounts" },
    ]} />
    <DirectorySearchControls
      action="/learners"
      label="Search learners"
      placeholder="Name, email, student ID or class"
      query={filters.q}
      hidden={hidden}
      clearHref="/learners"
      filtered={Boolean(filters.q || filters.classId || filters.status !== "all")}
      selects={[
        { name: "class", label: "Class", value: filters.classId ?? "all", options: [{ value: "all", label: "All classes" }, ...activeClasses.map((row) => ({ value: row.id, label: row.title }))] },
        { name: "status", label: "Account status", value: filters.status, options: learnerStatusFilters.map((value) => ({ value, label: learnerStatusLabels[value] })) },
      ]}
    />
    {search.data ? (
      <LearnerDirectoryTable
        basePath="/learners"
        filters={filters}
        result={search.data}
        rowHref={(row) => `/users/${row.user_id}/edit`}
        showCreated
        emptyTitle="No learner accounts yet."
        emptyText="Learners appear here after they sign up in the ByteQuest app."
      />
    ) : <DirectoryError message={search.error} retryHref={learnerSearchHref("/learners", filters, {})} />}
  </div></DashboardLayout>;
}
