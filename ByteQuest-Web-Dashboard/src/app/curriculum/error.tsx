"use client";

import { DashboardPageError } from "@/components/dashboard/DashboardPageError";

export default function CurriculumError({ reset }: { reset: () => void }) {
  return (
    <DashboardPageError
      title="Unable to load the curriculum"
      description="The curriculum request did not complete. No topic, revision or publication status was changed."
      reset={reset}
    />
  );
}
