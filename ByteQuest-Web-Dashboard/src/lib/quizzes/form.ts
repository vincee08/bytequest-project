import { quizSettingsSchema, type QuizSettingsInput } from "./authoring";
import { quizTopicLabel, type CurriculumCatalog } from "./curriculum";
import type { QuizDifficulty, QuizType, ResultReleaseMode } from "./types";

/** Editable state of the quiz create/settings form. */
export interface QuizFormState {
  title: string;
  cocModuleId: string;
  scope: "coc" | "modules";
  moduleIds: string[];
  topicId: string;
  outcomeIds: string[];
  focus: string;
  description: string;
  instructions: string;
  quizType: QuizType;
  difficulty: QuizDifficulty;
  timed: boolean;
  timeLimitMinutes: string;
  resultReleaseMode: ResultReleaseMode;
}

export function emptyQuizForm(): QuizFormState {
  return {
    title: "",
    cocModuleId: "",
    scope: "modules",
    moduleIds: [],
    topicId: "",
    outcomeIds: [],
    focus: "",
    description: "",
    instructions: "",
    quizType: "formative",
    difficulty: "foundation",
    timed: false,
    timeLimitMinutes: "30",
    resultReleaseMode: "immediate",
  };
}

export function parseQuizForm(state: QuizFormState) {
  const minutes = Number(state.timeLimitMinutes);
  return quizSettingsSchema.safeParse({
    title: state.title,
    cocModuleId: state.cocModuleId,
    moduleIds: state.scope === "coc" ? [] : state.moduleIds,
    topicId: state.topicId,
    outcomeIds: state.outcomeIds,
    focus: state.focus,
    description: state.description,
    instructions: state.instructions,
    quizType: state.quizType,
    difficulty: state.difficulty,
    timeLimitMinutes: state.timed
      ? state.timeLimitMinutes.trim() === ""
        ? Number.NaN
        : minutes
      : null,
    resultReleaseMode: state.resultReleaseMode,
  });
}

/** Extra validation the schema cannot express: module scope needs a module. */
export function scopeError(state: QuizFormState) {
  return state.scope === "modules" && state.moduleIds.length === 0
    ? "Select at least one module, or choose the whole COC."
    : null;
}

/** Named parameters for create_instructor_quiz / update_instructor_quiz. */
export function quizSettingsRpcArgs(
  input: QuizSettingsInput,
  catalog: CurriculumCatalog,
) {
  return {
    p_title: input.title,
    p_topic: quizTopicLabel(
      catalog,
      input.cocModuleId,
      input.moduleIds,
      input.topicId,
    ),
    p_description: input.description || null,
    p_coc_module_id: input.cocModuleId,
    p_instructions: input.instructions || null,
    p_focus: input.focus,
    p_quiz_type: input.quizType,
    p_difficulty: input.difficulty,
    p_topic_id: input.topicId || null,
    p_module_ids: input.moduleIds,
    p_outcome_ids: input.outcomeIds,
    p_time_limit_minutes: input.timeLimitMinutes,
    p_result_release_mode: input.resultReleaseMode,
  };
}

export function formFromQuiz(input: {
  title: string;
  description: string | null;
  cocModuleId: string | null;
  moduleIds: string[];
  topicId: string | null;
  outcomeIds: string[];
  focus: string | null;
  quizType: QuizType | null;
  difficulty: QuizDifficulty | null;
  instructions: string | null;
  timeLimitMinutes: number | null;
  resultReleaseMode: ResultReleaseMode;
}): QuizFormState {
  return {
    title: input.title,
    cocModuleId: input.cocModuleId ?? "",
    scope: input.cocModuleId && input.focus && !input.moduleIds.length ? "coc" : "modules",
    moduleIds: input.moduleIds,
    topicId: input.topicId ?? "",
    outcomeIds: input.outcomeIds,
    focus: input.focus ?? "",
    description: input.description ?? "",
    instructions: input.instructions ?? "",
    quizType: input.quizType ?? "formative",
    difficulty: input.difficulty ?? "foundation",
    timed: input.timeLimitMinutes !== null,
    timeLimitMinutes: String(input.timeLimitMinutes ?? 30),
    resultReleaseMode: input.resultReleaseMode,
  };
}
