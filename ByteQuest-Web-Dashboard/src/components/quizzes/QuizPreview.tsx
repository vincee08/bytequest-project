"use client";

import { useState } from "react";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { itemTypeLabels, type QuizItem } from "@/lib/quizzes/authoring";

const wordCount = (text: string) =>
  text.trim() ? text.trim().split(/\s+/).length : 0;

export function QuizPreview({
  title,
  instructions,
  items,
  onClose,
}: {
  title: string;
  instructions?: string | null;
  items: QuizItem[];
  onClose: () => void;
}) {
  const [index, setIndex] = useState(0);
  const [answers, setAnswers] = useState<Record<string, string>>({});
  const item = items[index];
  const setAnswer = (value: string) =>
    setAnswers((current) => ({ ...current, [item.id]: value }));
  return (
    <Dialog
      open
      onOpenChange={(open) => {
        if (!open) onClose();
      }}
    >
      <DialogContent className="max-h-[90dvh] max-w-2xl overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="break-words">{title}</DialogTitle>
          <DialogDescription>
            Instructor preview · no learner attempt or grade is created.
          </DialogDescription>
        </DialogHeader>
        {instructions ? (
          <p className="whitespace-pre-wrap text-sm text-muted-foreground">
            {instructions}
          </p>
        ) : null}
        {item ? (
          <div className="space-y-4">
            <p className="text-xs font-medium text-muted-foreground">
              Question {index + 1} of {items.length} ·{" "}
              {itemTypeLabels[item.itemType]}
            </p>
            {item.scenario ? (
              <p className="whitespace-pre-wrap rounded-md bg-muted/40 p-3 text-sm">
                <span className="font-medium">Scenario:</span> {item.scenario}
              </p>
            ) : null}
            <p className="whitespace-pre-wrap font-medium">{item.prompt}</p>
            {item.itemType === "scenario_essay" ? (
              <div className="space-y-2">
                <Textarea
                  aria-label="Preview essay answer"
                  rows={6}
                  value={answers[item.id] ?? ""}
                  onChange={(event) => setAnswer(event.target.value)}
                />
                <p className="text-xs text-muted-foreground">
                  {wordCount(answers[item.id] ?? "")} words
                  {item.minWords || item.maxWords
                    ? ` · suggested ${item.minWords ?? "any"}–${item.maxWords ?? "any"} words`
                    : ""}{" "}
                  · scored on{" "}
                  {(item.rubric ?? [])
                    .map((row) => `${row.criterion} (${row.maxPoints})`)
                    .join(", ")}
                </p>
              </div>
            ) : item.itemType === "identification" ? (
              <Input
                aria-label="Preview answer"
                value={answers[item.id] ?? ""}
                onChange={(event) => setAnswer(event.target.value)}
              />
            ) : (
              <fieldset className="space-y-2">
                <legend className="sr-only">Choose an answer</legend>
                {(item.itemType === "true_false"
                  ? ["true", "false"]
                  : item.options
                ).map((option, position) => (
                  <label
                    key={position}
                    className="flex min-h-11 cursor-pointer items-center gap-3 rounded-lg border border-border p-3 focus-within:ring-2 focus-within:ring-ring"
                  >
                    <input
                      type="radio"
                      name={`preview-${item.id}`}
                      value={option}
                      checked={answers[item.id] === option}
                      onChange={() => setAnswer(option)}
                    />
                    <span className="min-w-0 break-words">{option}</span>
                  </label>
                ))}
              </fieldset>
            )}
            <div className="flex justify-between gap-2">
              <Button
                variant="outline"
                disabled={index === 0}
                onClick={() => setIndex((current) => current - 1)}
              >
                Previous
              </Button>
              <Button
                disabled={index === items.length - 1}
                onClick={() => setIndex((current) => current + 1)}
              >
                Next question
              </Button>
            </div>
          </div>
        ) : (
          <p className="text-sm text-muted-foreground">
            Add questions to preview this quiz.
          </p>
        )}
      </DialogContent>
    </Dialog>
  );
}
