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
  difficultyLabels,
  itemTypeLabels,
  publicationReadiness,
  quizErrorMessage,
  quizTypeLabels,
  toRpcRubric,
  type QuestionInput,
  type QuizItem,
} from "@/lib/quizzes/authoring";
import { scopeSummary, type CurriculumCatalog } from "@/lib/quizzes/curriculum";
import {
  formFromQuiz,
  parseQuizForm,
  quizSettingsRpcArgs,
  scopeError,
  type QuizFormState,
} from "@/lib/quizzes/form";
import {
  quizDb,
  type QuizDifficulty,
  type QuizType,
  type ResultReleaseMode,
} from "@/lib/quizzes/types";
import { QuestionEditor } from "./QuestionEditor";
import { QuizPreview } from "./QuizPreview";
import { QuizDeadlineControls } from "./QuizDeadlineControls";
import { QuizCurriculumFields } from "./QuizCurriculumFields";
import { QuizResultsPanel, type ResultAttempt } from "./QuizResultsPanel";
import { manilaInputToUtc } from "@/lib/activities/dates";
import { AiQuizPanel, type QuizGroundingCatalog } from "./AiQuizPanel";

interface Version {
  id: string;
  versionNumber: number;
  status: "draft" | "published" | "retired";
  instructions: string | null;
  changeSummary?: string | null;
  publishedAt?: string | null;
  timeLimitMinutes?: number | null;
  resultReleaseMode?: ResultReleaseMode;
}
interface Assignment {
  id: string;
  classId: string;
  versionId: string;
  status: string;
  classTitle: string;
  dueAt?: string | null;
}
export interface QuizCurriculum {
  focus: string | null;
  quizType: QuizType | null;
  difficulty: QuizDifficulty | null;
  topicId: string | null;
  moduleIds: string[];
  outcomeIds: string[];
}
export interface QuizWorkspaceProps {
  initialTab?: string;
  initialAttemptId?: string;
  serverNow?: string;
  quiz: {
    id: string;
    title: string;
    topic: string;
    description: string | null;
    cocModuleId: string | null;
    archivedAt: string | null;
  };
  curriculum: QuizCurriculum;
  catalog: CurriculumCatalog;
  version: Version | null;
  items: QuizItem[];
  hasDraft: boolean;
  classes: { id: string; title: string; code: string | null }[];
  grounding: QuizGroundingCatalog | null;
  versions: Version[];
  assignments: Assignment[];
  results: ResultAttempt[];
  enrolled: number;
}
const panel = "rounded-xl border border-border bg-card p-4 sm:p-5";
const content = "mt-4 data-[state=inactive]:hidden";
const tabs = ["questions", "settings", "publishing", "ai", "history", "results"] as const;

export function QuizAuthoringWorkspace({
  quiz,
  curriculum,
  catalog,
  version,
  items,
  hasDraft,
  classes,
  grounding,
  versions,
  assignments,
  results,
  enrolled,
  initialTab,
  initialAttemptId,
  serverNow,
}: QuizWorkspaceProps) {
  const router = useRouter();
  const [tab, setTab] = useState<string>(
    tabs.includes(initialTab as (typeof tabs)[number]) ? (initialTab as string) : "questions",
  );
  const [quizDeadline, setQuizDeadline] = useState("");
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
  const draftVersion = versions.find((item) => item.status === "draft") ?? null;
  // Settings edits apply to the draft; without one they must match the latest version.
  const latestVersion = [...versions].sort((a, b) => b.versionNumber - a.versionNumber)[0];
  const settingsVersion = draftVersion ?? latestVersion ?? version;
  const initialForm = formFromQuiz({
    title: quiz.title,
    description: quiz.description,
    cocModuleId: quiz.cocModuleId,
    moduleIds: curriculum.moduleIds,
    topicId: curriculum.topicId,
    outcomeIds: curriculum.outcomeIds,
    focus: curriculum.focus,
    quizType: curriculum.quizType,
    difficulty: curriculum.difficulty,
    instructions: settingsVersion?.instructions ?? null,
    timeLimitMinutes: settingsVersion?.timeLimitMinutes ?? null,
    resultReleaseMode: settingsVersion?.resultReleaseMode ?? "immediate",
  });
  const [form, setForm] = useState<QuizFormState>(initialForm);
  const [savedForm, setSavedForm] = useState(JSON.stringify(initialForm));
  const [settingsErrors, setSettingsErrors] = useState<
    Record<string, string[] | undefined>
  >({});
  const settingsDirty = savedForm !== JSON.stringify(form);
  const dirty = settingsDirty || questionDirty;
  const activeItems = [...items].sort((a, b) => a.orderIndex - b.orderIndex);
  const readiness = publicationReadiness(activeItems);
  const isDraft = version?.status === "draft" && !quiz.archivedAt;
  const mapped = !!quiz.cocModuleId && !!curriculum.focus;
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
  function openEditor(item: QuizItem | null) {
    toast.dismiss();
    setEditor({ item });
  }
  function changeTab(value: string) {
    setTab(value);
    const url = new URL(window.location.href);
    url.searchParams.set("tab", value);
    if (value !== "results") url.searchParams.delete("attempt");
    window.history.replaceState(window.history.state, "", url);
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
    const essay = input.itemType === "scenario_essay";
    return run(
      "question",
      () =>
        quizDb(createClient()).rpc("upsert_quiz_item", {
          p_quiz_version_id: version.id,
          p_item_type: input.itemType,
          p_prompt: input.prompt,
          p_options: input.options,
          p_correct_answer: input.correctAnswer,
          p_explanation: input.explanation || null,
          p_item_id: id ?? null,
          p_points: essay ? null : input.points,
          p_rubric: essay ? toRpcRubric(input.rubric) : null,
          p_scenario: essay ? input.scenario : null,
          p_min_words: essay ? input.minWords : null,
          p_max_words: essay ? input.maxWords : null,
        }),
      "Question saved as a draft. Review it before publishing.",
    );
  }
  async function saveSettings(event: React.FormEvent) {
    event.preventDefault();
    const parsed = parseQuizForm(form);
    const scope = scopeError(form);
    if (!parsed.success || scope) {
      setSettingsErrors({
        ...(parsed.success ? {} : parsed.error.flatten().fieldErrors),
        ...(scope ? { moduleIds: [scope] } : {}),
      });
      return;
    }
    setSettingsErrors({});
    if (
      await run(
        "settings",
        () =>
          quizDb(createClient()).rpc("update_instructor_quiz", {
            p_quiz_id: quiz.id,
            ...quizSettingsRpcArgs(parsed.data, catalog),
          }),
        "Quiz curriculum and settings saved.",
      )
    )
      setSavedForm(JSON.stringify(form));
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
  const releaseLabel =
    (settingsVersion?.resultReleaseMode ?? "immediate") === "instructor_release" ||
    readiness.essays > 0
      ? "Instructor release"
      : "Immediate results";
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
            {!mapped ? <Badge variant="outline">Not mapped to a module</Badge> : null}
          </div>
          <p className="mt-2 text-sm text-muted-foreground">
            {scopeSummary(catalog, quiz.cocModuleId, curriculum.moduleIds)} ·{" "}
            {activeItems.length} questions · Version{" "}
            {version?.versionNumber ?? 1}
            {curriculum.quizType ? ` · ${quizTypeLabels[curriculum.quizType]}` : ""}
            {curriculum.difficulty ? ` · ${difficultyLabels[curriculum.difficulty]}` : ""}
            {settingsVersion?.timeLimitMinutes ? ` · ${settingsVersion.timeLimitMinutes}-minute limit` : ""}
            {` · ${releaseLabel}`}
          </p>
          {curriculum.focus ? (
            <p className="mt-1 break-words text-sm">
              <span className="font-medium">Focus:</span> {curriculum.focus}
            </p>
          ) : null}
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
              onClick={() => changeTab("publishing")}
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
        assessment · one attempt per learner · saved answers are submitted
        automatically at the deadline or time limit.
      </p>
      {!mapped && !quiz.archivedAt ? (
        <p className="rounded-lg border border-amber-300 bg-amber-50 p-3 text-sm text-amber-950">
          This quiz was created before curriculum mapping. Open Settings to
          choose its COC, modules, learning outcomes and focus.
        </p>
      ) : null}
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
              Create a new draft to change published questions, instructions,
              the time limit or the release mode.
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
      <Tabs value={tab} onValueChange={changeTab}>
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
            ["results", `Results (${results.filter((item) => item.status === "completed").length})`],
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
                  {readiness.essays
                    ? ` · ${readiness.essays} scenario essay${readiness.essays === 1 ? "" : "s"} (instructor release)`
                    : ""}
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
                        <Badge variant="outline">
                          {item.points ?? 1} pt{(item.points ?? 1) === 1 ? "" : "s"}
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
                      {item.scenario ? (
                        <p className="whitespace-pre-wrap break-words rounded-md bg-muted/35 p-3 text-sm">
                          <span className="font-medium">Scenario:</span>{" "}
                          {item.scenario}
                        </p>
                      ) : null}
                      <h3 className="whitespace-pre-wrap break-words text-sm font-medium leading-relaxed">
                        {item.prompt}
                      </h3>
                      <details className="text-sm">
                        <summary className="min-h-10 cursor-pointer py-2 text-muted-foreground focus-visible:ring-2 focus-visible:ring-ring">
                          {item.itemType === "scenario_essay"
                            ? "View rubric and scoring guide"
                            : "View options, answer and explanation"}
                        </summary>
                        <div className="mt-2 space-y-2 rounded-lg bg-muted/35 p-3">
                          {item.itemType === "scenario_essay" ? (
                            <>
                              <ul className="space-y-1">
                                {(item.rubric ?? []).map((row) => (
                                  <li key={row.id} className="break-words">
                                    <strong>{row.criterion}</strong> ({row.maxPoints} pts)
                                    {row.description ? ` — ${row.description}` : ""}
                                  </li>
                                ))}
                              </ul>
                              {item.minWords || item.maxWords ? (
                                <p className="text-muted-foreground">
                                  Word guidance: {item.minWords ?? "—"} to {item.maxWords ?? "—"} words
                                </p>
                              ) : null}
                              {item.correctAnswer ? (
                                <p className="break-words">
                                  <strong>Scoring guide:</strong> {item.correctAnswer}
                                </p>
                              ) : null}
                            </>
                          ) : (
                            <>
                              {item.options.map((option, position) => (
                                <p key={position} className="break-words">
                                  {String.fromCharCode(65 + position)}. {option}
                                </p>
                              ))}
                              <p className="break-words">
                                <strong>Answer:</strong> {item.correctAnswer}
                              </p>
                            </>
                          )}
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
              <Button onClick={() => changeTab("publishing")}>
                Select classes
              </Button>
            </div>
          ) : null}
        </TabsContent>
        <TabsContent forceMount value="settings" className={content}>
          <section className={panel}>
            <h2 className="font-semibold">Curriculum and settings</h2>
            <p className="mt-1 text-sm text-muted-foreground">
              Curriculum placement and focus are shared across versions.
              Instructions, time limit and release mode belong to the draft
              version; published versions keep theirs.
            </p>
            <form onSubmit={saveSettings} className="mt-5 max-w-3xl space-y-4" noValidate>
              <QuizCurriculumFields
                idPrefix="quiz-settings"
                catalog={catalog}
                value={form}
                onChange={setForm}
                errors={settingsErrors}
                disabled={busy !== null || !!quiz.archivedAt}
                settingsLocked={!draftVersion}
                hasEssays={readiness.essays > 0}
              />
              <Button
                type="submit"
                className="min-h-11"
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
          <section className={`${panel} mb-4 space-y-4`}>
            <h2 className="font-semibold">Class deadlines, closing and reopening</h2>
            <QuizDeadlineControls
              quizTitle={quiz.title}
              serverNow={serverNow ?? new Date().toISOString()}
              assignments={assignments
                .filter(
                  (a) =>
                    a.status === "active" &&
                    versions.find((v) => v.id === a.versionId)?.status === "published",
                )
                .map((a) => ({ id: a.id, classTitle: a.classTitle, dueAt: a.dueAt ?? null }))}
            />
          </section>
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
                <div className="space-y-2">
                  <Label htmlFor="publish-quiz-deadline">
                    Deadline for new assignments (optional, Asia/Manila)
                  </Label>
                  <Input
                    id="publish-quiz-deadline"
                    className="min-h-11"
                    type="datetime-local"
                    value={quizDeadline}
                    onChange={(event) => setQuizDeadline(event.target.value)}
                    disabled={busy !== null}
                  />
                  <p className="text-xs text-muted-foreground">
                    At the deadline, answering closes and saved answers are
                    submitted automatically. Set class-specific deadlines above
                    after publication.
                  </p>
                </div>
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
                {readiness.essays ? (
                  <p className="text-sm">
                    Includes scenario essays: results are released by you after
                    scoring and finalization.
                  </p>
                ) : null}
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
                focus={curriculum.focus}
                mapped={mapped}
                quizDifficulty={curriculum.difficulty}
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
                    <p className="text-xs text-muted-foreground">
                      {item.timeLimitMinutes ? `${item.timeLimitMinutes}-minute limit · ` : "No time limit · "}
                      {item.resultReleaseMode === "instructor_release" ? "Instructor release" : "Immediate results"}
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
              Supplementary scores across all versions. Averages use final
              scores only; attempts awaiting evaluation are counted separately.
            </p>
            <div className="mt-4">
              <QuizResultsPanel
                attempts={results}
                enrolled={enrolled}
                initialAttemptId={initialAttemptId}
              />
            </div>
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
              {review.item.scenario ? (
                <p className="whitespace-pre-wrap break-words text-sm">
                  <strong>Scenario:</strong> {review.item.scenario}
                </p>
              ) : null}
              <p className="whitespace-pre-wrap break-words text-sm font-medium">
                {review.item.prompt}
              </p>
              {review.item.itemType === "scenario_essay" ? (
                <ul className="space-y-1 text-sm">
                  {(review.item.rubric ?? []).map((row) => (
                    <li key={row.id} className="break-words">
                      <strong>{row.criterion}</strong> ({row.maxPoints} pts)
                      {row.description ? ` — ${row.description}` : ""}
                    </li>
                  ))}
                </ul>
              ) : (
                <>
                  {review.item.options.map((option, index) => (
                    <p key={index} className="break-words text-sm">
                      {String.fromCharCode(65 + index)}. {option}
                    </p>
                  ))}
                  <p className="break-words text-sm">
                    <strong>Answer:</strong> {review.item.correctAnswer}
                  </p>
                </>
              )}
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
            {readiness.essays
              ? " Essays force instructor release: learners see “Awaiting instructor evaluation” until you release results."
              : ""}
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
