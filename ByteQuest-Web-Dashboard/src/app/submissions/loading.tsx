import { DashboardLayout } from "@/components/layout/dashboard-layout";
import { Skeleton } from "@/components/ui/skeleton";

export default function SubmissionsLoading() {
  return (
    <DashboardLayout>
      <div className="mx-auto max-w-7xl space-y-6" role="status" aria-label="Loading homework submissions">
        <Skeleton className="h-16 w-full max-w-xl" />
        <div className="flex gap-2"><Skeleton className="h-11 w-48" /><Skeleton className="h-11 w-40" /></div>
        <Skeleton className="h-24 w-full" />
        <Skeleton className="h-72 w-full" />
      </div>
    </DashboardLayout>
  );
}
