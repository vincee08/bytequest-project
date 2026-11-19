import { DashboardLayout } from "@/components/layout/dashboard-layout";
import { Skeleton } from "@/components/ui/skeleton";

export default function AnalyticsLoading() {
  return (
    <DashboardLayout>
      <div className="mx-auto max-w-[1500px] space-y-6" role="status" aria-label="Loading performance analytics">
        <span className="sr-only">Loading performance analytics</span>
        <div className="space-y-2 border-b border-border pb-5"><Skeleton className="h-8 w-64" /><Skeleton className="h-4 w-full max-w-3xl" /></div>
        <Skeleton className="h-36 w-full rounded-xl" />
        <Skeleton className="h-11 w-full max-w-xl rounded-xl" />
        <div className="grid gap-3.5 sm:grid-cols-2 xl:grid-cols-3">
          {Array.from({ length: 6 }, (_, index) => <Skeleton key={index} className="h-[176px] rounded-xl" />)}
        </div>
        <div className="grid gap-5 xl:grid-cols-2"><Skeleton className="h-[360px] rounded-xl" /><Skeleton className="h-[360px] rounded-xl" /></div>
      </div>
    </DashboardLayout>
  );
}
