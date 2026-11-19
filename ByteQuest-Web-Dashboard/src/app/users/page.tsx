import Link from "next/link";
import { CircleCheck, Shield, UserPlus, Users, UserX } from "lucide-react";
import { DashboardLayout } from "@/components/layout/dashboard-layout";
import { MetricStrip } from "@/components/dashboard/MetricStrip";
import { PageHeader } from "@/components/dashboard/PageHeader";
import { DirectorySearchControls } from "@/components/learners/DirectorySearchControls";
import { DirectoryError } from "@/components/learners/LearnerDirectoryTable";
import { SearchPagination } from "@/components/learners/SearchPagination";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { requireStaffProfile } from "@/lib/auth/server";
import {
  LEARNER_PAGE_SIZE,
  accountSearchFilter,
  learnerStatusFilters,
  learnerStatusLabels,
  parseUserDirectoryParams,
  userDirectoryHref,
  userRoleFilters,
  userRoleLabels,
} from "@/lib/learners/search";
import { createAdminSupabaseClient } from "@/lib/supabase/admin";

export const dynamic = "force-dynamic";

function roleLabel(role: string) {
  if (role === "learner") return "Learner";
  if (role === "instructor") return "Instructor";
  if (role === "admin") return "Administrator";
  return "Unsupported legacy role";
}

export default async function UsersPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  await requireStaffProfile(["admin"]);
  const filters = parseUserDirectoryParams(await searchParams);
  const supabase = createAdminSupabaseClient(15_000);

  // Admin-only page: the service client reads profiles after the role check;
  // filters, ordering and pagination all run in the database.
  let list = supabase
    .from("profiles")
    .select("id,user_id,full_name,email,role,status,learner_id,created_at,deactivated_at", { count: "exact" });
  if (filters.role !== "all") list = list.eq("role", filters.role);
  if (filters.status === "active") list = list.eq("status", "active");
  if (filters.status === "inactive") list = list.neq("status", "active");
  if (filters.q) list = list.or(accountSearchFilter(filters.q));
  list = filters.sort === "name"
    ? list.order("full_name", { ascending: true }).order("user_id", { ascending: true })
    : list.order("created_at", { ascending: false }).order("user_id", { ascending: true });
  const offset = (filters.page - 1) * LEARNER_PAGE_SIZE;

  const [page, total, active, admins] = await Promise.all([
    list.range(offset, offset + LEARNER_PAGE_SIZE - 1),
    supabase.from("profiles").select("id", { count: "exact", head: true }),
    supabase.from("profiles").select("id", { count: "exact", head: true }).eq("status", "active"),
    supabase.from("profiles").select("id", { count: "exact", head: true }).eq("role", "admin"),
  ]);
  const metricsAvailable = !total.error && !active.error && !admins.error;
  const totalCount = total.count ?? 0;
  const activeCount = active.count ?? 0;
  const inactive = totalCount - activeCount;
  const rows = page.data ?? [];
  const matched = page.count ?? 0;
  const filtered = Boolean(filters.q || filters.role !== "all" || filters.status !== "all");
  const heading = filters.status === "inactive" ? "Inactive accounts" : filters.role !== "all" ? userRoleLabels[filters.role] : "Registered accounts";

  return (
    <DashboardLayout>
      <div className="mx-auto max-w-7xl space-y-7">
        <PageHeader
          title="Account management"
          description="Manage real Supabase Auth profiles with independent Learner, Instructor, and Administrator roles."
          actions={<Button asChild><Link href="/users/create"><UserPlus className="mr-2 h-4 w-4" aria-hidden="true" />Create account</Link></Button>}
        />
        {metricsAvailable ? (
          <MetricStrip ariaLabel="Account management metrics" metrics={[
            { label: "Total profiles", value: totalCount, helper: "Authoritative Supabase profiles", icon: Users, featured: true, href: "/users", linkLabel: "Show every account" },
            { label: "Active accounts", value: activeCount, helper: "Profiles currently allowed to sign in", icon: CircleCheck, tone: "positive", href: "/users?status=active", linkLabel: "Show active accounts" },
            { label: "Inactive profiles", value: inactive, helper: "Deactivated or otherwise unavailable", icon: UserX, tone: inactive ? "attention" : "neutral", href: "/users?status=inactive", linkLabel: "Review inactive profiles" },
            { label: "Administrators", value: admins.count ?? 0, helper: "Accounts with Admin governance role", icon: Shield, tone: "neutral", href: "/users?role=admin", linkLabel: "Show administrators" },
          ]} />
        ) : <MetricStrip error ariaLabel="Account management metrics" />}
        <DirectorySearchControls
          action="/users"
          label="Search accounts"
          placeholder="Name, email or student ID"
          query={filters.q}
          clearHref="/users"
          filtered={filtered}
          selects={[
            { name: "role", label: "Role", value: filters.role, options: userRoleFilters.map((value) => ({ value, label: userRoleLabels[value] })) },
            { name: "status", label: "Account status", value: filters.status, options: learnerStatusFilters.map((value) => ({ value, label: learnerStatusLabels[value] })) },
            { name: "sort", label: "Sort by", value: filters.sort, options: [{ value: "created", label: "Newest first" }, { value: "name", label: "Name A–Z" }] },
          ]}
        />
        {page.error ? <DirectoryError message="Accounts could not be loaded. Try again in a moment." retryHref={userDirectoryHref(filters, {})} /> : (
          <section className="overflow-hidden rounded-xl border border-border bg-card" aria-labelledby="accounts-heading">
            <div className="border-b border-border px-5 py-4">
              <h2 id="accounts-heading" className="font-semibold">{heading}</h2>
              <p className="mt-1 text-xs text-muted-foreground">{filtered ? `${matched} matching profile${matched === 1 ? "" : "s"}` : `${matched} profiles in the authoritative project`}</p>
            </div>
            {rows.length ? <div className="divide-y divide-border">{rows.map((profile) => {
              const initials = profile.full_name.split(/\s+/).filter(Boolean).slice(0, 2).map((part) => part[0]?.toUpperCase()).join("") || "U";
              return <Link key={profile.user_id} href={`/users/${profile.user_id}/edit`} className="grid gap-3 px-5 py-4 transition-colors hover:bg-muted/35 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring sm:grid-cols-[minmax(0,1fr)_auto_auto] sm:items-center"><div className="flex min-w-0 items-center gap-3"><Avatar className="h-9 w-9"><AvatarFallback className="bg-primary/10 text-xs font-bold text-primary">{initials}</AvatarFallback></Avatar><div className="min-w-0"><p className="truncate text-sm font-medium">{profile.full_name || "Unnamed account"}</p><p className="truncate text-xs text-muted-foreground">{profile.email}{profile.learner_id ? ` · ID ${profile.learner_id}` : ""}</p></div></div><div className="flex items-center gap-2 text-sm"><Shield className="h-4 w-4 text-muted-foreground" aria-hidden="true" />{roleLabel(profile.role)}</div><Badge variant={profile.status === "active" ? "secondary" : "outline"}>{profile.status}</Badge></Link>;
            })}</div> : (
              <div className="px-5 py-16 text-center" role="status">
                <Users className="mx-auto h-7 w-7 text-muted-foreground" aria-hidden="true" />
                <p className="mt-3 text-sm font-medium">{matched > 0 ? "This page is past the last result." : filtered ? "No accounts match these filters." : "No profiles found."}</p>
                {filtered || matched > 0 ? <Link href={matched > 0 ? userDirectoryHref(filters, { page: 1 }) : "/users"} className="mt-4 inline-flex min-h-11 items-center rounded-lg border border-border px-4 text-sm font-semibold hover:border-primary/30 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">{matched > 0 ? "First page" : "Clear filters"}</Link> : null}
              </div>
            )}
            <SearchPagination total={matched} page={filters.page} noun="accounts" hrefFor={(next) => userDirectoryHref(filters, { page: next })} />
          </section>
        )}
      </div>
    </DashboardLayout>
  );
}
