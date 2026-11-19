import { CurriculumWorkspaceView } from "@/components/curriculum/CurriculumWorkspace";
import { DashboardLayout } from "@/components/layout/dashboard-layout";
import { requireStaffProfile } from "@/lib/auth/server";
import { loadCurriculumWorkspace } from "@/lib/curriculum/server";
import { createAdminSupabaseClient } from "@/lib/supabase/admin";
import { createServerSupabaseClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

function single(value: string | string[] | undefined) {
  return typeof value === "string" && value.length <= 80 ? value : undefined;
}

export default async function CurriculumPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const profile = await requireStaffProfile(["instructor", "admin"]);
  const params = await searchParams;
  const workspace = await loadCurriculumWorkspace({
    id: profile.userId,
    role: profile.role,
    client: await createServerSupabaseClient(),
    service: createAdminSupabaseClient(30000),
  });

  return (
    <DashboardLayout>
      <div className="mx-auto max-w-7xl">
        <CurriculumWorkspaceView
          workspace={workspace}
          initialTab={single(params.tab)}
          initialModule={single(params.module)}
          initialTopic={single(params.topic)}
        />
      </div>
    </DashboardLayout>
  );
}
