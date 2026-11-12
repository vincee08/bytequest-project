"use client";

import { useState } from "react";
import { Loader2, Plus, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
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
import {
  itemTypeLabels,
  questionSchema,
  type ItemType,
  type QuestionInput,
  type QuizItem,
} from "@/lib/quizzes/authoring";

export function QuestionEditor({
  item,
  onClose,
  onSave,
  onDirtyChange,
}: {
  item: QuizItem | null;
  onClose: () => void;
  onSave: (input: QuestionInput, id?: string) => Promise<boolean>;
  onDirtyChange: (dirty: boolean) => void;
}) {
  const [itemType, setItemType] = useState<ItemType>(
    item?.itemType ?? "multiple_choice",
  );
  const [prompt, setPrompt] = useState(item?.prompt ?? "");
  const [options, setOptions] = useState(
    item?.options.length ? item.options : ["", "", "", ""],
  );
  const [answerIndex, setAnswerIndex] = useState(
    item ? item.options.indexOf(item.correctAnswer) : -1,
  );
  const [answer, setAnswer] = useState(
    item?.itemType === "true_false"
      ? item.correctAnswer.toLowerCase()
      : (item?.correctAnswer ?? ""),
  );
  const [explanation, setExplanation] = useState(item?.explanation ?? "");
  const [dirty, setDirty] = useState(false);
  const [saving, setSaving] = useState(false);
  const [errors, setErrors] = useState<Record<string, string[] | undefined>>(
    {},
  );
  const choice =
    itemType === "multiple_choice" || itemType === "scenario_based";
  function changed() {
    setDirty(true);
    onDirtyChange(true);
  }
  function close() {
    if (
      saving ||
      (dirty && !window.confirm("Discard the unsaved question changes?"))
    )
      return;
    onDirtyChange(false);
    onClose();
  }
  async function submit(event: React.FormEvent) {
    event.preventDefault();
    const result = questionSchema.safeParse({
      itemType,
      prompt,
      options: choice ? options : [],
      correctAnswer: choice ? (options[answerIndex] ?? "") : answer,
      explanation,
    });
    if (!result.success) {
      setErrors(result.error.flatten().fieldErrors);
      return;
    }
    setErrors({});
    setSaving(true);
    try {
      if (await onSave(result.data, item?.id)) {
        onDirtyChange(false);
        onClose();
      }
    } finally {
      setSaving(false);
    }
  }
  const error = (field: string) =>
    errors[field]?.length ? (
      <p
        id={`question-${field}-error`}
        role="alert"
        className="text-sm text-destructive"
      >
        {errors[field]?.join(" ")}
      </p>
    ) : null;
  return (
    <Dialog
      open
      onOpenChange={(open) => {
        if (!open) close();
      }}
    >
      <DialogContent
        className="max-h-[90dvh] max-w-2xl overflow-y-auto motion-reduce:animate-none"
        onInteractOutside={(event) => event.preventDefault()}
      >
        <DialogHeader>
          <DialogTitle>{item ? "Edit question" : "Add question"}</DialogTitle>
          <DialogDescription>
            Save as a draft, then review it before publication. Editing clears
            its previous approval.
          </DialogDescription>
        </DialogHeader>
        <form onSubmit={submit} className="space-y-4" onChange={changed}>
          <fieldset disabled={saving} className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="question-type">Question type</Label>
              <select
                id="question-type"
                className="min-h-11 w-full rounded-md border border-input bg-background px-3 text-sm focus-visible:ring-2 focus-visible:ring-ring"
                value={itemType}
                onChange={(event) => {
                  setItemType(event.target.value as ItemType);
                  setAnswer("");
                  setAnswerIndex(-1);
                  setErrors({});
                }}
              >
                {Object.entries(itemTypeLabels).map(([value, label]) => (
                  <option key={value} value={value}>
                    {label}
                  </option>
                ))}
              </select>
            </div>
            <div className="space-y-2">
              <Label htmlFor="question-prompt">
                {itemType === "scenario_based"
                  ? "Scenario and question"
                  : itemType === "true_false"
                    ? "Statement"
                    : "Question prompt"}
              </Label>
              <Textarea
                autoFocus
                id="question-prompt"
                required
                minLength={5}
                maxLength={2000}
                rows={3}
                value={prompt}
                onChange={(event) => setPrompt(event.target.value)}
                aria-invalid={!!errors.prompt}
                aria-describedby={
                  errors.prompt ? "question-prompt-error" : undefined
                }
              />
              {error("prompt")}
            </div>
            {choice ? (
              <fieldset className="space-y-2">
                <legend className="mb-2 text-sm font-medium">
                  Options · select the correct answer
                </legend>
                {options.map((option, index) => (
                  <div key={index} className="flex items-center gap-2">
                    <label className="flex min-h-11 min-w-11 items-center justify-center rounded-md border border-input focus-within:ring-2 focus-within:ring-ring">
                      <input
                        type="radio"
                        name="correct-option"
                        checked={answerIndex === index}
                        onChange={() => setAnswerIndex(index)}
                        aria-label={`Option ${String.fromCharCode(65 + index)} is correct`}
                      />
                    </label>
                    <div className="min-w-0 flex-1">
                      <Label className="sr-only" htmlFor={`option-${index}`}>
                        Option {String.fromCharCode(65 + index)}
                      </Label>
                      <Input
                        id={`option-${index}`}
                        required
                        maxLength={2000}
                        className="min-h-11"
                        value={option}
                        onChange={(event) =>
                          setOptions((current) =>
                            current.map((text, position) =>
                              position === index ? event.target.value : text,
                            ),
                          )
                        }
                        placeholder={`Option ${String.fromCharCode(65 + index)}`}
                      />
                    </div>
                    <Button
                      type="button"
                      variant="ghost"
                      className="min-h-11 min-w-11"
                      disabled={options.length <= 2}
                      aria-label={`Remove option ${String.fromCharCode(65 + index)}`}
                      onClick={() => {
                        setOptions((current) =>
                          current.filter((_, position) => position !== index),
                        );
                        setAnswerIndex((current) =>
                          current === index
                            ? -1
                            : current > index
                              ? current - 1
                              : current,
                        );
                        changed();
                      }}
                    >
                      <Trash2 aria-hidden="true" className="h-4 w-4" />
                    </Button>
                  </div>
                ))}
                {error("options")}
                <Button
                  type="button"
                  variant="outline"
                  disabled={options.length >= 6}
                  onClick={() => {
                    setOptions((current) => [...current, ""]);
                    changed();
                  }}
                >
                  <Plus aria-hidden="true" className="mr-2 h-4 w-4" />
                  Add option
                </Button>
              </fieldset>
            ) : itemType === "true_false" ? (
              <fieldset>
                <legend className="mb-2 text-sm font-medium">
                  Correct answer
                </legend>
                <div className="flex gap-3">
                  {["true", "false"].map((value) => (
                    <label
                      key={value}
                      className="flex min-h-11 flex-1 cursor-pointer items-center gap-3 rounded-md border border-input px-3 focus-within:ring-2 focus-within:ring-ring"
                    >
                      <input
                        type="radio"
                        name="boolean-answer"
                        value={value}
                        checked={answer === value}
                        onChange={() => setAnswer(value)}
                        required
                      />
                      {value === "true" ? "True" : "False"}
                    </label>
                  ))}
                </div>
              </fieldset>
            ) : (
              <div className="space-y-2">
                <Label htmlFor="identification-answer">Correct answer</Label>
                <Input
                  id="identification-answer"
                  required
                  maxLength={500}
                  value={answer}
                  onChange={(event) => setAnswer(event.target.value)}
                  aria-describedby="identification-rules"
                />
                <p
                  id="identification-rules"
                  className="text-xs text-muted-foreground"
                >
                  One accepted answer. Grading ignores letter case and spaces at
                  the beginning and end.
                </p>
              </div>
            )}
            {error("correctAnswer")}
            <div className="space-y-2">
              <Label htmlFor="question-explanation">
                Explanation (optional)
              </Label>
              <Textarea
                id="question-explanation"
                maxLength={1500}
                rows={2}
                value={explanation}
                onChange={(event) => setExplanation(event.target.value)}
              />
              {error("explanation")}
            </div>
          </fieldset>
          <div className="flex flex-wrap justify-end gap-2 border-t border-border pt-4">
            <Button
              type="button"
              variant="outline"
              disabled={saving}
              onClick={close}
            >
              Cancel
            </Button>
            <Button type="submit" disabled={saving} className="min-h-11">
              {saving ? (
                <Loader2
                  className="mr-2 h-4 w-4 animate-spin"
                  aria-hidden="true"
                />
              ) : null}
              {saving ? "Saving…" : "Save question"}
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}
