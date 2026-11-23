import { AlertTriangle } from "lucide-react";
import { PageHeader } from "@/components/dashboard/PageHeader";
import { EvaluationCenter } from "@/components/evaluations/EvaluationCenter";
import { QueryFilters } from "@/components/evaluations/QueryFilters";
import { DashboardLayout } from "@/components/layout/dashboard-layout";
import { requireStaffProfile } from "@/lib/auth/server";
import { KIND_LABEL, EVALUATION_KINDS, parseQueueQuery, queueFilters, type QueueResult } from "@/lib/evaluations/requests";
import { loadCurriculumOptions, namesFor } from "@/lib/evaluations/server";
import { evaluationsClient } from "@/lib/evaluations/types";
import { learnerDisplayName, UNNAMED_LEARNER } from "@/lib/learners/identity";
import { createServerSupabaseClient } from "@/lib/supabase/server";
import type { Json } from "@/types/database.generated";

export const dynamic = "force-dynamic";

export default async function EvaluationsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const profile = await requireStaffProfile(["instructor", "admin"]);
  const params = await searchParams;
  const parsed = parseQueueQuery(params);
  const query = parsed.success ? parsed.data : parseQueueQuery({}).data!;
  const supabase = evaluationsClient(await createServerSupabaseClient());
  const [queueResult, classes, learners, catalog] = await Promise.all([
    supabase.rpc("get_evaluation_queue", { p_stage: query.stage, p_filters: queueFilters(query) as Json }),
    supabase.from("classes").select("id,title,status").order("title"),
    supabase.from("profiles").select("user_id,full_name,email").eq("role", "learner").order("full_name").limit(500),
    loadCurriculumOptions(supabase).catch(() => null),
  ]);
  const queue = queueResult.error ? null : (queueResult.data as unknown as QueueResult);
  if (queue) {
    const people = await namesFor(queue.items.map((item) => item.learner.id)).catch(() => null);
    for (const item of queue.items) {
      const person = item.learner.id ? people?.get(item.learner.id) : undefined;
      if (!item.learner.name) item.learner.name = person?.name || UNNAMED_LEARNER;
      item.learner.email = person?.email || null;
    }
  }
  const current = (name: string) => {
    const value = params[name];
    return (Array.isArray(value) ? value[0] : value) ?? "";
  };
  const filterQuery = Object.fromEntries(["tab", "class", "kind", "coc", "module", "learner"].map((name) => [name, current(name)]).filter(([, value]) => value));

  return (
    <DashboardLayout>
      <div className="mx-auto max-w-7xl space-y-6">
        <PageHeader
          title="Evaluation Center"
          description="Objective 4: technical assessments, quiz essays and homework move through Evaluate, Finalize and Release. Nothing reaches a learner before release, and no stage can be skipped."
        />
        {!parsed.success ? <p role="alert" className="rounded-xl border border-amber-300 bg-amber-50 p-3 text-sm text-amber-950">Some filters in the link were not valid and were ignored.</p> : null}
        {profile.role === "admin" ? <p className="rounded-xl border border-border bg-muted/40 p-3 text-sm">Admin view: read-only across every class. Evaluation, finalization and release stay with each class instructor.</p> : null}
        <QueryFilters
          ariaLabel="Evaluation filters"
          keep={["tab"]}
          selects={[
            { name: "class", label: "Class", allLabel: profile.role === "admin" ? "All classes" : "All my classes", value: current("class"),
              options: (classes.data ?? []).map((c) => ({ value: c.id, label: c.status === "active" ? c.title : `${c.title} (archived)` })) },
            { name: "kind", label: "Type", allLabel: "All types", value: current("kind"),
              options: EVALUATION_KINDS.map((kind) => ({ value: kind, label: KIND_LABEL[kind] })) },
            { name: "coc", label: "COC", allLabel: "All COCs", value: current("coc"),
              options: (catalog?.cocs ?? []).map((c) => ({ value: c.coc_code, label: `${c.coc_code.toUpperCase()} · ${c.title}` })) },
            { name: "module", label: "Module", allLabel: "All modules", value: current("module"), parentName: "coc",
              options: (catalog?.modules ?? []).map((m) => ({ value: m.id, label: `${m.code} ${m.title}`, parent: m.coc_code })) },
            { name: "learner", label: "Learner", allLabel: "All learners", value: current("learner"),
              options: (learners.data ?? []).map((l) => ({ value: l.user_id, label: learnerDisplayName(l) })) },
          ]}
        />
        {queue ? (
          <EvaluationCenter
            stage={queue.stage}
            counts={queue.counts}
            items={queue.items}
            total={queue.total}
            limit={queue.limit}
            offset={queue.offset}
            quizAvailable={queue.quiz_available}
            canAct={profile.role === "instructor"}
            query={filterQuery}
          />
        ) : (
          <div role="alert" className="rounded-xl border border-destructive/40 bg-card px-5 py-12 text-center">
            <AlertTriangle className="mx-auto h-7 w-7 text-destructive" aria-hidden="true" />
            <p className="mt-3 text-sm font-semibold">The Evaluation Center could not load.</p>
            <p className="mt-1 text-sm text-muted-foreground">Refresh the page. If it continues, check the server connection.</p>
          </div>
        )}
      </div>
    </DashboardLayout>
  );
}
