import { DashboardLayout } from "@/components/layout/dashboard-layout";
import { Skeleton } from "@/components/ui/skeleton";

export default function LearnerProfileLoading() {
  return (
    <DashboardLayout>
      <div className="mx-auto max-w-[1400px] space-y-6" role="status" aria-label="Loading learner analytics">
        <span className="sr-only">Loading learner analytics</span>
        <div className="space-y-2 border-b border-border pb-5"><Skeleton className="h-5 w-36" /><Skeleton className="h-8 w-72" /><Skeleton className="h-4 w-full max-w-2xl" /></div>
        <Skeleton className="h-40 w-full rounded-xl" />
        <div className="grid gap-4 xl:grid-cols-2"><Skeleton className="h-72 rounded-xl" /><Skeleton className="h-72 rounded-xl" /></div>
        <Skeleton className="h-64 w-full rounded-xl" />
      </div>
    </DashboardLayout>
  );
}
