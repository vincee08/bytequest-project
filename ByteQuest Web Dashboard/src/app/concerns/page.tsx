import { DashboardLayout } from "@/components/layout/dashboard-layout";
import { PageHeader } from "@/components/dashboard/PageHeader";
import { SupportConcernWorkspace } from "@/components/concerns/SupportConcernWorkspace";
import { requireStaffProfile } from "@/lib/auth/server";
import { createServerSupabaseClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function TrainingConcernsPage() {
  const actor = await requireStaffProfile(["instructor"]);
  const supabase = await createServerSupabaseClient();
  const [{ data: classes, error: classError }, { data: concerns, error: concernError }] = await Promise.all([
    supabase.from("classes").select("id,title").eq("instructor_id", actor.userId).eq("status", "active").order("title"),
    supabase.from("support_concerns").select("*").eq("scope", "training").order("created_at", { ascending: false }),
  ]);

  return <DashboardLayout><div className="mx-auto max-w-6xl space-y-6">
    <PageHeader title="Training concerns" description="Track class-related learning, material, equipment, and assessment issues with retained Instructor status history." />
    {classError || concernError
      ? <p role="alert" className="rounded-xl border border-destructive/30 bg-destructive/5 p-5 text-sm">
          Training concerns are unavailable. Verify the support-concerns migration and database connection before using this workflow.
        </p>
      : <SupportConcernWorkspace scope="training" classes={classes ?? []} concerns={concerns ?? []} />}
  </div></DashboardLayout>;
}
