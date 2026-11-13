"use client";

import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import {
  ArrowDown,
  ArrowLeft,
  ArrowUp,
  Check,
  Eye,
  Loader2,
  Pencil,
  Plus,
  Send,
  Trash2,
} from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { createClient } from "@/lib/supabase/client";
import {
  itemTypeLabels,
  publicationReadiness,
  quizErrorMessage,
  quizSchema,
  type QuestionInput,
  type QuizItem,
} from "@/lib/quizzes/authoring";
import { QuestionEditor } from "./QuestionEditor";
import { QuizPreview } from "./QuizPreview";
import { QuizDeadlineControls } from './QuizDeadlineControls';
import { manilaInputToUtc } from '@/lib/activities/dates';
import { AiQuizPanel, type QuizGroundingCatalog } from "./AiQuizPanel";

interface Version {
  id: string;
  versionNumber: number;
  status: "draft" | "published" | "retired";
  instructions: string | null;
  changeSummary?: string | null;
  publishedAt?: string | null;
}
interface Assignment {
  id: string;
  classId: string;
  versionId: string;
  status: string;
  classTitle: string;
  dueAt?: string | null;
}
export interface QuizWorkspaceProps {
  initialTab?: string;
  serverNow?: string;
  quiz: {
    id: string;
    title: string;
    topic: string;
    description: string | null;
    cocModuleId: string | null;
    archivedAt: string | null;
  };
  version: Version | null;
  items: QuizItem[];
  hasDraft: boolean;
  modules: { id: string; code: string; title: string }[];
  classes: { id: string; title: string; code: string | null }[];
  grounding: QuizGroundingCatalog | null;
  versions: Version[];
  assignments: Assignment[];
  results: {
    id: string;
    learner: string;
    classTitle: string;
    status: string;
    versionNumber: number;
    completedAt: string | null;
    correctCount: number | null;
    questionCount: number | null;
  }[];
}
const panel = "rounded-xl border border-border bg-card p-4 sm:p-5";
const content = "mt-4 data-[state=inactive]:hidden";

export function QuizAuthoringWorkspace({
  quiz,
  version,
  items,
  hasDraft,
  modules,
  classes,
  grounding,
  versions,
  assignments,
  results,
  initialTab,
  serverNow,
}: QuizWorkspaceProps) {
  const router = useRouter();
  const [tab, setTab] = useState(initialTab === 'publishing' ? 'publishing' : "questions");
  const [quizDeadline, setQuizDeadline] = useState('');
  const [busy, setBusy] = useState<string | null>(null);
  const busyRef = useRef(false);
  const [feedback, setFeedback] = useState<{
    error: boolean;
    text: string;
  } | null>(null);
  const [editor, setEditor] = useState<{ item: QuizItem | null } | null>(null);
  const [questionDirty, setQuestionDirty] = useState(false);
  const [preview, setPreview] = useState(false);
  const [review, setReview] = useState<{
    item: QuizItem;
    action: "review" | "remove";
  } | null>(null);
  const [reviewNote, setReviewNote] = useState("");
  const [reviewError, setReviewError] = useState("");
  const [selectedClasses, setSelectedClasses] = useState<string[]>([]);
  const [confirmPublish, setConfirmPublish] = useState(false);
  const [assignmentInstructions, setAssignmentInstructions] = useState("");
  const [versionSummary, setVersionSummary] = useState("");
  const [archiveReason, setArchiveReason] = useState("");
  const [quizTitle, setQuizTitle] = useState(quiz.title);
  const [quizTopic, setQuizTopic] = useState(quiz.topic);
  const [quizDescription, setQuizDescription] = useState(
    quiz.description ?? "",
  );
  const [quizCocModuleId, setQuizCocModuleId] = useState(
    quiz.cocModuleId ?? "",
  );
  const [settingsErrors, setSettingsErrors] = useState<
    Record<string, string[] | undefined>
  >({});
  const [savedSettings, setSavedSettings] = useState(
    JSON.stringify([
      quiz.title,
      quiz.topic,
      quiz.description ?? "",
      quiz.cocModuleId ?? "",
    ]),
  );
  const settingsDirty =
    savedSettings !==
    JSON.stringify([quizTitle, quizTopic, quizDescription, quizCocModuleId]);
  const dirty = settingsDirty || questionDirty;
  const activeItems = [...items].sort((a, b) => a.orderIndex - b.orderIndex);
  const readiness = publicationReadiness(activeItems);
  const isDraft = version?.status === "draft" && !quiz.archivedAt;
  const canPublish =
    !!version &&
    !quiz.archivedAt &&
    version.status !== "retired" &&
    (!isDraft || readiness.ready) &&
    !dirty;
  const assignedClasses = new Set(
    assignments
      .filter(
        (assignment) =>
          assignment.versionId === version?.id &&
          assignment.status === "active",
      )
      .map((assignment) => assignment.classId),
  );
  const targets = classes.filter(
    (item) =>
      selectedClasses.includes(item.id) && !assignedClasses.has(item.id),
  );
  const relatedModule = modules.find((item) => item.id === quiz.cocModuleId);
  function openEditor(item: QuizItem | null) {
    toast.dismiss();
    setEditor({ item });
  }

  useEffect(() => {
    if (!dirty) return;
    const beforeUnload = (event: BeforeUnloadEvent) => {
      event.preventDefault();
    };
    const click = (event: MouseEvent) => {
      const link = (event.target as Element).closest?.("a[href]");
      if (
        link &&
        !link.getAttribute("href")?.startsWith("#") &&
        !window.confirm("Leave this quiz and discard unsaved changes?")
      ) {
        event.preventDefault();
        event.stopPropagation();
      }
    };
    window.addEventListener("beforeunload", beforeUnload);
    document.addEventListener("click", click, true);
    return () => {
      window.removeEventListener("beforeunload", beforeUnload);
      document.removeEventListener("click", click, true);
    };
  }, [dirty]);

  async function run(
    key: string,
    action: () => PromiseLike<{ error: { message: string } | null }>,
    message: string,
  ) {
    if (busyRef.current) return false;
    busyRef.current = true;
    setBusy(key);
    setFeedback(null);
    try {
      const { error } = await action();
      if (error) throw new Error(error.message);
      setFeedback({ error: false, text: message });
      toast.success(message);
      router.refresh();
      return true;
    } catch (error) {
      const text =
        error instanceof Error
          ? quizErrorMessage(error.message)
          : "The request failed. Your changes are still here; try again.";
      setFeedback({ error: true, text });
      toast.error(text);
      return false;
    } finally {
      busyRef.current = false;
      setBusy(null);
    }
  }
  async function saveQuestion(input: QuestionInput, id?: string) {
    if (!version || !isDraft) return false;
    return run(
      "question",
      () =>
        createClient().rpc("upsert_quiz_item", {
          p_quiz_version_id: version.id,
          p_item_type: input.itemType,
          p_prompt: input.prompt,
          p_options: input.options,
          p_correct_answer: input.correctAnswer,
          p_explanation: input.explanation || undefined,
          p_item_id: id,
        }),
      "Question saved as a draft. Review it before publishing.",
    );
  }
  async function saveMetadata(event: React.FormEvent) {
    event.preventDefault();
    const parsed = quizSchema.safeParse({
      title: quizTitle,
      topic: quizTopic,
      description: quizDescription,
      cocModuleId: quizCocModuleId,
      instructions: "",
    });
    if (!parsed.success) {
      setSettingsErrors(parsed.error.flatten().fieldErrors);
      return;
    }
    setSettingsErrors({});
    if (
      await run(
        "settings",
        () =>
          createClient().rpc("update_instructor_quiz", {
            p_quiz_id: quiz.id,
            p_title: parsed.data.title,
            p_topic: parsed.data.topic,
            p_description: parsed.data.description,
            p_coc_module_id: parsed.data.cocModuleId || undefined,
          }),
        "Quiz settings saved.",
      )
    )
      setSavedSettings(
        JSON.stringify([
          quizTitle,
          quizTopic,
          quizDescription,
          quizCocModuleId,
        ]),
      );
  }
  async function moveQuestion(index: number, direction: number) {
    if (!version) return;
    const reordered = [...activeItems];
    [reordered[index], reordered[index + direction]] = [
      reordered[index + direction],
      reordered[index],
    ];
    await run(
      "reorder",
      () =>
        createClient().rpc("reorder_quiz_items", {
          p_quiz_version_id: version.id,
          p_item_ids: reordered.map((item) => item.id),
        }),
      "Order saved. Review the reordered draft questions before publishing.",
    );
  }
  async function decide(decision: "approved" | "rejected" | "remove") {
    if (!review) return;
    if (decision !== "approved" && !reviewNote.trim()) {
      setReviewError("Enter a reason for rejection or removal.");
      return;
    }
    if (
      await run(
        "review",
        () =>
          decision === "remove"
            ? createClient().rpc("remove_quiz_item", {
                p_item_id: review.item.id,
                p_reason: reviewNote.trim(),
              })
            : createClient().rpc("review_quiz_item", {
                p_item_id: review.item.id,
                p_decision: decision,
                p_notes: reviewNote.trim() || undefined,
              }),
        decision === "remove"
          ? "Question removed; history retained."
          : `Question ${decision}.`,
      )
    )
      setReview(null);
  }
  async function publish() {
    if (!version || !canPublish || !targets.length) return;
    if (
      await run(
        "publish",
        () =>
          createClient().rpc("publish_and_assign_quiz", {
            p_quiz_version_id: version.id,
            p_class_ids: targets.map((item) => item.id),
            p_instructions: assignmentInstructions.trim() || undefined,
            p_due_at: manilaInputToUtc(quizDeadline) ?? undefined,
          }),
        `Version ${version.versionNumber} published and assigned to ${targets.map((item) => item.title).join(", ")}.`,
      )
    ) {
      setConfirmPublish(false);
      setSelectedClasses([]);
    }
  }
  return (
    <div className="space-y-4">
      <Link
        href="/quizzes"
        className="inline-flex min-h-10 items-center gap-2 text-sm text-muted-foreground hover:text-foreground"
      >
        <ArrowLeft className="h-4 w-4" aria-hidden="true" />
        Quiz library
      </Link>
      <header className="flex flex-col items-start justify-between gap-4 sm:flex-row sm:flex-wrap">
        <div className="w-full min-w-0 sm:w-auto sm:flex-1">
          <div className="flex flex-wrap items-center gap-2">
            <h1 className="break-words text-2xl font-bold tracking-tight">
              {quiz.title}
            </h1>
            <Badge
              variant={
                quiz.archivedAt ? "outline" : isDraft ? "default" : "secondary"
              }
            >
              {quiz.archivedAt ? "Archived" : (version?.status ?? "Draft")}
            </Badge>
          </div>
          <p className="mt-2 text-sm text-muted-foreground">
            {relatedModule?.code.toUpperCase() ?? "General supplementary quiz"}{" "}
            · {activeItems.length} questions · Version{" "}
            {version?.versionNumber ?? 1}
          </p>
          <p className="mt-1 text-xs text-muted-foreground" role="status">
            {busy
              ? "Saving changes…"
              : dirty
                ? "Unsaved changes"
                : "All changes saved"}
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Button
            variant="outline"
            className="min-h-11"
            onClick={() => {
              toast.dismiss();
              setPreview(true);
            }}
            disabled={busy !== null}
          >
            <Eye className="mr-2 h-4 w-4" aria-hidden="true" />
            Preview
          </Button>
          {!quiz.archivedAt ? (
            <Button
              className="min-h-11"
              onClick={() => setTab("publishing")}
              disabled={busy !== null || version?.status === "retired"}
            >
              <Send className="mr-2 h-4 w-4" aria-hidden="true" />
              {isDraft ? "Publish" : "Assign to classes"}
            </Button>
          ) : null}
        </div>
      </header>
      <p className="text-xs leading-relaxed text-muted-foreground">
        Supplementary learning quiz · separate from accredited TESDA competency
        assessment · one attempt per learner.
      </p>
      {feedback ? (
        <p
          role={feedback.error ? "alert" : "status"}
          className={`rounded-lg border p-3 text-sm ${feedback.error ? "border-destructive/40 text-destructive" : "border-border bg-muted/30"}`}
        >
          {feedback.text}
        </p>
      ) : null}
      {!hasDraft && !quiz.archivedAt ? (
        <section className="flex flex-col gap-3 rounded-lg border border-border bg-card p-3 sm:flex-row sm:items-center">
          <div className="min-w-0 flex-1">
            <p className="text-sm text-muted-foreground">
              Create a new draft to change published questions.
            </p>
          </div>
          <Button
            variant="outline"
            className="min-h-11 shrink-0"
            disabled={busy !== null}
            onClick={() =>
              run(
                "version",
                () =>
                  createClient().rpc("create_quiz_version", {
                    p_quiz_id: quiz.id,
                    p_change_summary: versionSummary.trim() || undefined,
                    p_instructions: version?.instructions || undefined,
                  }),
                "New draft created. Add and review its questions.",
              ).then((success) => {
                if (success) {
                  router.push(`/quizzes/${quiz.id}`);
                  setTab("questions");
                }
              })
            }
          >
            <Plus className="mr-2 h-4 w-4" aria-hidden="true" />
            New draft version
          </Button>
        </section>
      ) : null}
      <Tabs value={tab} onValueChange={setTab}>
        <TabsList
          aria-label="Quiz management"
          className="grid h-auto w-full grid-cols-3 gap-1 sm:flex sm:flex-wrap"
        >
          {[
            ["questions", `Questions (${items.length})`],
            ["settings", "Settings"],
            ["publishing", "Publishing"],
            ["ai", "AI assistant"],
            ["history", "History"],
            ["results", "Results"],
          ].map(([value, label]) => (
            <TabsTrigger key={value} value={value} className="min-h-10">
              {label}
            </TabsTrigger>
          ))}
        </TabsList>
        <TabsContent forceMount value="questions" className={content}>
          <section className="overflow-hidden rounded-xl border border-border bg-card">
            <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border p-4">
              <div>
                <h2 className="font-semibold">Questions</h2>
                <p className="mt-1 text-sm text-muted-foreground">
                  {readiness.approved} of {readiness.total} approved
                  {isDraft
                    ? " · review every question before publishing"
                    : " · published content is read-only"}
                </p>
              </div>
              {isDraft ? (
                <Button
                  className="min-h-11"
                  onClick={() => openEditor(null)}
                  disabled={busy !== null}
                >
                  <Plus className="mr-2 h-4 w-4" aria-hidden="true" />
                  Add question
                </Button>
              ) : null}
            </div>
            {activeItems.length ? (
              <ol className="divide-y divide-border">
                {activeItems.map((item, index) => (
                  <li key={item.id} className="p-4">
                    <article className="space-y-3">
                      <div className="flex flex-wrap items-center gap-2">
                        <span className="text-sm font-semibold text-muted-foreground">
                          {index + 1}.
                        </span>
                        <Badge variant="outline">
                          {itemTypeLabels[item.itemType]}
                        </Badge>
                        <Badge
                          variant={
                            item.reviewStatus === "approved"
                              ? "secondary"
                              : item.reviewStatus === "rejected"
                                ? "destructive"
                                : "outline"
                          }
                        >
                          {item.reviewStatus === "approved"
                            ? "Approved"
                            : item.reviewStatus === "rejected"
                              ? "Rejected"
                              : "Needs review"}
                        </Badge>
                        {item.origin === "ai_generated_draft" ? (
                          <Badge variant="outline">AI draft</Badge>
                        ) : null}
                      </div>
                      <h3 className="whitespace-pre-wrap break-words text-sm font-medium leading-relaxed">
                        {item.prompt}
                      </h3>
                      <details className="text-sm">
                        <summary className="min-h-10 cursor-pointer py-2 text-muted-foreground focus-visible:ring-2 focus-visible:ring-ring">
                          View options, answer and explanation
                        </summary>
                        <div className="mt-2 space-y-2 rounded-lg bg-muted/35 p-3">
                          {item.options.map((option, position) => (
                            <p key={position} className="break-words">
                              {String.fromCharCode(65 + position)}. {option}
                            </p>
                          ))}
                          <p className="break-words">
                            <strong>Answer:</strong> {item.correctAnswer}
                          </p>
                          {item.explanation ? (
                            <p className="whitespace-pre-wrap break-words text-muted-foreground">
                              {item.explanation}
                            </p>
                          ) : null}
                        </div>
                      </details>
                      {item.reviewNotes ? (
                        <p className="break-words text-sm text-muted-foreground">
                          Review note: {item.reviewNotes}
                        </p>
                      ) : null}
                      {isDraft ? (
                        <div className="flex flex-wrap items-center gap-2">
                          <Button
                            variant="outline"
                            className="min-h-11"
                            disabled={busy !== null}
                            onClick={() => openEditor(item)}
                            aria-label={`Edit question ${index + 1}`}
                          >
                            <Pencil
                              className="mr-2 h-4 w-4"
                              aria-hidden="true"
                            />
                            Edit
                          </Button>
                          <Button
                            variant={
                              item.reviewStatus === "approved"
                                ? "outline"
                                : "default"
                            }
                            className="min-h-11"
                            disabled={busy !== null}
                            onClick={() => {
                              setReview({ item, action: "review" });
                              setReviewNote("");
                              setReviewError("");
                            }}
                            aria-label={`Review question ${index + 1}`}
                          >
                            <Check
                              className="mr-2 h-4 w-4"
                              aria-hidden="true"
                            />
                            Review
                          </Button>
                          <Button
                            variant="ghost"
                            className="min-h-11 min-w-11"
                            disabled={busy !== null || index === 0}
                            onClick={() => moveQuestion(index, -1)}
                            aria-label={`Move question ${index + 1} up`}
                          >
                            <ArrowUp className="h-4 w-4" aria-hidden="true" />
                          </Button>
                          <Button
                            variant="ghost"
                            className="min-h-11 min-w-11"
                            disabled={
                              busy !== null || index === activeItems.length - 1
                            }
                            onClick={() => moveQuestion(index, 1)}
                            aria-label={`Move question ${index + 1} down`}
                          >
                            <ArrowDown className="h-4 w-4" aria-hidden="true" />
                          </Button>
                          <Button
                            variant="ghost"
                            className="min-h-11 min-w-11 text-destructive"
                            disabled={busy !== null}
                            onClick={() => {
                              setReview({ item, action: "remove" });
                              setReviewNote("");
                              setReviewError("");
                            }}
                            aria-label={`Remove question ${index + 1}`}
                          >
                            <Trash2 className="h-4 w-4" aria-hidden="true" />
                          </Button>
                        </div>
                      ) : null}
                    </article>
                  </li>
                ))}
              </ol>
            ) : (
              <div className="p-8 text-center">
                <p className="font-medium">Start with your first question</p>
                <p className="mt-2 text-sm text-muted-foreground">
                  Add a question manually or use the optional AI assistant.
                </p>
                {isDraft ? (
                  <Button
                    className="mt-4"
                    variant="outline"
                    onClick={() => openEditor(null)}
                  >
                    Add question
                  </Button>
                ) : null}
              </div>
            )}
          </section>
          {isDraft && readiness.ready ? (
            <div className="mt-3 flex flex-wrap items-center justify-between gap-3 rounded-lg border border-border bg-muted/30 p-3">
              <p className="text-sm">
                All questions approved. Choose the classes that will receive
                this version.
              </p>
              <Button onClick={() => setTab("publishing")}>
                Select classes
              </Button>
            </div>
          ) : null}
        </TabsContent>
        <TabsContent forceMount value="settings" className={content}>
          <section className={panel}>
            <h2 className="font-semibold">Quiz settings</h2>
            <p className="mt-1 text-sm text-muted-foreground">
              Metadata is shared across versions. Published questions and
              instructions remain unchanged.
            </p>
            <form onSubmit={saveMetadata} className="mt-5 max-w-3xl space-y-4">
              <fieldset
                disabled={busy !== null || !!quiz.archivedAt}
                className="grid gap-4 sm:grid-cols-2"
              >
                <div className="space-y-2">
                  <Label htmlFor="metadata-title">Title</Label>
                  <Input
                    id="metadata-title"
                    required
                    minLength={3}
                    maxLength={200}
                    value={quizTitle}
                    onChange={(event) => setQuizTitle(event.target.value)}
                    aria-invalid={!!settingsErrors.title}
                  />
                  {settingsErrors.title ? (
                    <p role="alert" className="text-sm text-destructive">
                      {settingsErrors.title.join(" ")}
                    </p>
                  ) : null}
                </div>
                <div className="space-y-2">
                  <Label htmlFor="metadata-topic">Topic</Label>
                  <Input
                    id="metadata-topic"
                    required
                    minLength={2}
                    maxLength={240}
                    value={quizTopic}
                    onChange={(event) => setQuizTopic(event.target.value)}
                    aria-invalid={!!settingsErrors.topic}
                  />
                  {settingsErrors.topic ? (
                    <p role="alert" className="text-sm text-destructive">
                      {settingsErrors.topic.join(" ")}
                    </p>
                  ) : null}
                </div>
                <div className="space-y-2 sm:col-span-2">
                  <Label htmlFor="metadata-coc">Related COC (optional)</Label>
                  <select
                    id="metadata-coc"
                    className="min-h-11 w-full rounded-md border border-input bg-background px-3 text-sm focus-visible:ring-2 focus-visible:ring-ring"
                    value={quizCocModuleId}
                    onChange={(event) => setQuizCocModuleId(event.target.value)}
                  >
                    <option value="">General supplementary quiz</option>
                    {modules.map((item) => (
                      <option key={item.id} value={item.id}>
                        {item.code.toUpperCase()} — {item.title}
                      </option>
                    ))}
                  </select>
                </div>
                <div className="space-y-2 sm:col-span-2">
                  <Label htmlFor="metadata-description">
                    Description (optional)
                  </Label>
                  <Textarea
                    id="metadata-description"
                    maxLength={2000}
                    rows={3}
                    value={quizDescription}
                    onChange={(event) => setQuizDescription(event.target.value)}
                  />
                </div>
              </fieldset>
              <Button
                type="submit"
                disabled={busy !== null || !settingsDirty || !!quiz.archivedAt}
              >
                {busy === "settings" ? (
                  <Loader2
                    className="mr-2 h-4 w-4 animate-spin"
                    aria-hidden="true"
                  />
                ) : null}
                Save settings
              </Button>
            </form>
          </section>
        </TabsContent>
        <TabsContent forceMount value="publishing" className={content}>
          <section className={`${panel} mb-4 space-y-4`}><h2 className="font-semibold">Class deadlines and reopening</h2><QuizDeadlineControls quizTitle={quiz.title} serverNow={serverNow ?? new Date().toISOString()} assignments={assignments.filter(a => a.status === 'active' && versions.find(v => v.id === a.versionId)?.status === 'published').map(a => ({ id: a.id, classTitle: a.classTitle, dueAt: a.dueAt ?? null }))} /></section>
          <section className={panel}>
            <h2 className="font-semibold">
              {isDraft ? "Publish to classes" : "Class assignments"}
            </h2>
            <p className="mt-1 text-sm text-muted-foreground">
              Publish an approved version and assign it together. No publication
              reason is required.
            </p>
            <div className="mt-4 grid gap-5 lg:grid-cols-[minmax(0,1fr)_minmax(240px,0.65fr)]">
              <div className="space-y-4">
                <fieldset
                  disabled={
                    busy !== null ||
                    !!quiz.archivedAt ||
                    version?.status === "retired"
                  }
                >
                  <legend className="mb-3 text-sm font-medium">
                    Target classes
                  </legend>
                  <div className="space-y-2">
                    {classes.length ? (
                      classes.map((item) => (
                        <label
                          key={item.id}
                          className="flex min-h-12 cursor-pointer items-center gap-3 rounded-lg border border-border p-3 focus-within:ring-2 focus-within:ring-ring"
                        >
                          <input
                            type="checkbox"
                            checked={
                              assignedClasses.has(item.id) ||
                              selectedClasses.includes(item.id)
                            }
                            disabled={assignedClasses.has(item.id)}
                            onChange={(event) =>
                              setSelectedClasses((current) =>
                                event.target.checked
                                  ? [...current, item.id]
                                  : current.filter((id) => id !== item.id),
                              )
                            }
                          />
                          <span className="min-w-0 flex-1 break-words text-sm">
                            {item.title}
                            {item.code ? ` (${item.code})` : ""}
                          </span>
                          {assignedClasses.has(item.id) ? (
                            <Badge variant="secondary">Assigned</Badge>
                          ) : null}
                        </label>
                      ))
                    ) : (
                      <p className="text-sm text-muted-foreground">
                        No active classes available. Create an active class
                        before publishing.
                      </p>
                    )}
                  </div>
                </fieldset>
                <div className="space-y-2">
                  <Label htmlFor="assignment-instructions">
                    Class instructions (optional)
                  </Label>
                  <Textarea
                    id="assignment-instructions"
                    rows={2}
                    maxLength={2000}
                    value={assignmentInstructions}
                    onChange={(event) =>
                      setAssignmentInstructions(event.target.value)
                    }
                    disabled={!!quiz.archivedAt}
                  />
                </div>
                <div className="space-y-2"><Label htmlFor="publish-quiz-deadline">Deadline for new assignments (optional, Asia/Manila)</Label><Input id="publish-quiz-deadline" className="min-h-11" type="datetime-local" value={quizDeadline} onChange={event => setQuizDeadline(event.target.value)} disabled={busy !== null} /><p className="text-xs text-muted-foreground">At the deadline, answering and submission close. Set class-specific deadlines above after publication.</p></div>
              </div>
              <div className="space-y-3 rounded-lg bg-muted/30 p-4">
                <h3 className="text-sm font-semibold">Publication readiness</h3>
                <p className="text-sm">
                  {readiness.approved}/{readiness.total} questions approved
                </p>
                <p className="text-sm">
                  {targets.length} new target{" "}
                  {targets.length === 1 ? "class" : "classes"}
                </p>
                <p className="text-sm">
                  One attempt per learner, shared across classes and versions.
                </p>
                {!readiness.ready && isDraft ? (
                  <p className="text-sm text-destructive">
                    {items.length
                      ? "Review all remaining draft or rejected questions."
                      : "Add and approve at least one question."}
                  </p>
                ) : null}
                {dirty ? (
                  <p className="text-sm text-destructive">
                    Save your changes before publishing.
                  </p>
                ) : null}
                {version?.status === "retired" ? (
                  <p className="text-sm text-muted-foreground">
                    This version is retired. Select the current version in
                    History.
                  </p>
                ) : null}
                <Button
                  className="min-h-11 w-full"
                  disabled={busy !== null || !canPublish || !targets.length}
                  onClick={() => setConfirmPublish(true)}
                >
                  <Send className="mr-2 h-4 w-4" aria-hidden="true" />
                  {isDraft ? "Review & publish" : "Confirm assignments"}
                </Button>
              </div>
            </div>
            {assignments.length ? (
              <div className="mt-5 border-t border-border pt-4">
                <h3 className="text-sm font-semibold">Assignment history</h3>
                <ul className="mt-2 space-y-2">
                  {assignments.map((assignment) => (
                    <li
                      key={assignment.id}
                      className="flex flex-wrap items-center gap-2 text-sm"
                    >
                      <span>{assignment.classTitle}</span>
                      <span className="text-muted-foreground">
                        · v
                        {
                          versions.find(
                            (item) => item.id === assignment.versionId,
                          )?.versionNumber
                        }
                      </span>
                      <Badge variant="outline">{assignment.status}</Badge>
                    </li>
                  ))}
                </ul>
              </div>
            ) : null}
          </section>
        </TabsContent>
        <TabsContent forceMount value="ai" className={content}>
          <section className={panel}>
            {isDraft && version ? (
              <AiQuizPanel
                classes={classes}
                version={version}
                grounding={grounding}
                topic={quiz.topic}
                items={activeItems}
              />
            ) : (
              <p className="text-sm text-muted-foreground">
                Open a draft version to generate editable AI questions. Manual
                authoring does not require AI or source context.
              </p>
            )}
          </section>
        </TabsContent>
        <TabsContent forceMount value="history" className={content}>
          <section className={panel}>
            <h2 className="font-semibold">Version history</h2>
            {!hasDraft && !quiz.archivedAt ? (
              <div className="mt-4 max-w-xl space-y-2">
                <Label htmlFor="version-summary">
                  Next version change summary (optional)
                </Label>
                <Input
                  id="version-summary"
                  value={versionSummary}
                  onChange={(event) => setVersionSummary(event.target.value)}
                  placeholder="Describe the changes in your next draft"
                />
              </div>
            ) : null}
            <p className="mt-1 text-sm text-muted-foreground">
              Published and retired questions remain immutable. Select a version
              to inspect its questions.
            </p>
            <ul className="mt-4 divide-y divide-border">
              {versions.map((item) => (
                <li
                  key={item.id}
                  className="flex flex-wrap items-center justify-between gap-3 py-3"
                >
                  <div className="min-w-0">
                    <Link
                      className="font-medium text-primary underline-offset-4 hover:underline"
                      href={`/quizzes/${quiz.id}?version=${item.id}`}
                    >
                      Version {item.versionNumber}
                      {item.id === version?.id ? " (viewing)" : ""}
                    </Link>
                    <p className="mt-1 break-words text-sm text-muted-foreground">
                      {item.changeSummary || "No change summary recorded"}
                    </p>
                    {item.publishedAt ? (
                      <p className="text-xs text-muted-foreground">
                        Published {new Date(item.publishedAt).toLocaleString()}
                      </p>
                    ) : null}
                  </div>
                  <Badge variant="outline">{item.status}</Badge>
                </li>
              ))}
            </ul>
          </section>
          {!quiz.archivedAt ? (
            <details className={`${panel} mt-4`}>
              <summary className="cursor-pointer text-sm font-medium">
                Archive quiz
              </summary>
              <p className="mt-3 text-sm text-muted-foreground">
                Retains every version, attempt, result and audit event. Learners
                lose access to active assignments.
              </p>
              <Label className="mt-4 block" htmlFor="archive-reason">
                Archive reason (required)
              </Label>
              <Input
                className="mt-2"
                id="archive-reason"
                value={archiveReason}
                onChange={(event) => setArchiveReason(event.target.value)}
              />
              <Button
                variant="outline"
                className="mt-3 text-destructive"
                disabled={busy !== null || !archiveReason.trim()}
                onClick={() => {
                  if (
                    window.confirm(
                      "Archive this quiz and restrict access to its assignments? History will be retained.",
                    )
                  )
                    run(
                      "archive",
                      () =>
                        createClient().rpc("archive_instructor_quiz", {
                          p_quiz_id: quiz.id,
                          p_reason: archiveReason.trim(),
                        }),
                      "Quiz archived; history retained.",
                    );
                }}
              >
                Archive quiz
              </Button>
            </details>
          ) : null}
        </TabsContent>
        <TabsContent forceMount value="results" className={content}>
          <section className={panel}>
            <h2 className="font-semibold">Learner results</h2>
            <p className="mt-1 text-sm text-muted-foreground">
              Supplementary scores across all versions. Historical results are
              retained.
            </p>
            {results.length ? (
              <ul className="mt-4 divide-y divide-border">
                {results.map((result) => (
                  <li
                    key={result.id}
                    className="flex flex-wrap items-center justify-between gap-3 py-3"
                  >
                    <div className="min-w-0">
                      <p className="break-words text-sm font-medium">
                        {result.learner}
                      </p>
                      <p className="text-xs text-muted-foreground">
                        {result.classTitle} · v{result.versionNumber}
                      </p>
                    </div>
                    <div className="text-sm">
                      <p>
                        {result.correctCount !== null
                          ? `${result.correctCount}/${result.questionCount} · Submitted — Attempt used`
                          : result.status === "in_progress"
                            ? "In progress — Continue attempt"
                            : "Submitted — Attempt used"}
                      </p>
                      {result.completedAt ? (
                        <p className="text-xs text-muted-foreground">
                          {new Date(result.completedAt).toLocaleString()}
                        </p>
                      ) : null}
                    </div>
                  </li>
                ))}
              </ul>
            ) : (
              <p className="mt-5 text-sm text-muted-foreground">
                No learner attempts yet. Published assignments appear in
                enrolled learners’ quizzes.
              </p>
            )}
          </section>
        </TabsContent>
      </Tabs>
      {editor ? (
        <QuestionEditor
          item={editor.item}
          onClose={() => setEditor(null)}
          onSave={saveQuestion}
          onDirtyChange={setQuestionDirty}
        />
      ) : null}
      {preview ? (
        <QuizPreview
          title={quiz.title}
          instructions={version?.instructions}
          items={activeItems}
          onClose={() => setPreview(false)}
        />
      ) : null}
      <Dialog
        open={!!review}
        onOpenChange={(open) => {
          if (!open && !busy) setReview(null);
        }}
      >
        <DialogContent className="max-h-[90dvh] max-w-2xl overflow-y-auto">
          <DialogHeader>
            <DialogTitle>
              {review?.action === "remove"
                ? "Remove draft question"
                : "Review question"}
            </DialogTitle>
            <DialogDescription>
              {review?.action === "remove"
                ? "The question is removed from this draft; audit history is retained."
                : "Verify the question, answer and explanation before approval."}
            </DialogDescription>
          </DialogHeader>
          {review ? (
            <>
              <p className="whitespace-pre-wrap break-words text-sm font-medium">
                {review.item.prompt}
              </p>
              {review.item.options.map((option, index) => (
                <p key={index} className="break-words text-sm">
                  {String.fromCharCode(65 + index)}. {option}
                </p>
              ))}
              <p className="break-words text-sm">
                <strong>Answer:</strong> {review.item.correctAnswer}
              </p>
              {review.item.explanation ? (
                <p className="break-words text-sm text-muted-foreground">
                  {review.item.explanation}
                </p>
              ) : null}
              <div className="space-y-2">
                <Label htmlFor="review-note">
                  Review note{" "}
                  {review.action === "remove"
                    ? "(required)"
                    : "(required for rejection)"}
                </Label>
                <Textarea
                  id="review-note"
                  rows={2}
                  value={reviewNote}
                  onChange={(event) => setReviewNote(event.target.value)}
                  aria-invalid={!!reviewError}
                  aria-describedby={reviewError ? "review-error" : undefined}
                />
                {reviewError ? (
                  <p
                    id="review-error"
                    role="alert"
                    className="text-sm text-destructive"
                  >
                    {reviewError}
                  </p>
                ) : null}
              </div>
              <div className="flex flex-wrap justify-end gap-2">
                <Button
                  variant="outline"
                  disabled={busy !== null}
                  onClick={() => setReview(null)}
                >
                  Cancel
                </Button>
                {review.action === "remove" ? (
                  <Button
                    variant="destructive"
                    disabled={busy !== null}
                    onClick={() => decide("remove")}
                  >
                    Remove question
                  </Button>
                ) : (
                  <>
                    <Button
                      variant="outline"
                      disabled={busy !== null}
                      onClick={() => decide("rejected")}
                    >
                      Reject
                    </Button>
                    <Button
                      disabled={busy !== null}
                      onClick={() => decide("approved")}
                    >
                      Approve question
                    </Button>
                  </>
                )}
              </div>
            </>
          ) : null}
        </DialogContent>
      </Dialog>
      <Dialog
        open={confirmPublish}
        onOpenChange={(open) => {
          if (!busy) setConfirmPublish(open);
        }}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>
              {isDraft
                ? "Publish this version?"
                : "Assign this published version?"}
            </DialogTitle>
            <DialogDescription>
              Version {version?.versionNumber} of {quiz.title} will be available
              to enrolled learners in the selected classes.
            </DialogDescription>
          </DialogHeader>
          <ul className="list-inside list-disc text-sm">
            {targets.map((item) => (
              <li key={item.id}>{item.title}</li>
            ))}
          </ul>
          <p className="text-sm text-muted-foreground">
            Each learner has one attempt for this quiz. Republishing or
            assigning another class does not grant another attempt.
          </p>
          <div className="flex justify-end gap-2">
            <Button
              variant="outline"
              disabled={busy !== null}
              onClick={() => setConfirmPublish(false)}
            >
              Cancel
            </Button>
            <Button
              disabled={busy !== null || !canPublish || !targets.length}
              onClick={publish}
            >
              {busy === "publish" ? (
                <Loader2
                  className="mr-2 h-4 w-4 animate-spin"
                  aria-hidden="true"
                />
              ) : null}
              {isDraft ? "Publish quiz" : "Assign quiz"}
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
}
