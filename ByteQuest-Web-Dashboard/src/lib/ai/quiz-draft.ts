import "server-only";

import { z } from "zod";

export const quizItemTypeSchema = z.enum([
  "multiple_choice",
  "true_false",
  "identification",
  "scenario_based",
  "scenario_essay",
]);

const draftRubricRowSchema = z.object({
  criterion: z.string().trim().min(2).max(200),
  description: z.string().trim().max(1000),
  maxPoints: z.number().int().min(1).max(20),
});

export const quizDraftQuestionSchema = z.object({
  question: z.string().trim().min(5).max(2000),
  type: quizItemTypeSchema,
  choices: z.array(z.string().trim().min(1).max(300)).max(6),
  correctAnswer: z.string().trim().min(1).max(2000),
  explanation: z.string().trim().min(1).max(1500),
  competency: z.string().trim().min(2).max(300),
  coc: z.string().trim().min(2).max(300),
  learningOutcome: z.string().trim().min(2).max(1000),
  // Present when scenario essays are requested.
  scenario: z.string().trim().max(4000).optional(),
  rubric: z.array(draftRubricRowSchema).max(8).optional(),
  minWords: z.number().int().min(0).max(5000).optional(),
  maxWords: z.number().int().min(0).max(5000).optional(),
});

export const quizDraftResponseSchema = z.object({
  questions: z.array(quizDraftQuestionSchema).min(1).max(10),
});

export const quizDraftItemSchema = z.object({
  item_type: quizItemTypeSchema,
  prompt: z.string().trim().min(5).max(2000),
  options: z.array(z.string().trim().min(1).max(300)).max(6),
  correct_answer: z.string().trim().max(2000),
  explanation: z.string().trim().min(1).max(1500),
  scenario: z.string().trim().max(4000).optional(),
  rubric: z
    .array(
      z.object({
        criterion: z.string(),
        description: z.string(),
        max_points: z.number(),
      }),
    )
    .optional(),
  min_words: z.number().int().nullable().optional(),
  max_words: z.number().int().nullable().optional(),
});

export type QuizItemType = z.infer<typeof quizItemTypeSchema>;
export type QuizDraftQuestion = z.infer<typeof quizDraftQuestionSchema>;
export type QuizDraftItem = z.infer<typeof quizDraftItemSchema>;

export interface QuizGenerationGrounding {
  qualification: { code: string; title: string };
  source: { id: string; title: string; edition: string; reference: string };
  coc: { id: string; code: string; title: string };
  competency: { id: string; code: string; title: string; sourceTrace: string };
  module: { id: string; title: string; version: number; sourceTrace: unknown };
  activity: {
    id: string;
    title: string;
    version: number;
    instructions: string | null;
  };
  mission: {
    id: string;
    number: number;
    title: string;
    objective: string;
    scenario: string;
    skillsAssessed: string[];
  };
  rubric: { id: string; title: string; version: number };
  criteria: Array<{
    code: string;
    title: string;
    description: string | null;
    required: boolean;
    sourceTrace: string;
  }>;
}

/**
 * Curriculum grounding: the quiz's COC, modules (official curriculum learning
 * outcomes), the official performance criteria it assesses, its published
 * topic text and the instructor's stated focus.
 */
export interface QuizCurriculumGrounding {
  coc: { id: string; code: string; title: string };
  modules: { id: string; code: string; title: string }[];
  outcomes: { id: string; code: string; module: string; statement: string }[];
  topic: { id: string; title: string; summary: string | null; excerpt: string } | null;
  focus: string;
  quizType: string | null;
  difficulty: string | null;
}

export interface QuizDraftRequest {
  quizTitle: string;
  topic: string;
  instructorContext: string | null;
  difficulty: "foundation" | "intermediate" | "advanced";
  itemCount: number;
  itemTypes: QuizItemType[];
  grounding?: QuizGenerationGrounding;
  curriculum?: QuizCurriculumGrounding;
  resource?: { title: string; text: string };
}

/** Label each generated question must use to name the criterion it assesses. */
export function outcomeLabel(outcome: { code: string; module: string }) {
  return `PC ${outcome.code} (${outcome.module})`;
}

export function quizDraftAlignment(request: QuizDraftRequest): {
  competency: string;
  coc: string;
  learningOutcome: string;
  learningOutcomes?: string[];
} {
  if (request.resource && !request.grounding && !request.curriculum)
    return {
      competency: "Supplementary learning",
      coc: "Supplementary",
      learningOutcome: request.topic,
    };
  if (request.curriculum && !request.grounding && !request.resource) {
    const labels = request.curriculum.outcomes.map(outcomeLabel);
    const allowed = labels.length
      ? labels
      : request.curriculum.modules.map((module) => module.code);
    return {
      competency: `${request.curriculum.coc.code.toUpperCase()} ${request.curriculum.coc.title}`,
      coc: request.curriculum.coc.code.toUpperCase(),
      learningOutcome: allowed[0] ?? request.curriculum.focus,
      learningOutcomes: allowed.length ? allowed : undefined,
    };
  }
  if (!request.grounding || request.resource || request.curriculum)
    throw new Error("AI_SOURCE_REQUIRED");
  return {
    competency: request.grounding.competency.title,
    coc: `${request.grounding.coc.code} - ${request.grounding.coc.title}`,
    learningOutcome: request.grounding.mission.objective,
  };
}

function normalize(value: string) {
  return value.trim().replace(/\s+/g, " ");
}

function validateQuestionContract(
  question: QuizDraftQuestion,
  request: QuizDraftRequest,
) {
  if (!request.itemTypes.includes(question.type)) return false;
  const alignment = quizDraftAlignment(request);
  if (normalize(question.competency) !== normalize(alignment.competency))
    return false;
  if (normalize(question.coc) !== normalize(alignment.coc)) return false;
  if (alignment.learningOutcomes) {
    if (!alignment.learningOutcomes.includes(normalize(question.learningOutcome)))
      return false;
  } else if (
    normalize(question.learningOutcome) !== normalize(alignment.learningOutcome)
  )
    return false;

  if (question.type === "scenario_essay") {
    const rubric = question.rubric ?? [];
    const names = new Set(
      rubric.map((row) => normalize(row.criterion).toLocaleLowerCase()),
    );
    const min = question.minWords || null;
    const max = question.maxWords || null;
    return (
      question.choices.length === 0 &&
      normalize(question.scenario ?? "").length >= 20 &&
      rubric.length >= 1 &&
      rubric.length <= 8 &&
      names.size === rubric.length &&
      (min === null || max === null || min <= max)
    );
  }
  if ((question.rubric?.length ?? 0) > 0) return false;
  if (question.correctAnswer.length > 500) return false;

  if (
    question.type === "multiple_choice" ||
    question.type === "scenario_based"
  ) {
    const uniqueChoices = new Set(
      question.choices.map((choice) => normalize(choice).toLocaleLowerCase()),
    );
    return (
      question.choices.length >= 2 &&
      uniqueChoices.size === question.choices.length &&
      question.choices.includes(question.correctAnswer)
    );
  }

  if (question.type === "true_false") {
    return (
      question.choices.length === 0 &&
      ["true", "false"].includes(question.correctAnswer.toLocaleLowerCase())
    );
  }

  return question.choices.length === 0;
}

export function normalizeAndValidateQuizDraft(
  payload: unknown,
  request: QuizDraftRequest,
): QuizDraftItem[] {
  const parsed = quizDraftResponseSchema.safeParse(payload);
  if (!parsed.success || parsed.data.questions.length !== request.itemCount) {
    throw new Error("AI_DRAFT_CONTRACT_INVALID");
  }

  const prompts = new Set<string>();
  for (const question of parsed.data.questions) {
    if (!validateQuestionContract(question, request))
      throw new Error("AI_DRAFT_QUESTION_INVALID");
    const key = normalize(question.question).toLocaleLowerCase();
    if (prompts.has(key)) throw new Error("AI_DRAFT_DUPLICATE_QUESTION");
    prompts.add(key);
  }

  return parsed.data.questions.map((question) => {
    const base = {
      item_type: question.type,
      prompt: normalize(question.question),
      options: question.choices.map(normalize),
      correct_answer:
        question.type === "true_false"
          ? question.correctAnswer.toLocaleLowerCase()
          : normalize(question.correctAnswer),
      explanation: normalize(question.explanation),
    };
    if (question.type !== "scenario_essay") return base;
    return {
      ...base,
      scenario: question.scenario?.trim() ?? "",
      rubric: (question.rubric ?? []).map((row) => ({
        criterion: normalize(row.criterion),
        description: normalize(row.description),
        max_points: row.maxPoints,
      })),
      min_words: question.minWords || null,
      max_words: question.maxWords || null,
    };
  });
}
