import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft, History } from "lucide-react";
import { z } from "zod";
import { DashboardLayout } from "@/components/layout/dashboard-layout";
import { PageHeader } from "@/components/dashboard/PageHeader";
import { RosterImportWorkspace } from "@/components/roster/RosterImportWorkspace";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { requireStaffProfile } from "@/lib/auth/server";
import { rosterClient } from "@/lib/roster/server";
import { createServerSupabaseClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

const dateTime = new Intl.DateTimeFormat("en-PH", { dateStyle: "medium", timeStyle: "short", timeZone: "Asia/Manila" });

export default async function ClassRosterImportPage({ params }: { params: Promise<{ id: string }> }) {
  await requireStaffProfile(["instructor"]);
  const { id } = await params;
  if (!z.string().uuid().safeParse(id).success) notFound();
  const supabase = await createServerSupabaseClient();
  const { data: classroom, error } = await supabase.from("classes").select("id,title,class_code,status").eq("id", id).maybeSingle();
  if (error) throw new Error("The class could not be loaded.");
  if (!classroom) notFound();

  const roster = rosterClient(supabase);
  const [batches, entries] = await Promise.all([
    roster.from("roster_import_batches").select("*").eq("class_id", id).order("created_at", { ascending: false }).limit(10),
    roster.from("class_roster_entries").select("status").eq("class_id", id),
  ]);
  if (batches.error || entries.error) throw new Error("The roster import history could not be loaded.");
  const pending = (entries.data ?? []).filter((row) => row.status === "pending").length;
  const joined = (entries.data ?? []).filter((row) => row.status === "enrolled").length;
  const joinedElsewhere = (entries.data ?? []).filter((row) => row.status === "enrolled_elsewhere").length;

  return (
    <DashboardLayout>
      <div className="mx-auto max-w-7xl space-y-7">
        <div>
          <Button asChild variant="ghost" size="sm" className="-ml-3 mb-2">
            <Link href={`/classes/${id}?tab=learners`}><ArrowLeft className="mr-2 h-4 w-4" aria-hidden="true" />{classroom.title}</Link>
          </Button>
          <PageHeader
            title="Import class roster"
            description="Upload an Excel roster. Registered learners are enrolled when you confirm; new emails wait as pending entries and enroll automatically when that learner signs up with the same email. A learner can belong to only one class at a time. Instructors never create accounts."
            actions={<Badge variant={classroom.status === "active" ? "secondary" : "outline"}>{classroom.status}</Badge>}
          />
        </div>

        {classroom.status === "active" ? (
          <RosterImportWorkspace classId={id} classTitle={classroom.title} />
        ) : (
          <p role="status" className="rounded-xl border border-border bg-card px-5 py-8 text-center text-sm text-muted-foreground">
            This class is archived. Roster imports are available only for active classes.
          </p>
        )}

        <section className="overflow-hidden rounded-xl border border-border bg-card" aria-labelledby="roster-history">
          <div className="flex flex-col gap-1 border-b border-border px-5 py-4 sm:flex-row sm:items-center sm:justify-between">
            <h2 id="roster-history" className="flex items-center gap-2 font-semibold"><History className="h-4 w-4" aria-hidden="true" />Recent imports</h2>
            <p className="text-xs text-muted-foreground">
              {pending} pending sign-up · {joined} joined via roster
              {joinedElsewhere ? ` · ${joinedElsewhere} signed up but joined another class (one class per learner)` : ""}
            </p>
          </div>
          {batches.data?.length ? (
            <div className="overflow-x-auto">
              <table className="w-full min-w-[720px] text-left text-sm">
                <thead className="bg-muted/45 text-xs text-muted-foreground">
                  <tr>
                    <th scope="col" className="px-5 py-2.5 font-medium">Imported</th>
                    <th scope="col" className="px-3 py-2.5 font-medium">File</th>
                    <th scope="col" className="px-3 py-2.5 text-right font-medium">Rows</th>
                    <th scope="col" className="px-3 py-2.5 text-right font-medium">Enrolled</th>
                    <th scope="col" className="px-3 py-2.5 text-right font-medium">Pending</th>
                    <th scope="col" className="px-3 py-2.5 text-right font-medium">Skipped</th>
                    <th scope="col" className="px-5 py-2.5 text-right font-medium">Invalid</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-border">
                  {batches.data.map((batch) => (
                    <tr key={batch.id}>
                      <td className="px-5 py-3 text-xs text-muted-foreground">{dateTime.format(new Date(batch.created_at))}</td>
                      <td className="break-all px-3 py-3">{batch.file_name ?? "Roster file"}</td>
                      <td className="px-3 py-3 text-right tabular-nums">{batch.row_count}</td>
                      <td className="px-3 py-3 text-right tabular-nums">{batch.enrolled_count}</td>
                      <td className="px-3 py-3 text-right tabular-nums">{batch.pending_count}</td>
                      <td className="px-3 py-3 text-right tabular-nums">{batch.skipped_count}</td>
                      <td className="px-5 py-3 text-right tabular-nums">{batch.invalid_count}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : (
            <p className="px-5 py-10 text-center text-sm text-muted-foreground">No roster has been imported into this class yet.</p>
          )}
        </section>
      </div>
    </DashboardLayout>
  );
}
