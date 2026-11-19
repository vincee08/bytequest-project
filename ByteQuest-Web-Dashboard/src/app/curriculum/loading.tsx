import { DashboardLayout } from "@/components/layout/dashboard-layout";
import { Skeleton } from "@/components/ui/skeleton";

export default function CurriculumLoading() {
  return (
    <DashboardLayout>
      <div className="mx-auto max-w-7xl space-y-6" aria-label="Loading the curriculum">
        <div className="space-y-3 border-b border-border pb-5">
          <Skeleton className="h-8 w-48 max-w-full" />
          <Skeleton className="h-4 w-full max-w-3xl" />
        </div>
        <Skeleton className="h-10 w-80 max-w-full rounded-xl" />
        <div className="grid gap-5 lg:grid-cols-[minmax(0,300px)_minmax(0,1fr)]">
          <div className="space-y-2">
            {[0, 1, 2, 3].map((item) => (
              <Skeleton key={item} className="h-20 rounded-xl" />
            ))}
          </div>
          <Skeleton className="h-[480px] rounded-xl" />
        </div>
      </div>
    </DashboardLayout>
  );
}
