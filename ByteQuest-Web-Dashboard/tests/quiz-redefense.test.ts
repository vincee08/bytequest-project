import assert from "node:assert/strict";
import test from "node:test";
import {
  fromRpcRubric,
  nextCriterionId,
  questionSchema,
  rubricTotal,
  toRpcRubric,
} from "../src/lib/quizzes/authoring";
import {
  outcomesForScope,
  pruneSelections,
  quizTopicLabel,
  scopeSummary,
  topicsForScope,
  type CurriculumCatalog,
} from "../src/lib/quizzes/curriculum";
import {
  emptyQuizForm,
  parseQuizForm,
  quizSettingsRpcArgs,
  scopeError,
} from "../src/lib/quizzes/form";
import {
  defaultLibraryFilters,
  filterLibrary,
  libraryStatus,
  type LibraryQuiz,
} from "../src/lib/quizzes/library";
import {
  isFinalScore,
  questionCorrectness,
  quizResultStats,
  type StatsAttempt,
} from "../src/lib/quizzes/results";
import {
  evaluationError,
  evaluationRpcPayload,
  quizEvaluationRequestSchema,
} from "../src/lib/quizzes/evaluation";

const COC1 = "00000000-0000-4000-8000-000000000001";
const COC2 = "00000000-0000-4000-8000-000000000002";
const LO11 = "00000000-0000-4000-8000-000000000011";
const LO12 = "00000000-0000-4000-8000-000000000012";
const LO21 = "00000000-0000-4000-8000-000000000021";
const PC14 = "00000000-0000-4000-8000-000000000114";
const PC31 = "00000000-0000-4000-8000-000000000131";
const PC15 = "00000000-0000-4000-8000-000000000215";
const TOPIC = "00000000-0000-4000-8000-000000000301";

const catalog: CurriculumCatalog = {
  cocs: [
    { id: COC1, code: "coc1", title: "Install and Configure Computer Systems" },
    { id: COC2, code: "coc2", title: "Set-up Computer Networks" },
  ],
  modules: [
    { id: LO12, cocId: COC1, cocCode: "coc1", code: "LO1.2", title: "Install operating system and drivers", sequenceOrder: 2 },
    { id: LO11, cocId: COC1, cocCode: "coc1", code: "LO1.1", title: "Assemble computer hardware", sequenceOrder: 1 },
    { id: LO21, cocId: COC2, cocCode: "coc2", code: "LO2.1", title: "Install network cables", sequenceOrder: 1 },
  ],
  outcomes: [
    { id: PC31, moduleId: LO12, code: "3.1", statement: "Operating system is installed", sequenceOrder: 4 },
    { id: PC14, moduleId: LO11, code: "1.4", statement: "Computer hardware is assembled", sequenceOrder: 4 },
    { id: PC15, moduleId: LO21, code: "1.5", statement: "Copper cable splicing is performed", sequenceOrder: 5 },
  ],
  topics: [
    { id: TOPIC, moduleId: LO11, title: "ESD-safe hardware assembly", summary: null, sequenceOrder: 1 },
  ],
};

const essay = {
  itemType: "scenario_essay" as const,
  prompt: "Explain how you would install the CPU safely.",
  options: [],
  correctAnswer: "",
  explanation: "",
  scenario: "A client left an unassembled workstation on your bench.",
  rubric: [
    { id: "C1", criterion: "Safety", description: "ESD precautions", maxPoints: 4 },
    { id: "C2", criterion: "Procedure", description: "Seating", maxPoints: 6 },
  ],
  minWords: 50,
  maxWords: 200,
};

test("scenario essays need a scenario and a rubric with positive points", () => {
  assert.ok(questionSchema.safeParse(essay).success);
  assert.equal(questionSchema.safeParse({ ...essay, scenario: "Short" }).success, false);
  assert.equal(questionSchema.safeParse({ ...essay, rubric: [] }).success, false);
  assert.equal(
    questionSchema.safeParse({ ...essay, rubric: [{ ...essay.rubric[0], maxPoints: 0 }] }).success,
    false,
  );
  assert.equal(questionSchema.safeParse({ ...essay, minWords: 300, maxWords: 100 }).success, false);
  assert.equal(
    questionSchema.safeParse({
      itemType: "multiple_choice",
      prompt: "Which tool prevents ESD?",
      options: ["Wrist strap", "Pliers"],
      correctAnswer: "Wrist strap",
      explanation: "",
      rubric: essay.rubric,
    }).success,
    false,
    "objective items cannot carry an essay rubric",
  );
  assert.equal(
    questionSchema.safeParse({
      itemType: "identification",
      prompt: "Name the routing device.",
      options: [],
      correctAnswer: "",
      explanation: "",
    }).success,
    false,
    "objective items still need an answer",
  );
});

test("rubric helpers keep ids, totals and the database shape", () => {
  assert.equal(rubricTotal(essay.rubric), 10);
  const rpc = toRpcRubric(essay.rubric);
  assert.deepEqual(rpc[0], { id: "C1", criterion: "Safety", description: "ESD precautions", max_points: 4 });
  assert.deepEqual(fromRpcRubric(rpc), essay.rubric);
  assert.deepEqual(fromRpcRubric("not-a-rubric"), []);
  assert.equal(nextCriterionId(essay.rubric), "C3");
  assert.equal(nextCriterionId([{ id: "C3" }]), "C2");
});

test("quiz settings require a COC, a focus and a valid time limit", () => {
  const form = { ...emptyQuizForm(), title: "Assembly check", focus: "Assess safe assembly" };
  assert.equal(parseQuizForm(form).success, false, "COC is required");
  const withCoc = { ...form, cocModuleId: COC1, scope: "coc" as const };
  assert.ok(parseQuizForm(withCoc).success);
  assert.equal(parseQuizForm({ ...withCoc, focus: " " }).success, false);
  assert.equal(parseQuizForm({ ...withCoc, timed: true, timeLimitMinutes: "0" }).success, false);
  assert.equal(parseQuizForm({ ...withCoc, timed: true, timeLimitMinutes: "241" }).success, false);
  assert.equal(parseQuizForm({ ...withCoc, timed: true, timeLimitMinutes: "" }).success, false);
  const timed = parseQuizForm({ ...withCoc, timed: true, timeLimitMinutes: "45" });
  assert.ok(timed.success && timed.data.timeLimitMinutes === 45);
  const untimed = parseQuizForm(withCoc);
  assert.ok(untimed.success && untimed.data.timeLimitMinutes === null);
  assert.equal(scopeError({ ...withCoc, scope: "modules", moduleIds: [] }), "Select at least one module, or choose the whole COC.");
  assert.equal(scopeError(withCoc), null);
});

test("RPC arguments use the whole-COC scope and a derived topic label", () => {
  const whole = parseQuizForm({
    ...emptyQuizForm(),
    title: "COC1 pre-assessment",
    focus: "Readiness across COC1",
    cocModuleId: COC1,
    scope: "coc",
    moduleIds: [LO11],
  });
  assert.ok(whole.success);
  const args = quizSettingsRpcArgs(whole.data, catalog);
  assert.deepEqual(args.p_module_ids, [], "whole-COC scope sends no modules");
  assert.equal(args.p_topic, "COC1 Install and Configure Computer Systems");
  assert.equal(args.p_time_limit_minutes, null);

  const scoped = parseQuizForm({
    ...emptyQuizForm(),
    title: "Assembly check",
    focus: "Safe assembly",
    cocModuleId: COC1,
    moduleIds: [LO11],
    topicId: TOPIC,
    outcomeIds: [PC14],
  });
  assert.ok(scoped.success);
  const scopedArgs = quizSettingsRpcArgs(scoped.data, catalog);
  assert.equal(scopedArgs.p_topic, "ESD-safe hardware assembly");
  assert.deepEqual(scopedArgs.p_outcome_ids, [PC14]);
  assert.equal(quizTopicLabel(catalog, COC1, [LO11, LO12], ""), "LO1.1 Assemble computer hardware; LO1.2 Install operating system and drivers");
});

test("curriculum helpers keep selections inside the chosen COC and modules", () => {
  assert.deepEqual(outcomesForScope(catalog, COC1, [LO11]).map((outcome) => outcome.code), ["1.4"]);
  assert.deepEqual(outcomesForScope(catalog, COC1, []).map((outcome) => outcome.code), ["1.4", "3.1"]);
  assert.deepEqual(topicsForScope(catalog, COC1, [LO12]), []);
  assert.deepEqual(pruneSelections(catalog, COC2, [LO11, LO21], TOPIC, [PC14, PC15]), {
    moduleIds: [LO21],
    topicId: "",
    outcomeIds: [PC15],
  });
  assert.equal(scopeSummary(catalog, COC1, []), "COC1 · Whole COC");
  assert.equal(scopeSummary(catalog, COC1, [LO12, LO11]), "COC1 · LO1.1, LO1.2");
  assert.equal(scopeSummary(catalog, null, []), "Not mapped to a COC");
});

const attempt = (overrides: Partial<StatsAttempt>): StatsAttempt => ({
  learnerId: "learner",
  status: "completed",
  evaluationStatus: "not_required",
  submissionKind: "learner",
  percent: 0,
  ...overrides,
});

test("result statistics use final scores only and count pending separately", () => {
  const stats = quizResultStats(
    [
      attempt({ learnerId: "a", percent: 40 }),
      attempt({ learnerId: "b", percent: 95 }),
      attempt({ learnerId: "c", evaluationStatus: "released", percent: 80 }),
      attempt({ learnerId: "d", evaluationStatus: "pending", percent: null }),
      attempt({ learnerId: "e", evaluationStatus: "evaluated", percent: 100 }),
      attempt({ learnerId: "f", status: "in_progress", percent: null }),
      attempt({ learnerId: "g", submissionKind: "auto_deadline", evaluationStatus: "finalized", percent: 61.5 }),
    ],
    10,
  );
  assert.equal(stats.participants, 7);
  assert.equal(stats.submitted, 6);
  assert.equal(stats.inProgress, 1);
  assert.equal(stats.completionRate, 60);
  assert.equal(stats.finalScores, 4);
  assert.equal(stats.pendingEvaluation, 2, "pending and evaluated-not-finalized are excluded");
  assert.equal(stats.average, 69.1, "(40 + 95 + 80 + 61.5) / 4");
  assert.equal(stats.highest, 95);
  assert.equal(stats.lowest, 40);
  assert.equal(stats.autoSubmitted, 1);
  assert.deepEqual(
    stats.distribution.map((band) => band.count),
    [1, 0, 1, 0, 1, 1],
  );
  assert.equal(isFinalScore("evaluated"), false);
});

test("empty and unenrolled results report nothing instead of zeros", () => {
  const stats = quizResultStats([attempt({ evaluationStatus: "pending", percent: null })], 0);
  assert.equal(stats.average, null);
  assert.equal(stats.highest, null);
  assert.equal(stats.lowest, null);
  assert.equal(stats.completionRate, null);
  assert.equal(stats.distribution.reduce((total, band) => total + band.count, 0), 0);
});

test("per-question results count correct answers and essay rubric points", () => {
  const item = (id: string, type: string, correct: boolean | null, answered = true) => ({
    item_id: id,
    type: type as "multiple_choice",
    prompt: `Question ${id}`,
    learner_answer: answered ? "answer" : null,
    answered,
    is_correct: correct,
    order_index: id === "q1" ? 1 : 2,
  });
  const rows = questionCorrectness(
    [
      { items: [item("q1", "multiple_choice", true), item("e1", "scenario_essay", null)] },
      { items: [item("q1", "multiple_choice", false, false), item("e1", "scenario_essay", null)] },
    ],
    new Map([["e1", [{ points: 8, max: 10 }, { points: 5, max: 10 }]]]),
  );
  assert.deepEqual(
    rows.map((row) => [row.itemId, row.rate, row.correct, row.answered, row.responses]),
    [
      ["q1", 50, 1, 1, 2],
      ["e1", 65, 0, 2, 2],
    ],
  );
});

const libraryQuiz = (overrides: Partial<LibraryQuiz>): LibraryQuiz => ({
  id: "quiz",
  title: "Quiz",
  topic: "Topic",
  cocId: COC1,
  coc: "COC1",
  moduleIds: [],
  moduleCodes: [],
  topicId: null,
  quizType: "formative",
  mapped: true,
  status: "published",
  hasDraft: false,
  version: 1,
  questionCount: 3,
  essayCount: 0,
  timeLimitMinutes: null,
  updatedAt: "2035-01-01T00:00:00Z",
  nextDueAt: null,
  ...overrides,
});

test("library status: draft, published, closed (all deadlines passed) and archived", () => {
  const now = Date.parse("2035-01-01T10:00:00Z");
  assert.equal(libraryStatus({ archived: false, hasPublished: false, assignmentDueDates: [], now }), "draft");
  assert.equal(libraryStatus({ archived: false, hasPublished: true, assignmentDueDates: [], now }), "published");
  assert.equal(
    libraryStatus({ archived: false, hasPublished: true, assignmentDueDates: ["2035-01-01T09:00:00Z", "2035-01-01T11:00:00Z"], now }),
    "published",
  );
  assert.equal(
    libraryStatus({ archived: false, hasPublished: true, assignmentDueDates: ["2035-01-01T09:00:00Z", "2035-01-01T10:00:00Z"], now }),
    "closed",
  );
  assert.equal(libraryStatus({ archived: false, hasPublished: true, assignmentDueDates: [null], now }), "published");
  assert.equal(libraryStatus({ archived: true, hasPublished: true, assignmentDueDates: [], now }), "archived");
});

test("library filters by COC, module (including whole-COC quizzes), type and status, with sorting", () => {
  const quizzes = [
    libraryQuiz({ id: "a", title: "Bravo", moduleIds: [LO11], nextDueAt: "2035-01-03T00:00:00Z" }),
    libraryQuiz({ id: "b", title: "Alpha", moduleIds: [], quizType: "summative", nextDueAt: "2035-01-02T00:00:00Z" }),
    libraryQuiz({ id: "c", title: "Charlie", cocId: COC2, moduleIds: [LO21], moduleCodes: ["LO2.1"], status: "closed" }),
    libraryQuiz({ id: "d", title: "Delta", status: "archived" }),
    libraryQuiz({ id: "e", title: "Echo", cocId: COC1, moduleIds: [], mapped: false }),
  ];
  const moduleCoc = new Map(catalog.modules.map((module) => [module.id, module.cocId]));
  const ids = (filters: Partial<typeof defaultLibraryFilters>) =>
    filterLibrary(quizzes, { ...defaultLibraryFilters, ...filters }, moduleCoc).map((quiz) => quiz.id);
  assert.deepEqual(ids({ sort: "title" }), ["b", "a", "c", "e"], "archived hidden by default");
  assert.deepEqual(ids({ cocId: COC2 }), ["c"]);
  assert.deepEqual(ids({ moduleId: LO11, sort: "title" }), ["b", "a"], "whole-COC quiz matches; unmapped does not");
  assert.deepEqual(ids({ quizType: "summative" }), ["b"]);
  assert.deepEqual(ids({ status: "closed" }), ["c"]);
  assert.deepEqual(ids({ status: "all", sort: "title" }), ["b", "a", "c", "d", "e"]);
  assert.deepEqual(ids({ sort: "due" }).slice(0, 2), ["b", "a"]);
  assert.deepEqual(ids({ search: "lo2.1" }), ["c"], "search covers module codes");
});

test("evaluation requests are validated before reaching the database", () => {
  const attemptId = "00000000-0000-4000-8000-00000000a001";
  const itemId = "00000000-0000-4000-8000-00000000b001";
  const score = quizEvaluationRequestSchema.safeParse({
    action: "score_essay",
    attempt_id: attemptId,
    item_id: itemId,
    criterion_scores: { C1: 3, C2: 5 },
    feedback: "Good ESD steps.",
  });
  assert.ok(score.success);
  assert.deepEqual(evaluationRpcPayload(score.data), {
    action: "score_essay",
    payload: { attempt_id: attemptId, item_id: itemId, criterion_scores: { C1: 3, C2: 5 }, feedback: "Good ESD steps." },
  });
  assert.equal(
    quizEvaluationRequestSchema.safeParse({ action: "score_essay", attempt_id: attemptId, item_id: itemId, criterion_scores: { C1: -1 } }).success,
    false,
  );
  assert.equal(
    quizEvaluationRequestSchema.safeParse({ action: "score_essay", attempt_id: attemptId, item_id: itemId, criterion_scores: {} }).success,
    false,
  );
  assert.equal(quizEvaluationRequestSchema.safeParse({ action: "finalize", attempt_ids: [] }).success, false);
  assert.equal(
    quizEvaluationRequestSchema.safeParse({ action: "release", attempt_ids: Array(51).fill(attemptId) }).success,
    false,
  );
  assert.equal(quizEvaluationRequestSchema.safeParse({ action: "approve", attempt_ids: [attemptId] }).success, false);
  assert.equal(
    quizEvaluationRequestSchema.safeParse({ action: "release", attempt_ids: [attemptId], extra: true }).success,
    false,
    "unknown fields are rejected",
  );
  assert.deepEqual(evaluationRpcPayload({ action: "release", attempt_ids: [attemptId] }), {
    action: "release",
    payload: { attempt_ids: [attemptId] },
  });
  assert.equal(evaluationError("QUIZ_RESULT_NOT_FINALIZED").status, 409);
  assert.equal(evaluationError("QUIZ_EVALUATION_SCOPE_DENIED").status, 403);
  assert.equal(evaluationError("QUIZ_ESSAY_NOT_ANSWERED").status, 409);
  assert.match(evaluationError("QUIZ_ESSAY_NOT_ANSWERED").error, /scores zero/);
  assert.equal(evaluationError("unexpected").status, 503);
});
