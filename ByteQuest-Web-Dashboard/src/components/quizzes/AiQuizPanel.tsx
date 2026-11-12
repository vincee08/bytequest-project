"use client";
import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Loader2, Sparkles, RefreshCw } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  itemTypeLabels,
  type ItemType,
  type QuizItem,
} from "@/lib/quizzes/authoring";
import { buildAlternativeQuizDraftRequest } from "@/lib/ai/alternative-quiz-draft";
export interface QuizGroundingCatalog {
  source: { title: string; edition: string };
  coc: { id: string; code: string; title: string };
  competency: { code: string; title: string };
  module: { title: string; version: number };
  activities: Array<{
    id: string;
    title: string;
    missionNumber: number;
    missionTitle: string;
    learningOutcome: string;
  }>;
}
export function AiQuizPanel({
  version,
  grounding,
  topic,
  items,
  classes,
}: {
  version: { id: string };
  grounding: QuizGroundingCatalog | null;
  topic: string;
  items: QuizItem[];
  classes: { id: string; title: string; code: string | null }[];
}) {
  const router = useRouter();
  const isDraft = true;
  const [sourceMode, setSourceMode] = useState<
    "approved_coc" | "class_resource"
  >("approved_coc");
  const [classId, setClassId] = useState(classes[0]?.id ?? "");
  const [resourceId, setResourceId] = useState("");
  const [resources, setResources] = useState<
    {
      id: string;
      title: string;
      mime_type: string | null;
      size_bytes: number | null;
    }[]
  >([]);
  const [loadingResources, setLoadingResources] = useState(false);
  const [resourceError, setResourceError] = useState<string | null>(null);
  const [resourceRefresh, setResourceRefresh] = useState(0);
  const [consent, setConsent] = useState(false);
  const [configuration, setConfiguration] = useState<{
    configured: boolean;
    simulated?: boolean;
  } | null>(null);
  const busyRef = useRef(false);
  const requestRef = useRef<{ body: string; id: string } | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [aiTopic, setAiTopic] = useState(topic);
  const [aiActivityVersionId, setAiActivityVersionId] = useState(
    grounding?.activities[0]?.id ?? "",
  );
  const [aiInstructorContext, setAiInstructorContext] = useState("");
  const [aiError, setAiError] = useState<string | null>(null);
  const [difficulty, setDifficulty] = useState<
    "foundation" | "intermediate" | "advanced"
  >("foundation");
  const [itemCount, setItemCount] = useState(5);
  const [aiTypes, setAiTypes] = useState<ItemType[]>(["multiple_choice"]);
  useEffect(() => {
    const controller = new AbortController();
    fetch("/api/instructor/quizzes/ai-draft", {
      signal: controller.signal,
      cache: "no-store",
    })
      .then((response) => (response.ok ? response.json() : Promise.reject()))
      .then(setConfiguration)
      .catch(() => {
        if (!controller.signal.aborted) setConfiguration({ configured: false });
      });
    return () => controller.abort();
  }, [resourceRefresh]);
  useEffect(() => {
    if (!classId || sourceMode !== "class_resource") return;
    const controller = new AbortController();
    setLoadingResources(true);
    setResourceError(null);
    fetch(`/api/classes/${classId}/resources`, {
      signal: controller.signal,
      cache: "no-store",
    })
      .then(async (response) => {
        const result = await response.json();
        if (!response.ok)
          throw new Error(result.error || "Resources could not be loaded.");
        return result;
      })
      .then((result) => {
        setResources(result.resources);
        setResourceId((current) =>
          result.resources.some((item: { id: string }) => item.id === current)
            ? current
            : "",
        );
      })
      .catch((error) => {
        if (!controller.signal.aborted) {
          setResources([]);
          setResourceError(
            error instanceof Error
              ? error.message
              : "Resources could not be loaded.",
          );
        }
      })
      .finally(() => {
        if (!controller.signal.aborted) setLoadingResources(false);
      });
    return () => controller.abort();
  }, [classId, sourceMode, resourceRefresh]);
  const selectedResource = resources.find((item) => item.id === resourceId);
  const disabledReason = !configuration
    ? "Checking AI availability…"
    : !configuration.configured
      ? "OpenRouter is not configured locally. Ask the administrator to add the local AI key; manual authoring remains available."
      : sourceMode === "approved_coc" && (!grounding || !aiActivityVersionId)
        ? "Select and save a COC with complete approved content, or choose My Class Resource."
        : sourceMode === "class_resource" && loadingResources
          ? "Loading class resources…"
          : sourceMode === "class_resource" && !selectedResource
            ? "Choose a PDF from your active class."
            : sourceMode === "class_resource" &&
                (selectedResource?.mime_type !== "application/pdf" ||
                  (selectedResource?.size_bytes ?? Infinity) > 10 * 1024 * 1024)
              ? "Choose a text PDF up to 10 MB. Images and videos cannot be read for AI generation."
              : !consent
                ? "Confirm that the selected content may be sent to OpenRouter."
                : aiTopic.trim().length < 2
                  ? "Enter a quiz focus with at least 2 characters."
                  : !Number.isInteger(itemCount) ||
                      itemCount < 1 ||
                      itemCount > 10
                    ? "Choose 1 to 10 questions."
                    : aiTypes.length === 0
                      ? "Select at least one question type."
                      : null;
  function sourceRequest() {
    return {
      sourceMode,
      externalConsent: consent,
      ...(sourceMode === "class_resource"
        ? { classId, resourceId }
        : { activityVersionId: aiActivityVersionId }),
    };
  }
  function withRequestId(body: object) {
    const serialized = JSON.stringify(body);
    if (requestRef.current?.body !== serialized)
      requestRef.current = { body: serialized, id: crypto.randomUUID() };
    return { ...body, requestId: requestRef.current!.id };
  }
  useEffect(() => {
    setAiActivityVersionId((current) =>
      grounding?.activities.some((activity) => activity.id === current)
        ? current
        : (grounding?.activities[0]?.id ?? ""),
    );
  }, [grounding]);
  async function generateAiDraft(event: React.FormEvent) {
    event.preventDefault();
    if (busyRef.current || disabledReason || !version || !isDraft) return;
    busyRef.current = true;
    setAiError(null);
    setBusy("ai");
    try {
      const response = await fetch("/api/instructor/quizzes/ai-draft", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(
          withRequestId({
            quizVersionId: version.id,
            ...sourceRequest(),
            topic: aiTopic,
            instructorContext: aiInstructorContext.trim() || undefined,
            difficulty,
            itemCount,
            itemTypes: aiTypes,
          }),
        ),
      });
      const result = (await response.json().catch(() => null)) as {
        error?: string;
        generatedCount?: number;
      } | null;
      if (!response.ok) {
        if (response.status !== 409) requestRef.current = null;
        const message =
          result?.error ||
          "AI draft generation failed without publishing any item.";
        setAiError(message);
        toast.error(message);
      } else {
        requestRef.current = null;
        toast.success(
          `${result?.generatedCount ?? itemCount} AI-generated draft items require your review.`,
        );
        router.refresh();
      }
    } catch {
      const message =
        "The AI service could not be reached. Manual quiz creation is still available.";
      setAiError(message);
      toast.error(message);
    } finally {
      busyRef.current = false;
      setBusy(null);
    }
  }

  async function regenerateAiItem(item: QuizItem) {
    if (
      busyRef.current ||
      disabledReason ||
      !version ||
      !isDraft ||
      item.origin !== "ai_generated_draft" ||
      (sourceMode === "approved_coc" && !aiActivityVersionId)
    )
      return;
    busyRef.current = true;
    setAiError(null);
    setBusy(`regenerate-${item.id}`);
    try {
      const response = await fetch("/api/instructor/quizzes/ai-draft", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(
          withRequestId({
            ...buildAlternativeQuizDraftRequest({
              sourceMode,
              quizVersionId: version.id,
              activityVersionId: aiActivityVersionId,
              topic: aiTopic,
              instructorContext: aiInstructorContext,
              difficulty,
              itemType: item.itemType,
              originalPrompt: item.prompt,
            }),
            ...sourceRequest(),
            activityVersionId:
              sourceMode === "class_resource" ? undefined : aiActivityVersionId,
          }),
        ),
      });
      const result = (await response.json().catch(() => null)) as {
        error?: string;
      } | null;
      if (!response.ok) {
        if (response.status !== 409) requestRef.current = null;
        const message =
          result?.error ||
          "The alternative question could not be generated. The original draft was kept.";
        setAiError(message);
        toast.error(message);
      } else {
        requestRef.current = null;
        toast.success(
          "A separate AI alternative was added as a draft. Review it before removing the original.",
        );
        router.refresh();
      }
    } catch {
      const message =
        "The AI service could not be reached. The original draft was kept.";
      setAiError(message);
      toast.error(message);
    } finally {
      busyRef.current = false;
      setBusy(null);
    }
  }

  return (
    <div className="max-w-3xl space-y-5">
      <section className="space-y-1">
        <div className="flex items-center gap-2">
          <Sparkles className="h-5 w-5 text-primary" aria-hidden="true" />
          <h2 className="font-semibold">Generate with AI</h2>
        </div>
        <p className="mt-2 text-sm leading-relaxed text-muted-foreground">
          Choose approved COC content or a PDF from your class. Every result
          stays an editable draft until an Instructor reviews and approves it.
        </p>

        <fieldset className="mt-4" disabled={busy !== null}>
          <legend className="mb-2 text-sm font-medium">Source</legend>
          <div className="grid gap-2 sm:grid-cols-2">
            {(
              [
                ["approved_coc", "Approved COC Content"],
                ["class_resource", "My Class Resource"],
              ] as const
            ).map(([value, label]) => (
              <label
                key={value}
                className={`flex min-h-11 cursor-pointer items-center gap-2 rounded-lg border p-3 text-sm ${sourceMode === value ? "border-primary bg-primary/5" : "border-border"}`}
              >
                <input
                  type="radio"
                  name="ai-source"
                  value={value}
                  checked={sourceMode === value}
                  onChange={() => {
                    setSourceMode(value);
                    setConsent(false);
                    setAiError(null);
                  }}
                  className="accent-primary"
                />
                {label}
              </label>
            ))}
          </div>
        </fieldset>
        {sourceMode === "approved_coc" &&
          (grounding ? (
            <div className="mt-4 rounded-lg border border-border bg-muted/35 p-3 text-xs leading-relaxed">
              <p className="font-semibold text-foreground">
                {grounding.coc.code.toUpperCase()} · {grounding.competency.code}
              </p>
              <p className="mt-1 text-muted-foreground">
                {grounding.source.title} · {grounding.source.edition}
              </p>
            </div>
          ) : (
            <div className="mt-4 rounded-lg border border-amber-300 bg-amber-50 p-3 text-sm text-amber-950">
              Select and save a related COC with complete approved source
              content before generating AI drafts. Manual authoring remains
              available.
            </div>
          ))}

        <form onSubmit={generateAiDraft} className="mt-5 space-y-4">
          <fieldset disabled={busy !== null} className="space-y-4">
            {sourceMode === "class_resource" ? (
              <div className="space-y-4">
                <p className="text-sm text-muted-foreground">
                  Class resources create supplementary learning quizzes. They do
                  not become approved COC or TESDA sources.
                </p>
                <div className="space-y-2">
                  <Label htmlFor="ai-class">Class</Label>
                  <select
                    id="ai-class"
                    value={classId}
                    onChange={(event) => {
                      setClassId(event.target.value);
                      setResourceId("");
                      setResources([]);
                      setConsent(false);
                    }}
                    className="min-h-11 w-full rounded-md border border-input bg-background px-3 text-sm"
                  >
                    <option value="">Select a class</option>
                    {classes.map((item) => (
                      <option key={item.id} value={item.id}>
                        {item.title}
                      </option>
                    ))}
                  </select>
                </div>
                <div className="space-y-2">
                  <Label htmlFor="ai-resource">Uploaded resource</Label>
                  <select
                    id="ai-resource"
                    value={resourceId}
                    disabled={loadingResources || !classId}
                    onChange={(event) => {
                      setResourceId(event.target.value);
                      setConsent(false);
                    }}
                    className="min-h-11 w-full rounded-md border border-input bg-background px-3 text-sm"
                  >
                    <option value="">
                      {loadingResources
                        ? "Loading resources…"
                        : "Select a text PDF"}
                    </option>
                    {resources.map((item) => (
                      <option
                        key={item.id}
                        value={item.id}
                        disabled={
                          item.mime_type !== "application/pdf" ||
                          (item.size_bytes ?? Infinity) > 10 * 1024 * 1024
                        }
                      >
                        {item.title}
                        {item.mime_type !== "application/pdf"
                          ? " (not a PDF)"
                          : (item.size_bytes ?? Infinity) > 10 * 1024 * 1024
                            ? " (over 10 MB AI limit)"
                            : ""}
                      </option>
                    ))}
                  </select>
                  <p className="text-xs text-muted-foreground">
                    Text PDFs: up to 10 MB, 50 pages and 48,000 text characters.
                    Scanned documents need OCR first.
                  </p>
                </div>
                {resourceError ? (
                  <p role="alert" className="text-sm text-destructive">
                    {resourceError}
                  </p>
                ) : null}
                {!loadingResources && !resources.length ? (
                  <p role="status" className="text-sm text-muted-foreground">
                    No class resources available. Upload a text PDF to get
                    started.
                  </p>
                ) : null}
                <div className="flex flex-wrap gap-3">
                  <Button
                    type="button"
                    variant="outline"
                    disabled={loadingResources}
                    onClick={() => setResourceRefresh((value) => value + 1)}
                  >
                    <RefreshCw className="mr-2 h-4 w-4" aria-hidden="true" />
                    Refresh resources
                  </Button>
                  <Button variant="link" asChild>
                    <Link
                      href={
                        classId
                          ? `/classes/${classId}?tab=resources`
                          : "/classes"
                      }
                      target="_blank"
                      rel="noreferrer"
                    >
                      Open Class Resources (new tab)
                    </Link>
                  </Button>
                </div>
              </div>
            ) : (
              <div className="space-y-2">
                <Label htmlFor="ai-activity">
                  Approved activity / learning outcome
                </Label>
                <select
                  id="ai-activity"
                  value={aiActivityVersionId}
                  onChange={(event) =>
                    setAiActivityVersionId(event.target.value)
                  }
                  disabled={!grounding}
                  required
                  className="flex min-h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:cursor-not-allowed disabled:opacity-60"
                >
                  {!grounding ? (
                    <option value="">No approved context available</option>
                  ) : null}
                  {grounding?.activities.map((activity) => (
                    <option key={activity.id} value={activity.id}>
                      M{activity.missionNumber} · {activity.title}
                    </option>
                  ))}
                </select>
                {grounding && aiActivityVersionId ? (
                  <p className="text-xs leading-relaxed text-muted-foreground">
                    {
                      grounding.activities.find(
                        (activity) => activity.id === aiActivityVersionId,
                      )?.learningOutcome
                    }
                  </p>
                ) : null}
              </div>
            )}
            <div className="space-y-2">
              <Label htmlFor="ai-topic">Quiz focus</Label>
              <Textarea
                id="ai-topic"
                value={aiTopic}
                onChange={(event) => setAiTopic(event.target.value)}
                rows={3}
                maxLength={240}
                required
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="ai-instructor-context">
                Additional Instructor context (optional)
              </Label>
              <Textarea
                id="ai-instructor-context"
                value={aiInstructorContext}
                onChange={(event) => setAiInstructorContext(event.target.value)}
                rows={3}
                maxLength={2000}
                placeholder="Add class-specific emphasis without introducing new TESDA rules."
              />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-2">
                <Label htmlFor="ai-difficulty">Difficulty</Label>
                <select
                  id="ai-difficulty"
                  value={difficulty}
                  onChange={(event) =>
                    setDifficulty(event.target.value as typeof difficulty)
                  }
                  className="flex min-h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                >
                  <option value="foundation">Foundation</option>
                  <option value="intermediate">Intermediate</option>
                  <option value="advanced">Advanced</option>
                </select>
              </div>
              <div className="space-y-2">
                <Label htmlFor="ai-count">Questions</Label>
                <Input
                  id="ai-count"
                  type="number"
                  min={1}
                  max={10}
                  value={itemCount}
                  onChange={(event) => setItemCount(Number(event.target.value))}
                />
              </div>
            </div>
            <fieldset>
              <legend className="text-sm font-medium">
                Supported question types
              </legend>
              <div className="mt-2 grid gap-2">
                {Object.entries(itemTypeLabels).map(([value, label]) => (
                  <label
                    key={value}
                    className="flex min-h-10 cursor-pointer items-center gap-3 rounded-md border border-border px-3 text-sm focus-within:ring-2 focus-within:ring-ring"
                  >
                    <input
                      type="checkbox"
                      checked={aiTypes.includes(value as ItemType)}
                      onChange={(event) =>
                        setAiTypes((current) =>
                          event.target.checked
                            ? [...new Set([...current, value as ItemType])]
                            : current.filter((item) => item !== value),
                        )
                      }
                      className="h-4 w-4 accent-primary"
                    />
                    {label}
                  </label>
                ))}
              </div>
            </fieldset>
            <label className="flex cursor-pointer items-start gap-3 rounded-lg border border-border bg-muted/30 p-3 text-sm leading-relaxed">
              <input
                type="checkbox"
                className="mt-1 h-4 w-4 shrink-0 accent-primary"
                checked={consent}
                onChange={(event) => setConsent(event.target.checked)}
              />
              <span>
                I confirm that this content is appropriate to send to OpenRouter
                and its model provider for AI processing. The selected source
                text, quiz focus and optional context will leave ByteQuest. I
                have permission to share them.
              </span>
            </label>
            {configuration?.simulated ? (
              <p role="status" className="text-sm text-amber-900">
                QA simulation: responses come from a local test server. No real
                AI provider is being used.
              </p>
            ) : null}
          </fieldset>
          {aiError ? (
            <div
              role="alert"
              aria-live="assertive"
              className="rounded-lg border border-destructive/30 bg-destructive/10 px-3 py-2 text-sm text-destructive"
            >
              {aiError}
            </div>
          ) : null}
          <Button
            type="submit"
            disabled={busy !== null || Boolean(disabledReason)}
            className="min-h-11 w-full"
          >
            {busy === "ai" ? (
              <Loader2
                className="mr-2 h-4 w-4 animate-spin"
                aria-hidden="true"
              />
            ) : (
              <Sparkles className="mr-2 h-4 w-4" aria-hidden="true" />
            )}
            {busy === "ai" ? "Generating quiz…" : "Generate with AI"}
          </Button>
          {disabledReason ? (
            <p role="status" className="text-sm text-muted-foreground">
              {disabledReason}
            </p>
          ) : null}
          <p className="text-xs leading-relaxed text-muted-foreground">
            AI-generated draft · never auto-published · does not determine
            learner competency
          </p>
        </form>
      </section>
      {items.filter((item) => item.origin === "ai_generated_draft").length ? (
        <section className="space-y-3 border-t border-border pt-5">
          <h3 className="font-medium">Generate a separate alternative</h3>
          <p className="text-sm text-muted-foreground">
            The original question is kept. Alternatives also require your
            review.
          </p>
          {items
            .filter((item) => item.origin === "ai_generated_draft")
            .map((item) => (
              <div
                key={item.id}
                className="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-border p-3"
              >
                <p className="min-w-0 flex-1 break-words text-sm">
                  {item.prompt}
                </p>
                <Button
                  variant="outline"
                  disabled={
                    busy !== null ||
                    Boolean(disabledReason) ||
                    aiTopic.trim().length < 2
                  }
                  onClick={() => regenerateAiItem(item)}
                >
                  <RefreshCw className="mr-2 h-4 w-4" aria-hidden="true" />
                  Generate alternative
                </Button>
              </div>
            ))}
        </section>
      ) : null}
    </div>
  );
}
