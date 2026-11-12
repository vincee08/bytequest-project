"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Loader2, Plus } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { createClient } from "@/lib/supabase/client";
import { quizSchema } from "@/lib/quizzes/authoring";

export function CreateQuizForm({
  modules,
  onDirtyChange,
}: {
  modules: { id: string; code: string; title: string }[];
  onDirtyChange?: (dirty: boolean) => void;
}) {
  const router = useRouter();
  const [title, setTitle] = useState("");
  const [topic, setTopic] = useState("");
  const [description, setDescription] = useState("");
  const [instructions, setInstructions] = useState("");
  const [cocModuleId, setCocModuleId] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [errors, setErrors] = useState<Record<string, string[] | undefined>>(
    {},
  );
  const [requestError, setRequestError] = useState("");

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    const parsed = quizSchema.safeParse({
      title,
      topic,
      description,
      instructions,
      cocModuleId,
    });
    if (!parsed.success) {
      setErrors(parsed.error.flatten().fieldErrors);
      return;
    }

    setSubmitting(true);
    setErrors({});
    setRequestError("");
    try {
      const { data, error } = await createClient().rpc(
        "create_instructor_quiz",
        {
          p_title: parsed.data.title,
          p_topic: parsed.data.topic,
          p_description: parsed.data.description || undefined,
          p_coc_module_id: parsed.data.cocModuleId || undefined,
          p_instructions: parsed.data.instructions || undefined,
        },
      );

      if (error || !data) {
        throw new Error(
          error?.message || "The quiz draft could not be created.",
        );
      }

      toast.success("Quiz and version 1 draft created.");
      onDirtyChange?.(false);
      router.push(`/quizzes/${data.id}`);
      router.refresh();
    } catch (error) {
      setRequestError(
        error instanceof Error
          ? error.message
          : "Unable to create the quiz. Your entries are kept; try again.",
      );
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <form
      onSubmit={handleSubmit}
      className="space-y-5"
      onChange={() => onDirtyChange?.(true)}
    >
      {requestError ? (
        <p role="alert" className="text-sm text-destructive">
          {requestError}
        </p>
      ) : null}
      <fieldset disabled={submitting} className="space-y-4">
        <div className="grid gap-4 md:grid-cols-2">
          <div className="space-y-2">
            <Label htmlFor="quiz-title">
              Quiz title <span aria-hidden="true">*</span>
            </Label>
            <Input
              autoFocus
              id="quiz-title"
              value={title}
              onChange={(event) => setTitle(event.target.value)}
              minLength={3}
              maxLength={200}
              required
              aria-invalid={!!errors.title}
              aria-describedby={errors.title ? "create-title-error" : undefined}
              placeholder="Network troubleshooting review"
            />
            {errors.title ? (
              <p
                id="create-title-error"
                role="alert"
                className="text-sm text-destructive"
              >
                {errors.title.join(" ")}
              </p>
            ) : null}
          </div>
          <div className="space-y-2">
            <Label htmlFor="quiz-topic">
              Topic <span aria-hidden="true">*</span>
            </Label>
            <Input
              id="quiz-topic"
              value={topic}
              onChange={(event) => setTopic(event.target.value)}
              minLength={2}
              maxLength={240}
              required
              aria-invalid={!!errors.topic}
              aria-describedby={errors.topic ? "create-topic-error" : undefined}
              placeholder="Cable testing and fault isolation"
            />
            {errors.topic ? (
              <p
                id="create-topic-error"
                role="alert"
                className="text-sm text-destructive"
              >
                {errors.topic.join(" ")}
              </p>
            ) : null}
          </div>
          <div className="space-y-2">
            <Label htmlFor="quiz-coc">Related COC (optional)</Label>
            <select
              id="quiz-coc"
              value={cocModuleId}
              onChange={(event) => setCocModuleId(event.target.value)}
              className="flex min-h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
            >
              <option value="">General supplementary quiz</option>
              {modules.map((module) => (
                <option key={module.id} value={module.id}>
                  {module.code.toUpperCase()} — {module.title}
                </option>
              ))}
            </select>
          </div>
        </div>
        <details className="space-y-4">
          <summary className="min-h-10 cursor-pointer py-2 text-sm font-medium">
            Description & learner instructions (optional)
          </summary>
          <div className="space-y-2">
            <Label htmlFor="quiz-instructions">
              Learner instructions (optional)
            </Label>
            <Input
              id="quiz-instructions"
              value={instructions}
              onChange={(event) => setInstructions(event.target.value)}
              maxLength={2000}
              placeholder="Answer each item using the lesson evidence."
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="quiz-description">
              Instructor description (optional)
            </Label>
            <Textarea
              id="quiz-description"
              value={description}
              onChange={(event) => setDescription(event.target.value)}
              maxLength={2000}
              rows={3}
              placeholder="Purpose, intended learner group, or review notes."
            />
          </div>
        </details>
      </fieldset>
      <Button type="submit" disabled={submitting} className="min-h-11">
        {submitting ? (
          <Loader2 className="mr-2 h-4 w-4 animate-spin" aria-hidden="true" />
        ) : (
          <Plus className="mr-2 h-4 w-4" aria-hidden="true" />
        )}
        {submitting ? "Creating…" : "Create quiz & add questions"}
      </Button>
    </form>
  );
}
