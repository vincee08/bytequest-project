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
  nextCriterionId,
  questionSchema,
  rubricTotal,
  type ItemType,
  type QuestionInput,
  type QuizItem,
} from "@/lib/quizzes/authoring";

interface RubricDraft {
  id: string;
  criterion: string;
  description: string;
  maxPoints: string;
}

const numberOrNull = (value: string) =>
  value.trim() === "" ? null : Number(value);

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
  const [points, setPoints] = useState(String(item?.points ?? 1));
  const [scenario, setScenario] = useState(item?.scenario ?? "");
  const [rubric, setRubric] = useState<RubricDraft[]>(
    item?.rubric?.length
      ? item.rubric.map((row) => ({ ...row, maxPoints: String(row.maxPoints) }))
      : [{ id: "C1", criterion: "", description: "", maxPoints: "5" }],
  );
  const [minWords, setMinWords] = useState(
    item?.minWords ? String(item.minWords) : "",
  );
  const [maxWords, setMaxWords] = useState(
    item?.maxWords ? String(item.maxWords) : "",
  );
  const [dirty, setDirty] = useState(false);
  const [saving, setSaving] = useState(false);
  const [errors, setErrors] = useState<Record<string, string[] | undefined>>(
    {},
  );
  const essay = itemType === "scenario_essay";
  const choice =
    itemType === "multiple_choice" || itemType === "scenario_based";
  const total = rubricTotal(
    rubric.map((row) => ({ maxPoints: Number(row.maxPoints) })),
  );
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
  function updateRow(index: number, patch: Partial<RubricDraft>) {
    setRubric((rows) =>
      rows.map((row, position) => (position === index ? { ...row, ...patch } : row)),
    );
    changed();
  }
  async function submit(event: React.FormEvent) {
    event.preventDefault();
    const result = questionSchema.safeParse({
      itemType,
      prompt,
      options: choice ? options : [],
      correctAnswer: essay
        ? answer
        : choice
          ? (options[answerIndex] ?? "")
          : answer,
      explanation,
      points: essay ? 1 : Number(points),
      scenario: essay ? scenario : "",
      rubric: essay
        ? rubric.map((row) => ({
            id: row.id,
            criterion: row.criterion,
            description: row.description,
            maxPoints: Number(row.maxPoints),
          }))
        : [],
      minWords: essay ? numberOrNull(minWords) : null,
      maxWords: essay ? numberOrNull(maxWords) : null,
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
              {essay ? (
                <p className="text-xs text-muted-foreground">
                  Learners write a long answer. You score it with the rubric
                  and release the result; quizzes with essays always use
                  instructor release.
                </p>
              ) : null}
            </div>
            {essay ? (
              <div className="space-y-2">
                <Label htmlFor="question-scenario">Scenario</Label>
                <Textarea
                  id="question-scenario"
                  required
                  minLength={10}
                  maxLength={4000}
                  rows={4}
                  value={scenario}
                  onChange={(event) => setScenario(event.target.value)}
                  aria-invalid={!!errors.scenario}
                  aria-describedby={
                    errors.scenario ? "question-scenario-error" : undefined
                  }
                  placeholder="A client reports that a newly assembled workstation does not power on…"
                />
                {error("scenario")}
              </div>
            ) : null}
            <div className="space-y-2">
              <Label htmlFor="question-prompt">
                {essay
                  ? "Essay prompt"
                  : itemType === "scenario_based"
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
            {essay ? (
              <>
                <fieldset className="space-y-3">
                  <legend className="mb-1 text-sm font-medium">
                    Rubric · {total || 0} points total
                  </legend>
                  {rubric.map((row, index) => (
                    <div
                      key={row.id}
                      className="space-y-2 rounded-lg border border-border p-3"
                    >
                      <div className="flex flex-wrap items-end gap-2">
                        <div className="min-w-0 flex-1 space-y-1">
                          <Label htmlFor={`rubric-${row.id}-criterion`}>
                            Criterion {index + 1}
                          </Label>
                          <Input
                            id={`rubric-${row.id}-criterion`}
                            className="min-h-11"
                            required
                            maxLength={200}
                            value={row.criterion}
                            onChange={(event) =>
                              updateRow(index, { criterion: event.target.value })
                            }
                            placeholder="Safety precautions"
                          />
                        </div>
                        <div className="w-24 space-y-1">
                          <Label htmlFor={`rubric-${row.id}-points`}>Points</Label>
                          <Input
                            id={`rubric-${row.id}-points`}
                            className="min-h-11"
                            type="number"
                            min={0.5}
                            max={100}
                            step={0.5}
                            required
                            value={row.maxPoints}
                            onChange={(event) =>
                              updateRow(index, { maxPoints: event.target.value })
                            }
                          />
                        </div>
                        <Button
                          type="button"
                          variant="ghost"
                          className="min-h-11 min-w-11"
                          disabled={rubric.length <= 1}
                          aria-label={`Remove criterion ${index + 1}`}
                          onClick={() => {
                            setRubric((rows) =>
                              rows.filter((_, position) => position !== index),
                            );
                            changed();
                          }}
                        >
                          <Trash2 aria-hidden="true" className="h-4 w-4" />
                        </Button>
                      </div>
                      <div className="space-y-1">
                        <Label htmlFor={`rubric-${row.id}-description`}>
                          What earns full points (shown to learners after release)
                        </Label>
                        <Textarea
                          id={`rubric-${row.id}-description`}
                          rows={2}
                          maxLength={1000}
                          value={row.description}
                          onChange={(event) =>
                            updateRow(index, { description: event.target.value })
                          }
                          placeholder="Wears an ESD strap and grounds the case before handling components."
                        />
                      </div>
                    </div>
                  ))}
                  {error("rubric")}
                  <Button
                    type="button"
                    variant="outline"
                    disabled={rubric.length >= 10}
                    onClick={() => {
                      setRubric((rows) => [
                        ...rows,
                        {
                          id: nextCriterionId(rows),
                          criterion: "",
                          description: "",
                          maxPoints: "5",
                        },
                      ]);
                      changed();
                    }}
                  >
                    <Plus aria-hidden="true" className="mr-2 h-4 w-4" />
                    Add criterion
                  </Button>
                </fieldset>
                <fieldset className="grid gap-3 sm:grid-cols-2">
                  <legend className="mb-1 text-sm font-medium sm:col-span-2">
                    Word guidance (optional)
                  </legend>
                  <div className="space-y-1">
                    <Label htmlFor="question-min-words">Suggested minimum</Label>
                    <Input
                      id="question-min-words"
                      className="min-h-11"
                      type="number"
                      min={1}
                      max={5000}
                      value={minWords}
                      onChange={(event) => setMinWords(event.target.value)}
                    />
                  </div>
                  <div className="space-y-1">
                    <Label htmlFor="question-max-words">Suggested maximum</Label>
                    <Input
                      id="question-max-words"
                      className="min-h-11"
                      type="number"
                      min={1}
                      max={5000}
                      value={maxWords}
                      onChange={(event) => setMaxWords(event.target.value)}
                    />
                  </div>
                  <div className="sm:col-span-2">{error("maxWords")}</div>
                </fieldset>
                <div className="space-y-2">
                  <Label htmlFor="essay-guide">
                    Scoring guide (optional, instructor only)
                  </Label>
                  <Textarea
                    id="essay-guide"
                    rows={2}
                    maxLength={2000}
                    value={answer}
                    onChange={(event) => setAnswer(event.target.value)}
                    placeholder="Key points a complete answer mentions."
                  />
                  <p className="text-xs text-muted-foreground">
                    Never sent to learners.
                  </p>
                </div>
              </>
            ) : choice ? (
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
            {!essay ? error("correctAnswer") : null}
            {!essay ? (
              <div className="space-y-2">
                <Label htmlFor="question-points">Points</Label>
                <Input
                  id="question-points"
                  className="min-h-11 w-28"
                  type="number"
                  min={0.5}
                  max={100}
                  step={0.5}
                  value={points}
                  onChange={(event) => setPoints(event.target.value)}
                  aria-invalid={!!errors.points}
                />
                {error("points")}
              </div>
            ) : null}
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
