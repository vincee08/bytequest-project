import { z } from "zod";
import type {
  QuizDifficulty,
  QuizType,
  ResultReleaseMode,
  RubricCriterion,
} from "./types";
import { QUIZ_UPLOAD_REQUEST_MESSAGE, quizTextRequestsUpload } from "./upload-requests";

export const itemTypeLabels = {
  multiple_choice: "Multiple choice",
  true_false: "True or false",
  identification: "Identification",
  scenario_based: "Scenario-based",
  scenario_essay: "Scenario essay",
} as const;
export type ItemType = keyof typeof itemTypeLabels;
export const objectiveItemTypes = [
  "multiple_choice",
  "true_false",
  "identification",
  "scenario_based",
] as const;

export const quizTypeLabels: Record<QuizType, string> = {
  pre_assessment: "Pre-assessment",
  formative: "Formative",
  summative: "Summative",
};
export const difficultyLabels: Record<QuizDifficulty, string> = {
  foundation: "Foundation",
  intermediate: "Intermediate",
  advanced: "Advanced",
};
export const releaseModeLabels: Record<ResultReleaseMode, string> = {
  immediate: "Show objective results at submission",
  instructor_release: "Instructor evaluates, finalizes and releases",
};

export interface RubricRow {
  id: string;
  criterion: string;
  description: string;
  maxPoints: number;
}

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
  points?: number;
  scenario?: string | null;
  rubric?: RubricRow[];
  minWords?: number | null;
  maxWords?: number | null;
}

/** Legacy metadata schema (title, topic, description, optional COC). */
export const quizSchema = z.object({
  title: z.string().trim().min(3, "Use at least 3 characters.").max(200),
  topic: z.string().trim().min(2, "Use at least 2 characters.").max(240),
  description: z.string().trim().max(2000),
  instructions: z.string().trim().max(2000),
  cocModuleId: z.string().uuid().or(z.literal("")),
});

/** Create/edit form: COC -> scope -> topic -> learning outcomes -> focus -> settings. */
export const quizSettingsSchema = z.object({
  title: z.string().trim().min(3, "Use at least 3 characters.").max(200),
  cocModuleId: z
    .string({ required_error: "Select the COC this quiz belongs to." })
    .uuid("Select the COC this quiz belongs to."),
  moduleIds: z.array(z.string().uuid()).max(16),
  topicId: z.string().uuid().or(z.literal("")),
  outcomeIds: z.array(z.string().uuid()).max(100),
  focus: z
    .string()
    .trim()
    .min(3, "State what this quiz assesses (at least 3 characters).")
    .max(1000, "Keep the focus under 1,000 characters."),
  description: z.string().trim().max(2000),
  instructions: z.string().trim().max(2000),
  quizType: z.enum(["pre_assessment", "formative", "summative"]),
  difficulty: z.enum(["foundation", "intermediate", "advanced"]),
  timeLimitMinutes: z
    .number({ invalid_type_error: "Enter whole minutes from 1 to 240." })
    .int("Enter whole minutes from 1 to 240.")
    .min(1, "Enter whole minutes from 1 to 240.")
    .max(240, "Enter whole minutes from 1 to 240.")
    .nullable(),
  resultReleaseMode: z.enum(["immediate", "instructor_release"]),
});
export type QuizSettingsInput = z.infer<typeof quizSettingsSchema>;

export const rubricRowSchema = z.object({
  id: z.string().trim().regex(/^[A-Za-z0-9_-]{1,40}$/, "Use a short criterion id."),
  criterion: z.string().trim().min(2, "Name each criterion.").max(200),
  description: z.string().trim().max(1000),
  maxPoints: z
    .number({ invalid_type_error: "Enter points for each criterion." })
    .positive("Each criterion needs positive points.")
    .max(100, "Use at most 100 points per criterion."),
});

export const questionSchema = z
  .object({
    itemType: z.enum([
      "multiple_choice",
      "true_false",
      "identification",
      "scenario_based",
      "scenario_essay",
    ]),
    prompt: z.string().trim().min(5, "Use at least 5 characters.").max(2000),
    options: z.array(z.string().trim().min(1, "Enter text for every option.")),
    correctAnswer: z.string().trim().max(2000),
    explanation: z.string().trim().max(1500),
    points: z
      .number({ invalid_type_error: "Enter the points for this question." })
      .positive("Points must be more than zero.")
      .max(100, "Use at most 100 points.")
      .default(1),
    scenario: z.string().trim().max(4000).default(""),
    rubric: z.array(rubricRowSchema).max(10).default([]),
    minWords: z.number().int().min(1).max(5000).nullable().default(null),
    maxWords: z.number().int().min(1).max(5000).nullable().default(null),
  })
  .superRefine((item, ctx) => {
    // Quiz answers are typed; a request for an image or file can never be met.
    if (quizTextRequestsUpload(item.prompt)) {
      ctx.addIssue({ code: "custom", path: ["prompt"], message: QUIZ_UPLOAD_REQUEST_MESSAGE });
    }
    if (quizTextRequestsUpload(item.scenario)) {
      ctx.addIssue({ code: "custom", path: ["scenario"], message: QUIZ_UPLOAD_REQUEST_MESSAGE });
    }
    if (item.rubric.some((row) => quizTextRequestsUpload(row.criterion) || quizTextRequestsUpload(row.description))) {
      ctx.addIssue({ code: "custom", path: ["rubric"], message: QUIZ_UPLOAD_REQUEST_MESSAGE });
    }
    if (item.itemType === "scenario_essay") {
      if (item.options.length) {
        ctx.addIssue({
          code: "custom",
          path: ["options"],
          message: "Scenario essays do not use options.",
        });
      }
      if (item.scenario.length < 10) {
        ctx.addIssue({
          code: "custom",
          path: ["scenario"],
          message: "Describe the scenario in at least 10 characters.",
        });
      }
      if (!item.rubric.length) {
        ctx.addIssue({
          code: "custom",
          path: ["rubric"],
          message: "Add at least one rubric criterion with points.",
        });
      }
      if (
        new Set(item.rubric.map((row) => row.id)).size !== item.rubric.length
      ) {
        ctx.addIssue({
          code: "custom",
          path: ["rubric"],
          message: "Each rubric criterion needs its own id.",
        });
      }
      if (
        item.minWords !== null &&
        item.maxWords !== null &&
        item.minWords > item.maxWords
      ) {
        ctx.addIssue({
          code: "custom",
          path: ["maxWords"],
          message: "The maximum must be at least the minimum word count.",
        });
      }
      return;
    }
    if (item.rubric.length || item.scenario) {
      ctx.addIssue({
        code: "custom",
        path: ["rubric"],
        message: "Only scenario essays use a scenario and rubric.",
      });
    }
    if (!item.correctAnswer) {
      ctx.addIssue({
        code: "custom",
        path: ["correctAnswer"],
        message: "Select or enter the correct answer.",
      });
    }
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

export function rubricTotal(rows: Pick<RubricRow, "maxPoints">[]) {
  return rows.reduce(
    (total, row) => total + (Number.isFinite(row.maxPoints) ? row.maxPoints : 0),
    0,
  );
}

/** Rubric rows in the database shape used by upsert_quiz_item. */
export function toRpcRubric(rows: RubricRow[]): RubricCriterion[] {
  return rows.map((row) => ({
    id: row.id.trim(),
    criterion: row.criterion.trim(),
    description: row.description.trim(),
    max_points: row.maxPoints,
  }));
}

export function fromRpcRubric(value: unknown): RubricRow[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((row) => {
    if (!row || typeof row !== "object") return [];
    const item = row as Record<string, unknown>;
    const maxPoints = Number(item.max_points);
    return typeof item.id === "string" && typeof item.criterion === "string"
      ? [
          {
            id: item.id,
            criterion: item.criterion,
            description:
              typeof item.description === "string" ? item.description : "",
            maxPoints: Number.isFinite(maxPoints) ? maxPoints : 0,
          },
        ]
      : [];
  });
}

/** Next free criterion id (C1, C2, ...). */
export function nextCriterionId(rows: Pick<RubricRow, "id">[]) {
  const used = new Set(rows.map((row) => row.id));
  let index = rows.length + 1;
  while (used.has(`C${index}`)) index += 1;
  return `C${index}`;
}

export function publicationReadiness(items: QuizItem[]) {
  const approved = items.filter(
    (item) => item.reviewStatus === "approved",
  ).length;
  return {
    approved,
    total: items.length,
    ready: items.length > 0 && approved === items.length,
    essays: items.filter((item) => item.itemType === "scenario_essay").length,
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
    QUIZ_COC_REQUIRED: "Select the COC this quiz belongs to.",
    QUIZ_FOCUS_REQUIRED: "State what this quiz assesses.",
    QUIZ_MODULE_SCOPE_INVALID:
      "Every selected module must belong to the selected COC.",
    QUIZ_OUTCOME_SCOPE_INVALID:
      "Every learning outcome must belong to the selected modules.",
    QUIZ_TOPIC_SCOPE_INVALID:
      "Choose a published topic from one of the selected modules.",
    QUIZ_TIME_LIMIT_INVALID: "Use a time limit from 1 to 240 minutes.",
    QUIZ_TYPE_INVALID: "Choose pre-assessment, formative or summative.",
    QUIZ_DIFFICULTY_INVALID: "Choose foundation, intermediate or advanced.",
    QUIZ_RELEASE_MODE_INVALID: "Choose how results are released.",
    CREATE_DRAFT_TO_CHANGE_SETTINGS:
      "Published versions keep their instructions, time limit and release mode. Create a new draft version to change them.",
    QUIZ_CURRICULUM_UPDATE_REQUIRED:
      "Changing the COC of a mapped quiz also requires its modules, outcomes and focus.",
    QUIZ_ESSAY_RUBRIC_REQUIRED:
      "Scenario essays need at least one rubric criterion with positive points.",
    QUIZ_ESSAY_SCENARIO_REQUIRED: "Describe the scenario for this essay.",
    QUIZ_ESSAY_RUBRIC_INVALID:
      "Fix the rubric of each scenario essay before publishing.",
    QUIZ_WORD_GUIDANCE_INVALID:
      "Use word guidance from 1 to 5,000 with the minimum not above the maximum.",
    QUIZ_ITEM_POINTS_INVALID: "Use points greater than 0 and at most 100.",
    INVALID_QUIZ_ITEM: "Check the question type, options and answer.",
    QUIZ_UPLOAD_RESPONSE_UNSUPPORTED: QUIZ_UPLOAD_REQUEST_MESSAGE,
    FUTURE_DEADLINE_REQUIRED: "Choose a deadline that has not passed yet.",
  };
  return (
    Object.entries(known).find(([code]) => message.includes(code))?.[1] ??
    message
  );
}
