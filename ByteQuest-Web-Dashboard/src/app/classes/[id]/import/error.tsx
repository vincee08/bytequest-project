"use client";

import { DashboardPageError } from "@/components/dashboard/DashboardPageError";

export default function RosterImportError({ reset }: { reset: () => void }) {
  return <DashboardPageError title="Unable to load roster import" description="The class roster page did not load. No learner or enrollment was changed." reset={reset} />;
}
