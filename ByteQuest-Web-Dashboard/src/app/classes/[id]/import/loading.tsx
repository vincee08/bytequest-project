import { Skeleton } from "@/components/ui/skeleton";

export default function RosterImportLoading() {
  return (
    <div className="mx-auto max-w-7xl space-y-6" role="status" aria-label="Loading roster import">
      <Skeleton className="h-8 w-64" />
      <Skeleton className="h-4 w-full max-w-2xl" />
      <Skeleton className="h-36 w-full rounded-xl" />
      <Skeleton className="h-44 w-full rounded-xl" />
    </div>
  );
}
