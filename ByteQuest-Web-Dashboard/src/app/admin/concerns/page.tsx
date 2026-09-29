import { DashboardLayout } from "@/components/layout/dashboard-layout";
import { PageHeader } from "@/components/dashboard/PageHeader";
import { SupportConcernWorkspace } from "@/components/concerns/SupportConcernWorkspace";
import { requireStaffProfile } from "@/lib/auth/server";
import { createServerSupabaseClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function SystemConcernsPage() {
  await requireStaffProfile(["admin"]);
  const supabase = await createServerSupabaseClient();
  const [{ data: concerns, error: concernError }, { data: classes, error: classError }] = await Promise.all([
    supabase.from("support_concerns").select("*").order("created_at", { ascending: false }),
    supabase.from("classes").select("id,title").order("title"),
  ]);
  const system = (concerns ?? []).filter((concern) => concern.scope === "system");
  const training = (concerns ?? []).filter((concern) => concern.scope === "training");

  return <DashboardLayout><div className="mx-auto max-w-6xl space-y-6">
    <PageHeader title="System incidents" description="Manage internal account, configuration, security, and platform incidents; review training concerns without taking over Instructor decisions." />
    {concernError || classError
      ? <p role="alert" className="rounded-xl border border-destructive/30 bg-destructive/5 p-5 text-sm">
          System incidents are unavailable. Verify the support-concerns migration and database connection before using this workflow.
        </p>
      : <SupportConcernWorkspace scope="system" concerns={system} oversight={training} classes={classes ?? []} />}
  </div></DashboardLayout>;
}
