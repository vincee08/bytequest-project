import assert from "node:assert/strict";
import test from "node:test";
import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { AppRouterContext, type AppRouterInstance } from "next/dist/shared/lib/app-router-context.shared-runtime";
import { QuizResultsPanel, type ResultAttempt } from "../src/components/quizzes/QuizResultsPanel";
import { questionSchema, quizErrorMessage } from "../src/lib/quizzes/authoring";
import { QUIZ_UPLOAD_REQUEST_MESSAGE, quizTextRequestsUpload } from "../src/lib/quizzes/upload-requests";
import { learnerDisplayName, learnerSecondaryEmail } from "../src/lib/learners/identity";

// The SQL guard (supabase/tests/quiz_workflow_fixes_rollback.sql) checks the same phrases.
const asksForUpload = [
  "Explain your answer and attach one image of your crimped cable.",
  "Required: written answer and one image file.",
  "Upload a screenshot of your IP configuration.",
  "Take a clear photo of the wiring and submit it.",
  "Please upload your file.",
  "One image file is required for this item.",
];
const typedOnly = [
  "Why should a technician take a photo of the cable layout before disassembly?",
  "Which protocol is used to upload a file to a server?",
  "Which of these is an image file format?",
  "Attach the CPU fan cable to the CPU_FAN header.",
  "A user cannot open an attached image file in Outlook. Diagnose the cause.",
  "Provide the IP address and subnet mask you would assign.",
];

test("quiz questions that ask for an image or file are recognised; technical wording is not", () => {
  for (const text of asksForUpload) assert.equal(quizTextRequestsUpload(text), true, text);
  for (const text of typedOnly) assert.equal(quizTextRequestsUpload(text), false, text);
});

test("the question editor refuses an image request in the prompt, scenario or rubric", () => {
  const essay = {
    itemType: "scenario_essay" as const,
    prompt: "Explain the T568B order you used.",
    options: [],
    correctAnswer: "",
    explanation: "",
    scenario: "A client needs a new patch cable for a workstation.",
    rubric: [{ id: "C1", criterion: "Order", description: "Lists T568B colours", maxPoints: 5 }],
    minWords: null,
    maxWords: null,
  };
  assert.equal(questionSchema.safeParse(essay).success, true, "a typed essay is valid");
  const issues = (input: object) =>
    (questionSchema.safeParse(input).error?.issues ?? []).filter((issue) => issue.message === QUIZ_UPLOAD_REQUEST_MESSAGE);
  assert.deepEqual(issues({ ...essay, prompt: `${essay.prompt} Attach one image of your crimped cable.` }).map((i) => i.path[0]), ["prompt"]);
  assert.deepEqual(issues({ ...essay, scenario: "Required: written answer and one image file." }).map((i) => i.path[0]), ["scenario"]);
  assert.deepEqual(issues({ ...essay, rubric: [{ ...essay.rubric[0], description: "Upload a photo of the plug." }] }).map((i) => i.path[0]), ["rubric"]);
  assert.deepEqual(
    issues({ itemType: "identification", prompt: "Name the standard. Upload a screenshot of your tester.", options: [], correctAnswer: "T568B", explanation: "" })
      .map((i) => i.path[0]),
    ["prompt"],
  );
});

test("server refusals for upload requests and past deadlines read as instructions", () => {
  assert.equal(quizErrorMessage("QUIZ_UPLOAD_RESPONSE_UNSUPPORTED"), QUIZ_UPLOAD_REQUEST_MESSAGE);
  assert.match(QUIZ_UPLOAD_REQUEST_MESSAGE, /homework task that requires a written answer and an image/);
  assert.equal(quizErrorMessage("FUTURE_DEADLINE_REQUIRED"), "Choose a deadline that has not passed yet.");
});

const router: AppRouterInstance = { back() {}, forward() {}, refresh() {}, push() {}, replace() {}, prefetch() {} };
function attempt(profile: { full_name: string | null; email: string | null }, id: string): ResultAttempt {
  return {
    id, learnerId: `learner-${id}`, learner: learnerDisplayName(profile), learnerEmail: learnerSecondaryEmail(profile),
    classTitle: "ByteQuest Section A", versionNumber: 1, status: "completed", evaluationStatus: "not_required",
    submissionKind: "learner", submittedAt: "2026-11-23T01:00:00Z", percent: 100, score: 2, maxScore: 2, items: [], essays: [],
  };
}

test("quiz results name each learner and show their email, never only the class title", () => {
  const html = renderToStaticMarkup(
    <AppRouterContext.Provider value={router}>
      <QuizResultsPanel enrolled={2} attempts={[
        attempt({ full_name: "Ana Reyes", email: "ana.reyes@example.test" }, "a1"),
        attempt({ full_name: null, email: "no.name@example.test" }, "a2"),
      ]} />
    </AppRouterContext.Provider>,
  );
  assert.match(html, /Ana Reyes/);
  assert.match(html, /ana\.reyes@example\.test/);
  assert.match(html, /no\.name@example\.test/, "a learner without a profile name is shown by email");
  assert.doesNotMatch(html, />Learner</, "no generic Learner label");
  assert.match(html, /ByteQuest Section A/, "the class is still shown beside the attempt");
});
