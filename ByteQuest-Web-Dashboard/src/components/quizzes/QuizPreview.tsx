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
import { itemTypeLabels, type QuizItem } from "@/lib/quizzes/authoring";

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
            <p className="whitespace-pre-wrap font-medium">{item.prompt}</p>
            {item.itemType === "identification" ? (
              <Input
                aria-label="Preview answer"
                value={answers[item.id] ?? ""}
                onChange={(event) =>
                  setAnswers((current) => ({
                    ...current,
                    [item.id]: event.target.value,
                  }))
                }
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
                      onChange={() =>
                        setAnswers((current) => ({
                          ...current,
                          [item.id]: option,
                        }))
                      }
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
