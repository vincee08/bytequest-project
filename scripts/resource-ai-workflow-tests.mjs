import assert from "node:assert/strict";
import fs from "node:fs";
import { randomUUID } from "node:crypto";
import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";
import { textPdf } from "./fixtures/resource-pdf.mjs";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
if (url !== "http://127.0.0.1:58921")
  throw new Error("Dedicated QA backend required.");
const base = "http://localhost:3008";
const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
const service = createClient(url, process.env.SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});
const fixture = JSON.parse(
  fs.readFileSync(".tmp/quiz-preview-accounts.json", "utf8"),
);
const { chromium } = process.env.BQ_PLAYWRIGHT_MODULE
  ? await import(pathToFileURL(process.env.BQ_PLAYWRIGHT_MODULE).href)
  : await import("playwright");
const browser = await chromium.launch({ headless: true });
const run = randomUUID().slice(0, 8);
const pass = (message) => console.log(`PASS ${message}`);
async function ok(promise) {
  const { data, error } = await promise;
  assert(!error, error?.message);
  return data;
}
async function denied(promise, code) {
  const { error } = await promise;
  assert(
    error && error.message.includes(code),
    error?.message ?? "Expected denial",
  );
}
async function login(account) {
  const cookies = [];
  const client = createServerClient(url, key, {
    cookies: {
      getAll: () => cookies,
      setAll: (values) => {
        for (const value of values) {
          const index = cookies.findIndex(
            (cookie) => cookie.name === value.name,
          );
          if (index >= 0) cookies[index] = value;
          else cookies.push(value);
        }
      },
    },
  });
  await ok(
    client.auth.signInWithPassword({
      email: account.email,
      password: account.password,
    }),
  );
  const context = await browser.newContext({
    viewport: { width: 1440, height: 1000 },
    reducedMotion: "reduce",
  });
  await context.addCookies(
    cookies.map((cookie) => ({
      name: cookie.name,
      value: cookie.value,
      url: base,
      httpOnly: false,
      sameSite: "Lax",
    })),
  );
  return { client, context, request: context.request };
}
const users = {};
async function runTests() {
  for (const name of [
    "instructor",
    "otherInstructor",
    "learner",
    "resumeLearner",
    "outsider",
  ])
    users[name] = await login(fixture.accounts[name]);
  const teacher = users.instructor.client;
  if (process.argv.includes("--missing-config")) {
    const saved = JSON.parse(fs.readFileSync(".tmp/resource-ai-test-fixture.json", "utf8"));
    const status = await (await users.instructor.request.get(`${base}/api/instructor/quizzes/ai-draft`)).json();
    assert.equal(status.configured, false, "This probe requires AI disabled; no generation request was made.");
    const draft = await ok(teacher.from("quiz_versions").select("id").eq("status", "draft").limit(1).single());
    const before = await ok(teacher.from("ai_quiz_generations").select("id"));
    const response = await users.instructor.request.post(`${base}/api/instructor/quizzes/ai-draft`, { data: { quizVersionId: draft.id, sourceMode: "class_resource", classId: saved.classId, resourceId: saved.resourceId, externalConsent: true, topic: "Missing configuration check", difficulty: "foundation", itemCount: 1, itemTypes: ["multiple_choice"] } });
    assert.equal(response.status(), 503);
    assert.match((await response.json()).error, /not configured/);
    assert.equal((await ok(teacher.from("ai_quiz_generations").select("id"))).length, before.length);
    pass("missing OpenRouter configuration returns an actionable 503 without creating a generation or contacting a provider");
    return;
  }
  if (process.argv.includes("--ui-only")) {
    const saved = JSON.parse(
      fs.readFileSync(".tmp/resource-ai-test-fixture.json", "utf8"),
    );
    await browserTests(teacher, { id: saved.classId });
    return;
  }
  const learner = users.learner.client;
  const classA = await ok(
    teacher.rpc("create_class", {
      p_title: `Resource QA ${run}`,
      p_class_code: `RES-${run}`,
    }),
  );
  const classB = await ok(
    teacher.rpc("create_class", {
      p_title: `Resource QA second ${run}`,
      p_class_code: `REB-${run}`,
    }),
  );
  for (const cls of [classA, classB])
    for (const name of ["learner", "resumeLearner"])
      await ok(
        teacher.rpc("enroll_learner", {
          p_class_id: cls.id,
          p_learner_id: fixture.accounts[name].id,
        }),
      );
  const api = users.instructor.request;
  async function upload(
    buffer,
    title = `Network reference ${run}`,
    mimeType = "application/pdf",
    actor = users.instructor,
    target = classA.id,
  ) {
    return actor.request.post(`${base}/api/classes/${target}/resources`, {
      timeout: 120_000,
      multipart: { title, file: { name: "qa-resource", mimeType, buffer } },
    });
  }
  const first = await upload(textPdf());
  assert.equal(first.status(), 201, await first.text());
  const resource = (await first.json()).resource;
  const retries = await Promise.all(
    Array.from({ length: 4 }, () => upload(textPdf())),
  );
  for (const retry of retries) {
    assert.equal(retry.status(), 200);
    assert.equal((await retry.json()).resource.id, resource.id);
  }
  const listing = await api.get(`${base}/api/classes/${classA.id}/resources`);
  assert(
    (await listing.json()).resources.some((item) => item.id === resource.id),
  );
  assert.equal(
    (await upload(Buffer.from("bad PDF"), "Forged PDF")).status(),
    415,
  );
  assert.equal(
    (await upload(Buffer.from("text"), "Unsupported", "text/plain")).status(),
    415,
  );
  assert.equal(
    (await upload(Buffer.alloc(50 * 1024 * 1024 + 1), "Oversized")).status(),
    413,
  );
  const boundary = Buffer.alloc(50 * 1024 * 1024, 32);
  textPdf().copy(boundary);
  const maximum = await upload(boundary, `50 MB boundary ${run}`);
  assert.equal(maximum.status(), 201, await maximum.text());
  assert.equal(
    (
      await upload(
        textPdf(),
        "Denied",
        "application/pdf",
        users.otherInstructor,
      )
    ).status(),
    403,
  );
  assert.equal(
    (
      await upload(
        textPdf(),
        "Learner upload",
        "application/pdf",
        users.learner,
      )
    ).status(),
    403,
  );
  pass(
    "PDF upload, same-content retry deduplication, listing, 50 MB boundary and role/class upload denials",
  );
  const failTitle = `QA_METADATA_FAILURE_${run}`;
  const triggerName = `qa_resource_failure_${run}`;
  const sql = (input) => {
    const result = spawnSync(
      "docker",
      [
        "exec",
        "-i",
        "supabase_db_BQQuizQA20261112",
        "psql",
        "-U",
        "postgres",
        "-d",
        "postgres",
        "-v",
        "ON_ERROR_STOP=1",
        "-q",
      ],
      { input, encoding: "utf8" },
    );
    assert.equal(result.status, 0, result.stderr);
  };
  // Disposable invoker trigger, restricted to this synthetic class/title only.
  // It exercises the real RPC compensation path without changing a production function.
  sql(
    `create function public.${triggerName}() returns trigger language plpgsql security invoker set search_path='' as $$ begin raise exception 'QA_METADATA_REJECTED' using errcode='22023'; end $$; create trigger ${triggerName} before insert on public.learning_resources for each row when(new.class_id='${classA.id}'::uuid and new.title='${failTitle}') execute function public.${triggerName}();`,
  );
  try {
    const failure = await upload(textPdf(), failTitle);
    assert.equal(failure.status(), 403, await failure.text());
    assert.equal(
      (
        await ok(
          service
            .from("learning_resources")
            .select("id")
            .eq("class_id", classA.id)
            .eq("title", failTitle),
        )
      ).length,
      0,
    );
    const job = await ok(
      service
        .from("resource_upload_jobs")
        .select("*")
        .eq("class_id", classA.id)
        .eq("state", "cleaned")
        .single(),
    );
    assert(
      (
        await service.storage
          .from("learning-resources")
          .download(job.storage_path)
      ).error,
    );
  } finally {
    sql(
      `drop trigger ${triggerName} on public.learning_resources; drop function public.${triggerName}();`,
    );
  }
  pass(
    "real metadata rejection removes the private object, leaves no broken resource row and records completed compensation",
  );
  const storageContainer = "supabase_storage_BQQuizQA20261112";
  const stopped = spawnSync(
    "docker",
    ["stop", "--time", "1", storageContainer],
    { encoding: "utf8" },
  );
  assert.equal(stopped.status, 0, "Dedicated QA Storage stop failed.");
  try {
    const failure = await upload(textPdf(), `Storage offline ${run}`);
    assert.equal(failure.status(), 503, await failure.text());
    assert.match((await failure.json()).error, /Storage.*unavailable/i);
    assert.equal(
      (
        await ok(
          service
            .from("learning_resources")
            .select("id")
            .eq("class_id", classA.id)
            .eq("title", `Storage offline ${run}`),
        )
      ).length,
      0,
    );
  } finally {
    const restarted = spawnSync("docker", ["start", storageContainer], {
      encoding: "utf8",
    });
    assert.equal(restarted.status, 0, "Dedicated QA Storage restart failed.");
    let ready = false;
    for (let index = 0; index < 90; index++) {
      if (!(await service.storage.listBuckets()).error) {
        ready = true;
        break;
      }
      await new Promise((resolve) => setTimeout(resolve, 500));
    }
    assert(ready, "QA Storage did not become ready after restart.");
  }
  pass(
    "real isolated Storage outage returns a service-specific 503 without a broken metadata record; Storage restarted",
  );
  for (const name of ["instructor", "learner"]) {
    const download = await users[name].request.get(
      `${base}/api/classes/${classA.id}/resources/${resource.id}`,
    );
    assert.equal(download.status(), 200, `${name} download`);
    assert(Buffer.from(await download.body()).equals(textPdf()));
  }
  for (const name of ["otherInstructor", "outsider"]) {
    const response = await users[name].request.get(
      `${base}/api/classes/${classA.id}/resources/${resource.id}`,
    );
    assert.equal(response.status(), 404);
    assert(
      (
        await users[name].client.storage
          .from("learning-resources")
          .download(resource.storage_path)
      ).error,
    );
  }
  assert.equal(
    (
      await api.get(`${base}/api/classes/${classB.id}/resources/${resource.id}`)
    ).status(),
    404,
  );
  assert.equal(
    (
      await fetch(
        `${url}/storage/v1/object/public/learning-resources/${resource.storage_path}`,
      )
    ).ok,
    false,
  );
  assert((await learner.from("resource_upload_jobs").select("*")).error);
  pass(
    "private Storage and download access for enrolled learners; outsider, cross-class, public and upload-journal denials",
  );
  for (const [mime, buffer] of [
    ["image/png", Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])],
    ["image/jpeg", Buffer.from([255, 216, 255, 224])],
    ["image/webp", Buffer.from("RIFF0000WEBP")],
    ["video/mp4", Buffer.from("0000ftypisom")],
    ["video/webm", Buffer.from([26, 69, 223, 163])],
  ]) {
    const response = await upload(buffer, `${mime} signature ${run}`, mime);
    assert.equal(response.status(), 201, await response.text());
  }
  pass(
    "all existing image/video MIME and signature upload paths remain accepted (synthetic byte fixtures)",
  );
  const quiz = await ok(
    teacher.rpc("create_instructor_quiz", {
      p_title: `Resource supplementary ${run}`,
      p_topic: "Network review",
    }),
  );
  const version = await ok(
    teacher.from("quiz_versions").select("*").eq("quiz_id", quiz.id).single(),
  );
  const request = {
    quizVersionId: version.id,
    sourceMode: "class_resource",
    classId: classA.id,
    resourceId: resource.id,
    topic: "Network routing review",
    difficulty: "foundation",
    itemCount: 4,
    itemTypes: [
      "multiple_choice",
      "true_false",
      "identification",
      "scenario_based",
    ],
    externalConsent: true,
    requestId: randomUUID(),
  };
  const generate = (data, actor = users.instructor) =>
    actor.request.post(`${base}/api/instructor/quizzes/ai-draft`, {
      data,
      timeout: 120_000,
    });
  assert.equal(
    (await generate({ ...request, externalConsent: false })).status(),
    400,
  );
  assert.equal(
    (await generate({ ...request, resourceId: randomUUID() })).status(),
    404,
  );
  assert.equal(
    (await generate({ ...request, classId: classB.id })).status(),
    404,
  );
  assert.equal((await generate(request, users.otherInstructor)).status(), 403);
  assert.equal((await generate(request, users.learner)).status(), 403);
  assert.equal(
    (
      await generate({
        ...request,
        sourceMode: "approved_coc",
        activityVersionId: randomUUID(),
      })
    ).status(),
    422,
  );
  pass(
    "resource AI authorization, selected-class isolation, required external consent and preserved COC eligibility",
  );
  const status = await (
    await api.get(`${base}/api/instructor/quizzes/ai-draft`)
  ).json();
  if (!status.simulated)
    throw new Error(
      "Run this automated suite with the explicitly labelled local provider simulator.",
    );
  for (const [buffer, message] of [
    [Buffer.from("%PDF-1.4\nbroken\n%%EOF"), "could not be read"],
    [textPdf(""), "OCR"],
  ]) {
    const uploaded = await upload(buffer, `Unreadable ${message} ${run}`);
    const id = (await uploaded.json()).resource.id;
    const response = await generate({
      ...request,
      resourceId: id,
      requestId: randomUUID(),
    });
    assert.equal(response.status(), 422, await response.text());
    assert((await response.json()).error.includes(message));
  }
  const invalid = await generate({
    ...request,
    topic: "QA_INVALID_RESPONSE",
    requestId: randomUUID(),
  });
  assert.equal(invalid.status(), 502);
  const limited = await generate({
    ...request,
    topic: "QA_RATE_LIMIT",
    requestId: randomUUID(),
  });
  assert.equal(limited.status(), 429);
  assert.equal(limited.headers()["retry-after"], "1");
  assert.equal(
    (
      await ok(
        teacher
          .from("quiz_items")
          .select("id")
          .eq("quiz_version_id", version.id),
      )
    ).length,
    0,
  );
  pass(
    "unreadable/scanned PDFs and invalid/rate-limited provider responses save no questions",
  );
  const baselineRequests = (await (await fetch("http://127.0.0.1:3007")).json())
    .requests;
  const concurrent = await Promise.all(
    Array.from({ length: 5 }, () => generate(request)),
  );
  assert.equal(
    concurrent.filter((response) => response.status() === 201).length,
    1,
    await Promise.all(
      concurrent.map(async (response) => ({
        status: response.status(),
        body: await response.text(),
      })),
    ),
  );
  assert(
    concurrent.every((response) => [201, 409].includes(response.status())),
  );
  const retry = await generate(request);
  assert.equal(retry.status(), 200);
  assert((await retry.json()).reused);
  assert.equal(
    (await (await fetch("http://127.0.0.1:3007")).json()).requests -
      baselineRequests,
    1,
  );
  const items = await ok(
    teacher
      .from("quiz_items")
      .select("*")
      .eq("quiz_version_id", version.id)
      .order("order_index"),
  );
  assert.equal(items.length, 4);
  assert(
    items.every(
      (item) =>
        item.review_status === "draft" && item.origin === "ai_generated_draft",
    ),
  );
  const generation = await ok(
    service
      .from("ai_quiz_generations")
      .select("*")
      .eq("id", items[0].ai_generation_id)
      .single(),
  );
  assert.equal(generation.input_context.classification, "supplementary");
  assert.equal(generation.input_context.resource_id, resource.id);
  assert(
    !JSON.stringify(generation.input_context).includes("A router connects"),
  );
  await denied(
    teacher.rpc("publish_and_assign_quiz", {
      p_quiz_version_id: version.id,
      p_class_ids: [classA.id],
    }),
    "APPROVED_QUIZ_ITEM_REQUIRED",
  );
  for (const item of items)
    await ok(
      teacher.rpc("review_quiz_item", {
        p_item_id: item.id,
        p_decision: "approved",
      }),
    );
  const publication = await ok(
    teacher.rpc("publish_and_assign_quiz", {
      p_quiz_version_id: version.id,
      p_class_ids: [classA.id, classB.id],
    }),
  );
  pass(
    "one provider call under concurrent retries, idempotent draft persistence, private provenance, review required and reason-free publication",
  );
  const assignments = publication.assignments;
  const starts = await Promise.all(
    Array.from({ length: 12 }, (_, index) =>
      ok(
        learner.rpc("start_learner_quiz", {
          p_assignment_id: assignments[index % 2].id,
          p_client_start_key: randomUUID(),
        }),
      ),
    ),
  );
  const attemptId = starts[0].attempt_id;
  assert.equal(new Set(starts.map((item) => item.attempt_id)).size, 1);
  assert(
    !/ai_generated|ai_generation|provider|source_mode|resource_id|correct_answer|explanation/.test(
      JSON.stringify(starts),
    ),
  );
  for (const item of items)
    await ok(
      learner.rpc("save_learner_quiz_answer", {
        p_attempt_id: attemptId,
        p_item_id: item.id,
        p_answer: item.correct_answer,
      }),
    );
  const fresh = await login(fixture.accounts.learner);
  const resumed = await ok(
    fresh.client.rpc("start_learner_quiz", {
      p_assignment_id: assignments[1].id,
      p_client_start_key: randomUUID(),
    }),
  );
  assert.equal(resumed.attempt_id, attemptId);
  assert(resumed.questions.every((item) => item.saved_answer));
  const grades = await Promise.all(
    Array.from({ length: 8 }, () =>
      ok(
        fresh.client.rpc("submit_learner_quiz", {
          p_attempt_id: attemptId,
          p_submission_key: randomUUID(),
        }),
      ),
    ),
  );
  assert(grades.every((grade) => grade.correct_count === 4));
  assert.equal(
    (
      await ok(
        service
          .from("quiz_results")
          .select("id")
          .eq("quiz_attempt_id", attemptId),
      )
    ).length,
    1,
  );
  await denied(
    fresh.client.rpc("start_learner_quiz", {
      p_assignment_id: assignments[0].id,
      p_client_start_key: randomUUID(),
    }),
    "QUIZ_ATTEMPT_ALREADY_SUBMITTED",
  );
  assert(
    !/ai_generated|ai_generation|provider|source_mode|resource_id/.test(
      JSON.stringify(
        await ok(
          fresh.client.rpc("get_learner_quiz_result", {
            p_attempt_id: attemptId,
          }),
        ),
      ),
    ),
  );
  pass(
    "AI quiz uses ordinary answer/result contracts with no provenance; cross-class/device resume, 12 concurrent starts, 8 submissions, one grade and no retake",
  );
  const next = await ok(
    teacher.rpc("create_quiz_version", {
      p_quiz_id: quiz.id,
      p_change_summary: "AI single-attempt republication regression",
    }),
  );
  const nextItem = await ok(
    teacher.rpc("upsert_quiz_item", {
      p_quiz_version_id: next.id,
      p_item_type: "true_false",
      p_prompt: "A router connects networks.",
      p_options: [],
      p_correct_answer: "true",
    }),
  );
  await ok(
    teacher.rpc("review_quiz_item", {
      p_item_id: nextItem.id,
      p_decision: "approved",
    }),
  );
  const nextPublished = await ok(
    teacher.rpc("publish_and_assign_quiz", {
      p_quiz_version_id: next.id,
      p_class_ids: [classB.id],
    }),
  );
  await denied(
    learner.rpc("start_learner_quiz", {
      p_assignment_id: nextPublished.assignments[0].id,
      p_client_start_key: randomUUID(),
    }),
    "QUIZ_ATTEMPT_ALREADY_SUBMITTED",
  );
  assert.equal(
    (
      await ok(
        teacher
          .from("quiz_results")
          .select("*")
          .eq("quiz_attempt_id", attemptId),
      )
    )[0].correct_count,
    4,
  );
  pass(
    "AI/manual mixed republication preserves the same quiz identity, blocks retakes and retains instructor results",
  );

  fs.writeFileSync(
    ".tmp/resource-ai-test-fixture.json",
    JSON.stringify({
      classId: classA.id,
      resourceId: resource.id,
      quizId: quiz.id,
    }),
  );
  await browserTests(teacher, classA);
}

async function browserTests(teacher, classA) {
  // Browser component behavior is automated validation, not owner acceptance.
  const draftQuiz = await ok(
    teacher.rpc("create_instructor_quiz", {
      p_title: `AI assistant UI ${run}`,
      p_topic: "Network UI review",
    }),
  );
  const page = await users.instructor.context.newPage();
  await page.goto(`${base}/classes/${classA.id}?tab=resources`);
  await page.getByLabel("Resource title").fill(`Browser PDF ${run}`);
  await page
    .getByLabel("File", { exact: true })
    .setInputFiles({
      name: "browser.pdf",
      mimeType: "application/pdf",
      buffer: textPdf(),
    });
  await page
    .getByRole("button", { name: "Upload resource", exact: true })
    .click();
  await page.getByText(`Browser PDF ${run}`, { exact: true }).waitFor();
  await page.goto(`${base}/quizzes/${draftQuiz.id}`);
  await page.getByRole("tab", { name: "AI assistant", exact: true }).click();
  await page
    .getByRole("radio", { name: "My Class Resource", exact: true })
    .check();
  await page.getByLabel("Class", { exact: true }).selectOption(classA.id);
  const browserResource = await ok(
    teacher
      .from("learning_resources")
      .select("id")
      .eq("class_id", classA.id)
      .eq("title", `Browser PDF ${run}`)
      .single(),
  );
  await page.getByLabel("Uploaded resource").selectOption(browserResource.id);
  await page
    .getByLabel("Quiz focus", { exact: true })
    .fill("Keep these AI focus settings");
  await page.getByRole("tab", { name: "Settings", exact: true }).click();
  await page.getByRole("tab", { name: "AI assistant", exact: true }).click();
  assert.equal(
    await page.getByLabel("Quiz focus", { exact: true }).inputValue(),
    "Keep these AI focus settings",
  );
  assert.equal(
    await page.getByLabel("Uploaded resource").inputValue(),
    browserResource.id,
  );
  await page
    .getByRole("radio", { name: "Approved COC Content", exact: true })
    .check();
  await page
    .getByText("No approved context available", { exact: true })
    .waitFor({ state: "attached" });
  await page
    .getByRole("radio", { name: "My Class Resource", exact: true })
    .check();
  await page.getByLabel(/I confirm that this content/).check();
  await page.getByLabel("Questions", { exact: true }).fill("4");
  for (const label of ["True or false", "Identification", "Scenario-based"])
    await page.getByLabel(label, { exact: true }).check();
  await page
    .getByRole("button", { name: "Generate with AI", exact: true })
    .click();
  await page
    .getByText("4 AI-generated draft items require your review.", {
      exact: true,
    })
    .waitFor();
  await page.getByRole("tab", { name: /^Questions \(\d+\)$/ }).click();
  assert.equal(
    await page.getByRole("button", { name: /Edit question \d/ }).count(),
    4,
  );
  await page.getByRole("tab", { name: "AI assistant", exact: true }).click();
  fs.mkdirSync(".tmp/resource-ai-screenshots", { recursive: true });
  for (const width of [320, 375, 768, 1440]) {
    await page.setViewportSize({ width, height: 900 });
    assert(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth + 1,
      ),
      `overflow at ${width}`,
    );
    await page.screenshot({
      path: `.tmp/resource-ai-screenshots/assistant-${width}.png`,
      fullPage: true,
    });
  }
  await page
    .getByRole("button", { name: "Generate alternative", exact: true })
    .first()
    .click();
  await page
    .getByText(
      "A separate AI alternative was added as a draft. Review it before removing the original.",
      { exact: true },
    )
    .waitFor();
  const draftVersion = await ok(
    teacher
      .from("quiz_versions")
      .select("id")
      .eq("quiz_id", draftQuiz.id)
      .single(),
  );
  const alternatives = await ok(
    teacher
      .from("quiz_items")
      .select("review_status")
      .eq("quiz_version_id", draftVersion.id),
  );
  assert.equal(alternatives.length, 5);
  assert(alternatives.every((item) => item.review_status === "draft"));
  pass(
    "browser upload refresh, source controls, disclosure, tab retention, all generated types and responsive AI assistant at 320/375/768/1440",
  );
}
try {
  await runTests();
} catch (error) {
  console.error(
    `FAIL ${error.name}: ${String(error.message).split("\n")[0].slice(0, 300)}`,
  );
  for (const line of String(error.stack)
    .split("\n")
    .filter((line) =>
      /^\s+at .*resource-ai-workflow-tests\.mjs:\d+:\d+/.test(line),
    ))
    console.error(line);
  const page = browser
    .contexts()
    .flatMap((context) => context.pages())
    .at(-1);
  if (page)
    await page
      .screenshot({
        path: ".tmp/resource-ai-browser-failure.png",
        fullPage: true,
      })
      .catch(() => {});
  process.exitCode = 1;
} finally {
  await browser.close();
}
