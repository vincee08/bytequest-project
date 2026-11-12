"use client";
import { useEffect, useState } from "react";
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
}: {
  version: { id: string };
  grounding: QuizGroundingCatalog | null;
  topic: string;
  items: QuizItem[];
}) {
  const router = useRouter();
  const isDraft = true;
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
    setAiActivityVersionId((current) =>
      grounding?.activities.some((activity) => activity.id === current)
        ? current
        : (grounding?.activities[0]?.id ?? ""),
    );
  }, [grounding]);
  async function generateAiDraft(event: React.FormEvent) {
    event.preventDefault();
    if (!version || !isDraft || aiTypes.length === 0 || !aiActivityVersionId)
      return;
    setAiError(null);
    setBusy("ai");
    try {
      const response = await fetch("/api/instructor/quizzes/ai-draft", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          quizVersionId: version.id,
          activityVersionId: aiActivityVersionId,
          topic: aiTopic,
          instructorContext: aiInstructorContext.trim() || undefined,
          difficulty,
          itemCount,
          itemTypes: aiTypes,
        }),
      });
      const result = (await response.json().catch(() => null)) as {
        error?: string;
        generatedCount?: number;
      } | null;
      if (!response.ok) {
        const message =
          result?.error ||
          "AI draft generation failed without publishing any item.";
        setAiError(message);
        toast.error(message);
      } else {
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
      setBusy(null);
    }
  }

  async function regenerateAiItem(item: QuizItem) {
    if (
      !version ||
      !isDraft ||
      item.origin !== "ai_generated_draft" ||
      !aiActivityVersionId
    )
      return;
    setAiError(null);
    setBusy(`regenerate-${item.id}`);
    try {
      const response = await fetch("/api/instructor/quizzes/ai-draft", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(
          buildAlternativeQuizDraftRequest({
            quizVersionId: version.id,
            activityVersionId: aiActivityVersionId,
            topic: aiTopic,
            instructorContext: aiInstructorContext,
            difficulty,
            itemType: item.itemType,
            originalPrompt: item.prompt,
          }),
        ),
      });
      const result = (await response.json().catch(() => null)) as {
        error?: string;
      } | null;
      if (!response.ok) {
        const message =
          result?.error ||
          "The alternative question could not be generated. The original draft was kept.";
        setAiError(message);
        toast.error(message);
      } else {
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
          OpenRouter uses the selected approved ByteQuest/TESDA context. Every
          result stays an editable draft until an Instructor reviews and
          approves it.
        </p>

        {grounding ? (
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
            Select and save a related COC with complete approved source content
            before generating AI drafts. Manual authoring remains available.
          </div>
        )}

        <form onSubmit={generateAiDraft} className="mt-5 space-y-4">
          <div className="space-y-2">
            <Label htmlFor="ai-activity">
              Approved activity / learning outcome
            </Label>
            <select
              id="ai-activity"
              value={aiActivityVersionId}
              onChange={(event) => setAiActivityVersionId(event.target.value)}
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
            disabled={
              busy !== null ||
              aiTypes.length === 0 ||
              !grounding ||
              !aiActivityVersionId
            }
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
                    !aiActivityVersionId ||
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
