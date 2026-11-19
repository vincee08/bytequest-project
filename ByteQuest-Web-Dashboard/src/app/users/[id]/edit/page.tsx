import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { DashboardLayout } from "@/components/layout/dashboard-layout";
import { AccountActions } from "@/components/users/AccountActions";
import { StudentIdForm } from "@/components/users/StudentIdForm";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { requireStaffProfile } from "@/lib/auth/server";
import { createAdminSupabaseClient } from "@/lib/supabase/admin";
import type { AccountStatus, UserRole } from "@/types/auth";

export const dynamic = "force-dynamic";

export default async function EditUserPage({ params }: { params: Promise<{ id: string }> }) {
  await requireStaffProfile(["admin"]);
  const { id } = await params;
  const supabase = createAdminSupabaseClient();
  const { data: profile } = await supabase.from("profiles").select("*").eq("user_id", id).maybeSingle();
  if (!profile) notFound();
  // learner_id_managed is added by the A5 migration (not yet in the generated types).
  const studentIdManaged = (profile as typeof profile & { learner_id_managed?: boolean }).learner_id_managed === true;

  return (
    <DashboardLayout>
      <div className="mx-auto max-w-4xl space-y-7">
        <div><Button asChild variant="ghost" size="sm" className="-ml-3 mb-2"><Link href="/users"><ArrowLeft className="mr-2 h-4 w-4" aria-hidden="true" />Accounts</Link></Button><div className="flex flex-wrap items-center gap-3"><h1 className="text-2xl font-bold tracking-tight">{profile.full_name}</h1><Badge variant={profile.status === "active" ? "secondary" : "outline"}>{profile.status}</Badge></div><p className="mt-1 text-sm text-muted-foreground">{profile.email}</p></div>
        <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_18rem]">
          <div className="space-y-6">
            <section className="rounded-xl border border-border bg-card p-6"><h2 className="font-semibold">Access governance</h2><p className="mb-5 mt-1 text-sm leading-relaxed text-muted-foreground">Change role or lifecycle status through verified Admin RPCs. The database prevents self-demotion and self-deactivation.</p><AccountActions userId={profile.user_id} targetEmail={profile.email} currentRole={profile.role as UserRole} currentStatus={profile.status as AccountStatus} /></section>
            {profile.role === "learner" ? (
              <section className="rounded-xl border border-border bg-card p-6" aria-labelledby="student-id-heading">
                <h2 id="student-id-heading" className="font-semibold">Student ID</h2>
                <p className="mb-5 mt-1 text-sm leading-relaxed text-muted-foreground">Roster imports and administrators confirm student IDs. A confirmed ID is shown read-only in the learner app.</p>
                <StudentIdForm userId={profile.user_id} studentId={profile.learner_id} managed={studentIdManaged} />
              </section>
            ) : null}
          </div>
          <aside className="h-fit rounded-xl border border-border bg-card p-5"><h2 className="font-semibold">Account record</h2><dl className="mt-4 space-y-4 text-sm"><div><dt className="text-xs font-medium uppercase tracking-wide text-muted-foreground">User ID</dt><dd className="mt-1 break-all font-mono text-xs">{profile.user_id}</dd></div>{profile.role === "learner" ? <div><dt className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Student ID</dt><dd className="mt-1 font-mono text-xs">{profile.learner_id ?? "Not set"}{studentIdManaged ? " (staff-managed)" : ""}</dd></div> : null}<div><dt className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Created</dt><dd className="mt-1">{new Intl.DateTimeFormat("en-PH", { dateStyle: "medium" }).format(new Date(profile.created_at))}</dd></div>{profile.deactivation_reason ? <div><dt className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Deactivation reason</dt><dd className="mt-1 leading-relaxed">{profile.deactivation_reason}</dd></div> : null}</dl></aside>
        </div>
      </div>
    </DashboardLayout>
  );
}
