import { z } from "zod";

export const itemTypeLabels = {
  multiple_choice: "Multiple choice",
  true_false: "True or false",
  identification: "Identification",
  scenario_based: "Scenario-based",
} as const;
export type ItemType = keyof typeof itemTypeLabels;
export interface QuizItem {
  id: string;
  itemCode: string;
  itemType: ItemType;
  prompt: string;
  options: string[];
  correctAnswer: string;
  explanation: string | null;
  origin: "instructor_authored" | "ai_generated_draft";
  reviewStatus: "draft" | "approved" | "rejected";
  reviewNotes: string | null;
  orderIndex: number;
}

export const quizSchema = z.object({
  title: z.string().trim().min(3, "Use at least 3 characters.").max(200),
  topic: z.string().trim().min(2, "Use at least 2 characters.").max(240),
  description: z.string().trim().max(2000),
  instructions: z.string().trim().max(2000),
  cocModuleId: z.string().uuid().or(z.literal("")),
});

export const questionSchema = z
  .object({
    itemType: z.enum([
      "multiple_choice",
      "true_false",
      "identification",
      "scenario_based",
    ]),
    prompt: z.string().trim().min(5, "Use at least 5 characters.").max(2000),
    options: z.array(z.string().trim().min(1, "Enter text for every option.")),
    correctAnswer: z
      .string()
      .trim()
      .min(1, "Select or enter the correct answer."),
    explanation: z.string().trim().max(1500),
  })
  .superRefine((item, ctx) => {
    if (
      item.itemType === "multiple_choice" ||
      item.itemType === "scenario_based"
    ) {
      if (
        item.options.length < 2 ||
        item.options.length > 6 ||
        !item.options.includes(item.correctAnswer)
      ) {
        ctx.addIssue({
          code: "custom",
          path: ["correctAnswer"],
          message: "Add 2–6 options and select the correct option.",
        });
      }
      if (new Set(item.options).size !== item.options.length) {
        ctx.addIssue({
          code: "custom",
          path: ["options"],
          message: "Use distinct option text so the answer is unambiguous.",
        });
      }
    } else if (item.options.length) {
      ctx.addIssue({
        code: "custom",
        path: ["options"],
        message: "This question type does not use options.",
      });
    }
    if (
      item.itemType === "true_false" &&
      !["true", "false"].includes(item.correctAnswer)
    ) {
      ctx.addIssue({
        code: "custom",
        path: ["correctAnswer"],
        message: "Select True or False.",
      });
    }
    if (item.itemType === "identification" && item.correctAnswer.length > 500) {
      ctx.addIssue({
        code: "custom",
        path: ["correctAnswer"],
        message: "Use at most 500 characters.",
      });
    }
  });
export type QuestionInput = z.infer<typeof questionSchema>;

export function publicationReadiness(items: QuizItem[]) {
  const approved = items.filter(
    (item) => item.reviewStatus === "approved",
  ).length;
  return {
    approved,
    total: items.length,
    ready: items.length > 0 && approved === items.length,
  };
}

export function quizErrorMessage(message: string) {
  const known: Record<string, string> = {
    ALL_QUIZ_ITEMS_REQUIRE_APPROVAL:
      "Review and approve every question before publishing.",
    APPROVED_QUIZ_ITEM_REQUIRED:
      "Add and approve at least one question before publishing.",
    INSTRUCTOR_CLASS_SCOPE_REQUIRED:
      "Your access to a selected class has changed. Refresh and select your active classes again.",
    ACTIVE_CLASS_REQUIRED:
      "A selected class is no longer active. Refresh and select an active class.",
    QUIZ_ORDER_CHANGED_REFRESH_REQUIRED:
      "The question list changed. Refresh before reordering it again.",
    DRAFT_ACTIVE_QUIZ_REQUIRED:
      "This version is no longer an active draft. Refresh to view its current status.",
    QUIZ_SCOPE_DENIED: "You do not have permission to change this quiz.",
    PUBLISHED_QUIZ_ITEMS_ARE_IMMUTABLE:
      "This version has been published. Create a new draft to change its questions.",
  };
  return (
    Object.entries(known).find(([code]) => message.includes(code))?.[1] ??
    message
  );
}
