import { DashboardLayout } from "@/components/layout/dashboard-layout";
import { Skeleton } from "@/components/ui/skeleton";

export default function EvaluationsLoading() {
  return (
    <DashboardLayout>
      <div className="mx-auto max-w-7xl space-y-6" role="status" aria-label="Loading the Evaluation Center">
        <Skeleton className="h-16 w-full max-w-xl" />
        <Skeleton className="h-24 w-full" />
        <div className="grid grid-cols-2 gap-2 lg:grid-cols-4">
          {[0, 1, 2, 3].map((index) => <Skeleton key={index} className="h-14" />)}
        </div>
        <Skeleton className="h-72 w-full" />
      </div>
    </DashboardLayout>
  );
}
