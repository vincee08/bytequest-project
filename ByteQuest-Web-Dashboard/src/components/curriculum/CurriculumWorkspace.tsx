"use client";

import React, { useState } from "react";
import { usePathname, useRouter } from "next/navigation";
import { toast } from "sonner";
import { Archive, BookOpenCheck, Check, FilePlus2, History, Lock, PencilLine } from "lucide-react";
import { PageHeader } from "@/components/dashboard/PageHeader";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import type { CurriculumTopic, CurriculumWorkspace, TopicRevision } from "@/lib/curriculum/types";
import { inProgressStatuses, revisionActions, statusLabels, workflowStages, type RevisionAction } from "@/lib/curriculum/workflow";
import { EvaluationDialog, type EvaluationResult } from "./EvaluationDialog";
import { MarkdownPreview } from "./MarkdownPreview";
import { ContentStatusBadge, PublicationTimeline } from "./PublicationTimeline";
import { TopicEditorDialog, type TopicDraft } from "./TopicEditorDialog";

const actionLabels: Record<RevisionAction, string> = {
  edit: "Edit draft",
  new_revision: "Edit as a new revision",
  submit: "Submit for evaluation",
  evaluate: "Evaluate",
  finalize: "Finalize",
  approve: "Approve",
  publish: "Publish",
  unpublish: "Unpublish",
};
const successMessages: Record<string, string> = {
  create_topic: "Topic created as a draft.",
  edit_revision: "Draft saved.",
  submit: "Submitted for evaluation.",
  evaluate: "Evaluation recorded.",
  finalize: "Revision finalized. Its content is now locked.",
  approve: "Revision approved.",
  publish: "Published. Learners now see this revision.",
  unpublish: "Unpublished. Learners no longer see this lesson.",
  archive_topic: "Topic archived.",
};

type TopicView = {
  topic: CurriculumTopic;
  revisions: TopicRevision[];
  published: TopicRevision | null;
  working: TopicRevision | null;
  display: TopicRevision | null;
};

function topicView(topic: CurriculumTopic, all: TopicRevision[]): TopicView {
  const revisions = all.filter((revision) => revision.topic_id === topic.id).sort((a, b) => b.revision_number - a.revision_number);
  const published = revisions.find((revision) => revision.status === "published") ?? null;
  const working = revisions.find((revision) => inProgressStatuses.has(revision.status)) ?? null;
  return { topic, revisions, published, working, display: working ?? published ?? revisions[0] ?? null };
}

function WorkflowStepper({ status }: { status: TopicRevision["status"] }) {
  const current = status === "needs_revision" ? "submitted" : status;
  const index = workflowStages.indexOf(current);
  return (
    <ol className="flex flex-wrap items-center gap-1.5 text-xs" aria-label="Publication workflow">
      {workflowStages.map((stage, stageIndex) => {
        const done = index >= 0 && stageIndex < index;
        const active = stageIndex === index;
        return (
          <li
            key={stage}
            aria-current={active ? "step" : undefined}
            className={
              active
                ? "rounded-full bg-primary px-2.5 py-1 font-semibold text-primary-foreground"
                : done
                  ? "rounded-full bg-primary/10 px-2.5 py-1 font-medium text-primary"
                  : "rounded-full bg-muted px-2.5 py-1 text-muted-foreground"
            }
          >
            {done ? <Check className="mr-1 inline h-3 w-3" aria-hidden="true" /> : null}
            {statusLabels[stage]}
          </li>
        );
      })}
      {status === "needs_revision" ? <li className="font-semibold text-destructive">· Returned for revision</li> : null}
    </ol>
  );
}

export function CurriculumWorkspaceView({
  workspace,
  initialTab,
  initialModule,
  initialTopic,
}: {
  workspace: CurriculumWorkspace;
  initialTab?: string;
  initialModule?: string;
  initialTopic?: string;
}) {
  const router = useRouter();
  const pathname = usePathname();
  const cocs = workspace.cocs.filter((coc) => workspace.modules.some((module) => module.coc_code === coc.coc_code));
  const [tab, setTab] = useState(cocs.some((coc) => coc.coc_code === initialTab) ? initialTab! : (cocs[0]?.coc_code ?? "coc1"));
  const [moduleCode, setModuleCode] = useState<string | undefined>(initialModule);
  const [topicId, setTopicId] = useState<string | undefined>(initialTopic);
  const [busy, setBusy] = useState<string | null>(null);
  const [editor, setEditor] = useState<{ key: number; mode: "create" | "edit" | "new_revision"; revision?: TopicRevision } | null>(null);
  const [evaluation, setEvaluation] = useState<{ key: number; revision: TopicRevision } | null>(null);
  const [confirm, setConfirm] = useState<
    { action: "publish" | "unpublish"; revision: TopicRevision } | { action: "archive_topic"; topic: CurriculumTopic } | null
  >(null);

  const modules = workspace.modules.filter((module) => module.coc_code === tab).sort((a, b) => a.sequence_order - b.sequence_order);
  const selectedModule = modules.find((module) => module.code === moduleCode) ?? modules[0];
  const outcomes = workspace.outcomes
    .filter((outcome) => outcome.module_id === selectedModule?.id)
    .sort((a, b) => a.sequence_order - b.sequence_order);
  const missions = workspace.missions.filter((mission) => mission.module_id === selectedModule?.id);
  const topics = workspace.topics
    .filter((topic) => topic.module_id === selectedModule?.id && !topic.archived_at)
    .sort((a, b) => a.sequence_order - b.sequence_order)
    .map((topic) => topicView(topic, workspace.revisions));
  const selected = topics.find((view) => view.topic.id === topicId) ?? topics[0] ?? null;
  const outcomeCode = new Map(workspace.outcomes.map((outcome) => [outcome.id, outcome.code]));
  const person = (id: string | null) => (id && workspace.people[id]) || "Staff member";
  const isAdmin = workspace.role === "admin";

  function navigate(next: { tab?: string; module?: string | null; topic?: string | null }) {
    const params = new URLSearchParams();
    params.set("tab", next.tab ?? tab);
    const nextModule = next.module === undefined ? selectedModule?.code : next.module;
    const nextTopic = next.topic === undefined ? selected?.topic.id : next.topic;
    if (nextModule) params.set("module", nextModule);
    if (nextTopic) params.set("topic", nextTopic);
    router.replace(`${pathname}?${params.toString()}`, { scroll: false });
  }

  async function run(body: Record<string, unknown>): Promise<boolean> {
    const action = String(body.action);
    setBusy(action);
    try {
      const response = await fetch("/api/curriculum", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      const json = (await response.json().catch(() => ({}))) as { error?: string; record?: { topic?: { id?: string } } };
      if (!response.ok) {
        toast.error(json.error ?? "The curriculum change could not be saved. Refresh and try again.");
        return false;
      }
      toast.success(successMessages[action] ?? "Saved.");
      if (action === "create_topic" && json.record?.topic?.id) {
        setTopicId(json.record.topic.id);
        navigate({ topic: json.record.topic.id });
      }
      router.refresh();
      return true;
    } catch {
      toast.error("Network error. Check your connection and try again.");
      return false;
    } finally {
      setBusy(null);
    }
  }

  function startAction(action: RevisionAction, revision: TopicRevision) {
    if (action === "edit") return setEditor({ key: Date.now(), mode: "edit", revision });
    if (action === "new_revision") return setEditor({ key: Date.now(), mode: "new_revision", revision });
    if (action === "evaluate") return setEvaluation({ key: Date.now(), revision });
    if (action === "publish" || action === "unpublish") return setConfirm({ action, revision });
    void run({ action, revision_id: revision.id });
  }

  async function saveDraft(draft: TopicDraft) {
    if (!editor) return;
    const ok =
      editor.mode === "create"
        ? await run({ action: "create_topic", module_id: selectedModule?.id, ...draft })
        : await run({ action: "edit_revision", revision_id: editor.revision?.id, ...draft, summary: draft.summary || null });
    if (ok) setEditor(null);
  }

  function actionButtons(view: TopicView, revision: TopicRevision) {
    const actions = revisionActions({
      role: workspace.role,
      actorId: workspace.actorId,
      revision,
      topic: view.topic,
      otherRevisionInProgress: Boolean(view.working && view.working.id !== revision.id),
    });
    if (!actions.length) return null;
    return (
      <div className="flex flex-wrap gap-2">
        {actions.map((action) => (
          <Button
            key={action}
            type="button"
            size="sm"
            className="min-h-10"
            variant={action === "edit" || action === "new_revision" || action === "unpublish" ? "outline" : "default"}
            disabled={busy !== null}
            onClick={() => startAction(action, revision)}
          >
            {action === "publish" && revision.status === "unpublished" ? "Republish" : actionLabels[action]}
          </Button>
        ))}
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="Curriculum"
        description="Official CSS NC II learning outcomes organised as COC modules, with lessons that move Draft → Submitted → Evaluated → Finalized → Approved → Published. Learners only ever see the published revision."
        actions={<Badge variant="outline">{isAdmin ? "Admin: full workflow" : "Instructor: author and submit"}</Badge>}
      />

      <Tabs
        value={tab}
        onValueChange={(value) => {
          setTab(value);
          setModuleCode(undefined);
          setTopicId(undefined);
          navigate({ tab: value, module: null, topic: null });
        }}
      >
        <TabsList aria-label="Certificates of competency">
          {cocs.map((coc) => (
            <TabsTrigger key={coc.coc_code} value={coc.coc_code} className="min-h-9">
              COC {coc.order_index}
            </TabsTrigger>
          ))}
        </TabsList>
      </Tabs>
      <p className="text-sm text-muted-foreground">{cocs.find((coc) => coc.coc_code === tab)?.title}</p>

      <div className="grid gap-5 lg:grid-cols-[minmax(0,300px)_minmax(0,1fr)]">
        <nav aria-label="Modules" className="space-y-2">
          {modules.map((module) => {
            const count = workspace.topics.filter((topic) => topic.module_id === module.id && !topic.archived_at).length;
            const active = module.id === selectedModule?.id;
            return (
              <button
                key={module.id}
                type="button"
                aria-current={active ? "true" : undefined}
                onClick={() => {
                  setModuleCode(module.code);
                  setTopicId(undefined);
                  navigate({ module: module.code, topic: null });
                }}
                className={`w-full rounded-xl border p-3 text-left transition-colors duration-150 ${active ? "border-primary bg-primary/[0.06]" : "border-border bg-card hover:bg-muted/50"}`}
              >
                <span className="block text-xs font-medium text-muted-foreground">
                  Module {module.sequence_order} · {module.code}
                </span>
                <span className="block text-sm font-semibold leading-5">{module.title}</span>
                <span className="mt-1 block text-xs text-muted-foreground">
                  {count === 1 ? "1 topic" : `${count} topics`} ·{" "}
                  {workspace.missions.filter((mission) => mission.module_id === module.id).length} practice missions
                </span>
              </button>
            );
          })}
        </nav>

        {selectedModule ? (
          <section className="min-w-0 space-y-5" aria-labelledby="module-heading">
            <div className="rounded-xl border border-border bg-card p-5">
              <p className="text-xs font-medium text-muted-foreground">
                Module {selectedModule.sequence_order} · {selectedModule.code} · official curriculum learning outcome (read-only)
              </p>
              <h2 id="module-heading" className="mt-1 text-lg font-bold">
                {selectedModule.title}
              </h2>
              {selectedModule.element_title ? (
                <p className="text-sm text-muted-foreground">Unit element: {selectedModule.element_title}</p>
              ) : null}
              <p className="mt-1 text-xs text-muted-foreground">Source: {selectedModule.source_reference}</p>
              <h3 className="mt-4 text-sm font-semibold">Performance criteria</h3>
              <ul className="mt-2 space-y-1.5">
                {outcomes.map((outcome) => (
                  <li key={outcome.id} className="flex gap-3 text-sm">
                    <span className="w-9 shrink-0 font-semibold">{outcome.code}</span>
                    <span>
                      {outcome.statement}
                      <span className="ml-1 text-xs text-muted-foreground">({outcome.source_reference})</span>
                    </span>
                  </li>
                ))}
              </ul>
              <h3 className="mt-4 text-sm font-semibold">Practice missions in this module</h3>
              {missions.length ? (
                <ul className="mt-2 flex flex-wrap gap-2">
                  {missions.map((mission) => (
                    <li key={mission.mission_code}>
                      <Badge variant="outline">
                        {mission.mission_code.toUpperCase().replace("_", " ")} · {mission.title}
                      </Badge>
                    </li>
                  ))}
                </ul>
              ) : (
                <p className="mt-1 text-sm text-muted-foreground">
                  No practice mission yet. Learners complete this module through its published lessons.
                </p>
              )}
            </div>

            <div className="rounded-xl border border-border bg-card p-5">
              <div className="flex flex-wrap items-center justify-between gap-3">
                <div>
                  <h3 className="text-base font-semibold">Topics</h3>
                  <p className="text-xs text-muted-foreground">
                    Published topics are required for module completion and unlocking.
                  </p>
                </div>
                <Button
                  type="button"
                  className="min-h-10"
                  disabled={busy !== null}
                  onClick={() => setEditor({ key: Date.now(), mode: "create" })}
                >
                  <FilePlus2 className="mr-2 h-4 w-4" aria-hidden="true" />
                  Add topic
                </Button>
              </div>
              {topics.length === 0 ? (
                <div className="mt-4 rounded-lg border border-dashed border-border p-6 text-center">
                  <BookOpenCheck className="mx-auto h-6 w-6 text-muted-foreground" aria-hidden="true" />
                  <p className="mt-2 text-sm font-medium">No topics yet — add the first lesson for this module</p>
                </div>
              ) : (
                <ul className="mt-4 grid gap-2 md:grid-cols-2">
                  {topics.map((view) => (
                    <li key={view.topic.id}>
                      <button
                        type="button"
                        aria-current={view.topic.id === selected?.topic.id ? "true" : undefined}
                        onClick={() => {
                          setTopicId(view.topic.id);
                          navigate({ topic: view.topic.id });
                        }}
                        className={`w-full rounded-lg border p-3 text-left transition-colors duration-150 ${view.topic.id === selected?.topic.id ? "border-primary bg-primary/[0.05]" : "border-border hover:bg-muted/50"}`}
                      >
                        <span className="block text-sm font-semibold">{view.display?.title ?? "Untitled topic"}</span>
                        <span className="mt-1.5 flex flex-wrap gap-1.5">
                          {view.working ? <ContentStatusBadge status={view.working.status} /> : null}
                          {view.published ? (
                            <Badge variant="secondary">Published · revision {view.published.revision_number}</Badge>
                          ) : !view.working && view.display ? (
                            <ContentStatusBadge status={view.display.status} />
                          ) : null}
                        </span>
                      </button>
                    </li>
                  ))}
                </ul>
              )}
            </div>

            {selected && selected.display ? (
              <div className="space-y-4 rounded-xl border border-border bg-card p-5">
                <div className="flex flex-wrap items-start justify-between gap-3">
                  <div className="min-w-0">
                    <p className="text-xs text-muted-foreground">
                      Revision {selected.display.revision_number} · {person(selected.display.author_id)}
                    </p>
                    <h3 className="text-lg font-bold">{selected.display.title}</h3>
                  </div>
                  {isAdmin ? (
                    <Button
                      type="button"
                      variant="outline"
                      size="sm"
                      className="min-h-10"
                      disabled={busy !== null}
                      onClick={() => setConfirm({ action: "archive_topic", topic: selected.topic })}
                    >
                      <Archive className="mr-2 h-4 w-4" aria-hidden="true" />
                      Archive topic
                    </Button>
                  ) : null}
                </div>
                <WorkflowStepper status={selected.display.status} />

                {selected.working ? (
                  <div className="space-y-2 rounded-lg bg-muted/40 p-3">
                    <div className="flex flex-wrap items-center gap-2 text-sm">
                      <PencilLine className="h-4 w-4" aria-hidden="true" />
                      <span className="font-semibold">Revision {selected.working.revision_number} in workflow</span>
                      <ContentStatusBadge status={selected.working.status} />
                      {!["draft", "needs_revision"].includes(selected.working.status) ? (
                        <span className="inline-flex items-center gap-1 text-xs text-muted-foreground">
                          <Lock className="h-3 w-3" aria-hidden="true" /> Content locked
                        </span>
                      ) : null}
                    </div>
                    {selected.working.evaluation_notes ? (
                      <p className="text-sm">
                        <span className="font-semibold">Evaluation notes:</span> {selected.working.evaluation_notes}
                      </p>
                    ) : null}
                    {actionButtons(selected, selected.working)}
                  </div>
                ) : null}
                {selected.published ? (
                  <div className="space-y-2 rounded-lg border border-emerald-200 bg-emerald-50/60 p-3">
                    <p className="text-sm font-semibold text-emerald-900">
                      Learners see revision {selected.published.revision_number}
                      {selected.published.published_at
                        ? ` · published ${new Date(selected.published.published_at).toLocaleDateString("en-PH")}`
                        : ""}
                    </p>
                    {actionButtons(selected, selected.published)}
                  </div>
                ) : !selected.working && selected.display.status === "unpublished" ? (
                  <div className="space-y-2 rounded-lg border border-border p-3">
                    <p className="text-sm font-semibold">Not visible to learners (unpublished)</p>
                    {actionButtons(selected, selected.display)}
                  </div>
                ) : null}

                {selected.display.summary ? <p className="text-sm text-muted-foreground">{selected.display.summary}</p> : null}
                {selected.display.outcome_ids.length ? (
                  <p className="flex flex-wrap gap-1.5">
                    {selected.display.outcome_ids.map((id) => (
                      <Badge key={id} variant="outline">
                        PC {outcomeCode.get(id) ?? "—"}
                      </Badge>
                    ))}
                  </p>
                ) : null}
                <div className="rounded-lg border border-border p-4">
                  <MarkdownPreview source={selected.display.body_markdown} emptyLabel="This revision has no lesson content yet." />
                </div>

                <details className="rounded-lg border border-border p-3">
                  <summary className="flex min-h-9 cursor-pointer items-center gap-2 text-sm font-semibold">
                    <History className="h-4 w-4" aria-hidden="true" />
                    Revisions and publication history
                  </summary>
                  <ul className="mt-3 space-y-1 text-sm">
                    {selected.revisions.map((revision) => (
                      <li key={revision.id} className="flex flex-wrap items-center gap-2">
                        <span className="font-medium">Revision {revision.revision_number}</span>
                        <ContentStatusBadge status={revision.status} />
                        <span className="text-xs text-muted-foreground">
                          {person(revision.author_id)} · updated {new Date(revision.updated_at).toLocaleString("en-PH")}
                        </span>
                      </li>
                    ))}
                  </ul>
                  <div className="mt-4">
                    <PublicationTimeline
                      events={workspace.events.filter((event) => event.entity_id === selected.topic.id)}
                      revisions={selected.revisions}
                      people={workspace.people}
                    />
                  </div>
                </details>
              </div>
            ) : null}
          </section>
        ) : (
          <p className="text-sm text-muted-foreground">No modules are available for this COC.</p>
        )}
      </div>

      {editor ? (
        <TopicEditorDialog
          key={editor.key}
          open
          heading={editor.mode === "create" ? `Add a topic to ${selectedModule?.code ?? "this module"}` : editor.mode === "new_revision" ? "Edit as a new revision" : "Edit draft"}
          description={
            editor.mode === "new_revision"
              ? "Learners keep seeing the published revision until this new revision is evaluated, finalized, approved and published."
              : "Drafts are visible to staff only."
          }
          initial={{
            title: editor.revision?.title ?? "",
            summary: editor.revision?.summary ?? "",
            body_markdown: editor.revision?.body_markdown ?? "",
            outcome_ids: editor.revision?.outcome_ids ?? [],
          }}
          outcomes={outcomes}
          saving={busy !== null}
          onCancel={() => setEditor(null)}
          onSave={saveDraft}
        />
      ) : null}

      {evaluation ? (
        <EvaluationDialog
          key={evaluation.key}
          open
          revisionLabel={`revision ${evaluation.revision.revision_number}`}
          saving={busy !== null}
          onCancel={() => setEvaluation(null)}
          onSubmit={async (result: EvaluationResult, notes: string) => {
            if (await run({ action: "evaluate", revision_id: evaluation.revision.id, result, notes })) setEvaluation(null);
          }}
        />
      ) : null}

      <AlertDialog open={confirm !== null} onOpenChange={(open) => (!open ? setConfirm(null) : undefined)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>
              {confirm?.action === "archive_topic" ? "Archive this topic?" : confirm?.action === "unpublish" ? "Unpublish this lesson?" : "Publish this revision?"}
            </AlertDialogTitle>
            <AlertDialogDescription>
              {confirm?.action === "archive_topic"
                ? "Learners stop seeing the topic and it no longer counts toward module completion. Completed modules and unlocks are kept."
                : confirm?.action === "unpublish"
                  ? "Learners stop seeing this lesson. Unlocks and completions already earned are kept."
                  : "Learners will see this revision immediately. Any previously published revision of the topic is unpublished."}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={busy !== null}>Cancel</AlertDialogCancel>
            <AlertDialogAction
              disabled={busy !== null}
              onClick={() => {
                const current = confirm;
                setConfirm(null);
                if (!current) return;
                if (current.action === "archive_topic") void run({ action: "archive_topic", topic_id: current.topic.id });
                else void run({ action: current.action, revision_id: current.revision.id });
              }}
            >
              Confirm
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
