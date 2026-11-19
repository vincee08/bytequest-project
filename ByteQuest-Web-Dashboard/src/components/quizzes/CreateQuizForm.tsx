"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Loader2, Plus } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { createClient } from "@/lib/supabase/client";
import { quizErrorMessage } from "@/lib/quizzes/authoring";
import type { CurriculumCatalog } from "@/lib/quizzes/curriculum";
import {
  emptyQuizForm,
  parseQuizForm,
  quizSettingsRpcArgs,
  scopeError,
  type QuizFormState,
} from "@/lib/quizzes/form";
import { quizDb } from "@/lib/quizzes/types";
import { QuizCurriculumFields } from "./QuizCurriculumFields";

export function CreateQuizForm({
  catalog,
  onDirtyChange,
}: {
  catalog: CurriculumCatalog;
  onDirtyChange?: (dirty: boolean) => void;
}) {
  const router = useRouter();
  const [form, setForm] = useState<QuizFormState>(emptyQuizForm);
  const [submitting, setSubmitting] = useState(false);
  const [errors, setErrors] = useState<Record<string, string[] | undefined>>(
    {},
  );
  const [requestError, setRequestError] = useState("");

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    const parsed = parseQuizForm(form);
    const scope = scopeError(form);
    if (!parsed.success || scope) {
      setErrors({
        ...(parsed.success ? {} : parsed.error.flatten().fieldErrors),
        ...(scope ? { moduleIds: [scope] } : {}),
      });
      return;
    }

    setSubmitting(true);
    setErrors({});
    setRequestError("");
    try {
      const { data, error } = await quizDb(createClient()).rpc(
        "create_instructor_quiz",
        quizSettingsRpcArgs(parsed.data, catalog),
      );
      const created = data as { id?: string } | null;
      if (error || !created?.id) {
        throw new Error(
          error?.message || "The quiz draft could not be created.",
        );
      }
      toast.success("Quiz and version 1 draft created.");
      onDirtyChange?.(false);
      router.push(`/quizzes/${created.id}`);
      router.refresh();
    } catch (error) {
      setRequestError(
        error instanceof Error
          ? quizErrorMessage(error.message)
          : "Unable to create the quiz. Your entries are kept; try again.",
      );
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-5" noValidate>
      {requestError ? (
        <p role="alert" className="text-sm text-destructive">
          {requestError}
        </p>
      ) : null}
      <QuizCurriculumFields
        idPrefix="create-quiz"
        catalog={catalog}
        value={form}
        onChange={(next) => {
          setForm(next);
          onDirtyChange?.(true);
        }}
        errors={errors}
        disabled={submitting}
      />
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
