/**
 * End-to-end panel workflows on the LOCAL Supabase stack (never production).
 *
 * Proves, with real signed-in instructor and learner sessions:
 *  1. one active class per learner (enroll_learner, roster preview/import, sign-up claim,
 *     move after deactivation, history retained, learner directory scope);
 *  2. "written answer + 1 image" homework; 3. file-only homework; 4. answer-only homework;
 *  5. legacy "written answer or file" homework, including grading and release.
 *
 * Homework, uploads and submissions go through the same route handlers the mobile app and the
 * dashboard call (bearer sessions); enrollment and roster use the same RPCs as their routes.
 *
 * Prerequisites: local stack running (db, auth, rest, kong, storage), the fixture accounts from
 * `node scripts/local-qa-fixtures.mjs` in .tmp/local-qa-accounts.json, and .env.local pointing at
 * the local stack. Run from ByteQuest-Web-Dashboard:  pnpm test:panel-local
 *
 * Each run creates clearly labelled records ("E2E panel <run>"): two classes, synthetic learners
 * (e2e.panel.<run>.*@bytequest.test) and their homework. History is append-only, so cleanup
 * archives the classes instead of deleting rows; archived classes no longer count toward the
 * one-class rule and disappear from learner views.
 */
import assert from "node:assert/strict";
import { createHash, randomBytes } from "node:crypto";
import { readFileSync } from "node:fs";
import { after, before, test } from "node:test";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import * as XLSX from "xlsx";
import { enrollmentFailure, ONE_ACTIVE_CLASS_MESSAGE } from "../../src/lib/learners/enrollment";
import { rosterGroups, rosterStatusLabels, type RosterOutcome } from "../../src/lib/roster/types";

// `server-only` is a bundler guard; stub it so the real server modules load under Node.
const serverOnly = require.resolve("server-only");
require.cache[serverOnly] = { id: serverOnly, filename: serverOnly, loaded: true, exports: {} } as unknown as NodeJS.Module;
type Handler = (request: Request) => Promise<Response>;
let homeworkGet: Handler;
let homeworkPost: Handler;
let uploadPost: Handler;
let parseRosterFile: typeof import("../../src/lib/roster/parse").parseRosterFile;

const url = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "";
const publishable = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "";
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY ?? "";
if (!["127.0.0.1", "localhost"].includes(new URL(url || "http://invalid").hostname)) {
  throw new Error("This workflow test only runs against a local Supabase stack.");
}

const run = `${Date.now().toString(36)}${randomBytes(2).toString("hex")}`;
const label = `E2E panel ${run}`;
const service = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
const fixtures = JSON.parse(readFileSync("../.tmp/local-qa-accounts.json", "utf8")).accounts as Record<string, { email: string; password: string; id: string }>;

type Session = { id: string; token: string; client: SupabaseClient };
async function signIn(email: string, password: string): Promise<Session> {
  const client = createClient(url, publishable, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data, error } = await client.auth.signInWithPassword({ email, password });
  assert.ifError(error);
  return { id: data.user!.id, token: data.session!.access_token, client };
}

async function createLearner(key: string, fullName: string) {
  const email = `e2e.panel.${run}.${key}@bytequest.test`;
  const password = randomBytes(18).toString("base64url");
  const { data, error } = await service.auth.admin.createUser({ email, password, email_confirm: true, user_metadata: { full_name: fullName } });
  assert.ifError(error);
  const { data: profile } = await service.from("profiles").select("role,status").eq("user_id", data.user!.id).single();
  assert.deepEqual(profile, { role: "learner", status: "active" });
  return { email, ...(await signIn(email, password)) };
}

async function route(handler: Handler, path: string, token: string, body?: unknown) {
  const response = await handler(new Request(`http://localhost${path}`, {
    method: body === undefined ? "GET" : "POST",
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json", "x-bytequest-app-version": "1.2.0" },
    body: body === undefined ? undefined : JSON.stringify(body),
  }));
  return { status: response.status, body: await response.json() as Record<string, unknown> };
}

const PNG = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==", "base64");
const PDF = Buffer.from("%PDF-1.4\n1 0 obj <<>> endobj\ntrailer <<>>\n%%EOF\n");

/** The mobile app's upload sequence: prepare, PUT to the signed Storage URL, complete. */
async function upload(token: string, assignmentId: string, filename: string, mime: string, bytes: Buffer) {
  const sha256 = createHash("sha256").update(bytes).digest("hex");
  const prepared = await route(uploadPost, "/api/uploads", token, { action: "prepare", purpose: "homework", target_id: assignmentId, filename, mime, size: bytes.length, sha256 });
  if (prepared.status !== 200) return prepared;
  if (typeof prepared.body.signed_url === "string") {
    const put = await fetch(prepared.body.signed_url, { method: "PUT", headers: { "Content-Type": mime, "x-upsert": "false" }, body: bytes });
    assert.ok(put.ok, `Storage refused the upload (${put.status})`);
  }
  return route(uploadPost, "/api/uploads", token, { action: "complete", upload_id: prepared.body.upload_id });
}

function rosterRows(rows: { student_id: string; last_name: string; first_name: string; email: string }[]) {
  const sheet = XLSX.utils.aoa_to_sheet([
    ["student_id", "last_name", "first_name", "email", "course_section"],
    ...rows.map((row) => [row.student_id, row.last_name, row.first_name, row.email, "E2E"]),
  ]);
  const book = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(book, sheet, "Roster");
  const bytes = new Uint8Array(XLSX.write(book, { type: "array", bookType: "xlsx" }) as ArrayBuffer);
  const parsed = parseRosterFile({ name: `roster-${run}.xlsx`, size: bytes.length, bytes });
  assert.ok(parsed.ok, "the roster file must parse like an uploaded file");
  return parsed.rows;
}
const statusOf = (outcome: RosterOutcome, email: string) =>
  outcome.rows.find((row) => row.email?.toLowerCase() === email.toLowerCase())?.status;

let instructor: Session;
let admin: Session;
let classA = "";
let classB = "";
let one: Awaited<ReturnType<typeof createLearner>>;
let two: Awaited<ReturnType<typeof createLearner>>;
let three: Awaited<ReturnType<typeof createLearner>>;
const pendingEmail = `e2e.panel.${run}.pending@bytequest.test`;

before(async () => {
  ({ GET: homeworkGet, POST: homeworkPost } = await import("../../src/app/api/activities/homework/route"));
  ({ POST: uploadPost } = await import("../../src/app/api/uploads/route"));
  ({ parseRosterFile } = await import("../../src/lib/roster/parse"));
  instructor = await signIn(fixtures.instructor.email, fixtures.instructor.password);
  admin = await signIn(fixtures.admin.email, fixtures.admin.password);
  for (const suffix of ["A", "B"]) {
    const { data, error } = await instructor.client.rpc("create_class", { p_title: `${label} class ${suffix}`, p_class_code: null });
    assert.ifError(error);
    if (suffix === "A") classA = (data as { id: string }).id; else classB = (data as { id: string }).id;
  }
  one = await createLearner("one", `E2E Panel Learner One ${run}`);
  two = await createLearner("two", `E2E Panel Learner Two ${run}`);
});

after(async () => {
  for (const id of [classA, classB].filter(Boolean)) {
    await instructor.client.rpc("archive_class", { p_class_id: id, p_reason: `${label} cleanup` });
  }
});

const activeClasses = async (learnerId: string) =>
  ((await service.from("class_memberships").select("class_id,status").eq("learner_id", learnerId)).data ?? [])
    .filter((row) => row.status === "active").map((row) => row.class_id).sort();

test("1. a learner can be enrolled in only one active class", async () => {
  const first = await instructor.client.rpc("enroll_learner", { p_class_id: classA, p_learner_id: one.id });
  assert.ifError(first.error);

  const second = await instructor.client.rpc("enroll_learner", { p_class_id: classB, p_learner_id: one.id });
  assert.equal(second.error?.code, "23505");
  assert.match(second.error?.message ?? "", /LEARNER_ALREADY_IN_ANOTHER_CLASS/);
  assert.doesNotMatch(JSON.stringify(second.error), new RegExp(`${label} class A`), "the refusal never names the other class");
  assert.deepEqual(enrollmentFailure(second.error?.code, second.error?.message),
    { status: 409, code: "ENROLLED_IN_ANOTHER_CLASS", message: ONE_ACTIVE_CLASS_MESSAGE });

  const again = await instructor.client.rpc("enroll_learner", { p_class_id: classA, p_learner_id: one.id });
  assert.equal(enrollmentFailure(again.error?.code, again.error?.message).code, "ALREADY_ENROLLED");
  assert.deepEqual(await activeClasses(one.id), [classA]);
});

test("1. roster import skips learners in another class and pre-registers new emails", async () => {
  const rows = rosterRows([
    { student_id: `${run}-1`, last_name: "One", first_name: "Learner", email: one.email },
    { student_id: `${run}-2`, last_name: "Two", first_name: "Learner", email: two.email },
    { student_id: `${run}-3`, last_name: "Pending", first_name: "Learner", email: pendingEmail },
  ]);
  const preview = await service.rpc("preview_class_roster", { p_actor: instructor.id, p_class_id: classB, p_rows: rows });
  assert.ifError(preview.error);
  const previewed = preview.data as RosterOutcome;
  assert.equal(statusOf(previewed, one.email), "enrolled_elsewhere");
  assert.equal(rosterStatusLabels.enrolled_elsewhere, "In another class");
  assert.ok(rosterGroups.find((group) => group.key === "skip")?.statuses.includes("enrolled_elsewhere"), "shown in the Skip group");
  assert.equal(statusOf(previewed, two.email), "enroll_now");
  assert.equal(statusOf(previewed, pendingEmail), "pending");
  assert.deepEqual(await activeClasses(two.id), [], "preview changes nothing");

  const applied = await service.rpc("import_class_roster", { p_actor: instructor.id, p_class_id: classB, p_rows: rows, p_file_name: `roster-${run}.xlsx` });
  assert.ifError(applied.error);
  const imported = applied.data as RosterOutcome;
  assert.equal(statusOf(imported, one.email), "enrolled_elsewhere");
  assert.deepEqual(await activeClasses(one.id), [classA], "the learner in another class is skipped");
  assert.deepEqual(await activeClasses(two.id), [classB]);

  // The pre-registered email is now waiting for class B, so class A cannot also claim it.
  const elsewhere = await service.rpc("preview_class_roster", {
    p_actor: instructor.id, p_class_id: classA,
    p_rows: rosterRows([{ student_id: `${run}-3`, last_name: "Pending", first_name: "Learner", email: pendingEmail }]),
  });
  assert.ifError(elsewhere.error);
  assert.equal(statusOf(elsewhere.data as RosterOutcome, pendingEmail), "pending_elsewhere");
  assert.equal(rosterStatusLabels.pending_elsewhere, "Waiting for another class");
});

test("1. signing up with a pre-registered email joins exactly its class", async () => {
  const password = randomBytes(18).toString("base64url");
  const { data, error } = await service.auth.admin.createUser({ email: pendingEmail, password, email_confirm: true, user_metadata: { full_name: `E2E Panel Learner Three ${run}` } });
  assert.ifError(error);
  three = { email: pendingEmail, ...(await signIn(pendingEmail, password)) };
  assert.equal(three.id, data.user!.id);
  assert.deepEqual(await activeClasses(three.id), [classB]);
  const { data: entry } = await service.from("class_roster_entries").select("status,claimed_user_id").eq("class_id", classB).eq("email_normalized", pendingEmail).single();
  assert.deepEqual(entry, { status: "enrolled", claimed_user_id: three.id });
});

test("1. a learner moves only after leaving the first class, and history is kept", async () => {
  const { data: membership } = await service.from("class_memberships").select("id").eq("class_id", classA).eq("learner_id", one.id).eq("status", "active").single();
  const left = await instructor.client.rpc("deactivate_class_membership", { p_membership_id: membership!.id, p_reason: `${label}: moved to class B` });
  assert.ifError(left.error);
  const moved = await instructor.client.rpc("enroll_learner", { p_class_id: classB, p_learner_id: one.id });
  assert.ifError(moved.error);
  assert.deepEqual(await activeClasses(one.id), [classB]);
  const { data: history } = await service.from("class_memberships").select("class_id,status").eq("learner_id", one.id).eq("class_id", classA);
  assert.deepEqual(history, [{ class_id: classA, status: "deactivated" }], "the previous enrollment is retained");

  // Admin and instructor learner directories list only the current class.
  for (const session of [admin, instructor]) {
    const { data, error } = await session.client.rpc("search_learners", { p_query: one.email, p_class_id: null, p_status: "active", p_sort: "name.asc", p_limit: 5, p_offset: 0 });
    assert.ifError(error);
    const row = (data as { rows: { user_id: string; classes: { id: string }[] }[] }).rows.find((item) => item.user_id === one.id);
    assert.deepEqual(row?.classes.map((item) => item.id), [classB]);
  }
});

const future = new Date(Date.now() + 7 * 86_400_000).toISOString();
async function publishHomework(title: string, rule: Record<string, unknown>) {
  const created = await route(homeworkPost, "/api/activities/homework", instructor.token, {
    action: "create", class_id: classB, title: `${label} ${title}`, instructions: `${title}: follow the submission rule.`, deadline_at: future, ...rule,
  });
  assert.equal(created.status, 200, JSON.stringify(created.body));
  const id = (created.body.record as { id: string }).id;
  const published = await route(homeworkPost, "/api/activities/homework", instructor.token, { action: "publish", assignment_id: id });
  assert.equal(published.status, 200, JSON.stringify(published.body));
  return id;
}
const submit = (token: string, assignmentId: string, answer: string, fileIds: string[] = []) =>
  route(homeworkPost, "/api/activities/homework", token, { action: "submit", assignment_id: assignmentId, answer, file_ids: fileIds });
const fileId = (response: { body: Record<string, unknown> }) => (response.body.record as { id: string }).id;

test("2. written answer + 1 image: refused until both are present, then graded and released", async () => {
  const id = await publishHomework("answer and image", { submission_format: "answer_and_file", required_file_count: 1, accepted_file_types: "image" });

  const listed = await route(homeworkGet, `/api/activities/homework?id=${id}`, one.token);
  assert.equal(listed.status, 200);
  const rule = (listed.body.homework as Record<string, unknown>[])[0];
  assert.deepEqual([rule.submission_format, rule.required_file_count, rule.accepted_file_types], ["answer_and_file", 1, "image"], "the app receives the rule");

  const textOnly = await submit(one.token, id, "My written explanation of the ESD steps.");
  assert.equal(textOnly.status, 422);
  assert.equal(textOnly.body.error, "Attach at least 1 image (JPG, PNG or WEBP) before submitting.");

  const pdf = await upload(one.token, id, "evidence.pdf", "application/pdf", PDF);
  assert.equal(pdf.status, 422, JSON.stringify(pdf.body));
  assert.equal(pdf.body.error, "This homework accepts images only (JPG, PNG or WEBP).");
  const { data: kept } = await service.from("homework_files").select("filename").eq("assignment_id", id).eq("owner_id", one.id);
  assert.deepEqual(kept, [], "a refused file is never attached");

  const png = await upload(one.token, id, "evidence.png", "image/png", PNG);
  assert.equal(png.status, 201, JSON.stringify(png.body));
  const imageOnly = await submit(one.token, id, "", [fileId(png)]);
  assert.equal(imageOnly.status, 422);
  assert.equal(imageOnly.body.error, "This homework requires a written answer.");

  const accepted = await submit(one.token, id, "My written explanation of the ESD steps.", [fileId(png)]);
  assert.equal(accepted.status, 200, JSON.stringify(accepted.body));
  const submissionId = (accepted.body.record as { id: string }).id;

  const graded = await route(homeworkPost, "/api/activities/homework", instructor.token, { action: "grade", submission_id: submissionId, feedback: "Clear steps and photo.", score: 90 });
  assert.equal(graded.status, 200, JSON.stringify(graded.body));
  const draft = (await route(homeworkGet, `/api/activities/homework?id=${id}`, one.token)).body.submissions as Record<string, unknown>[];
  assert.deepEqual([draft[0].status, draft[0].score], ["submitted", null], "an unreleased grade stays hidden from the learner");
  for (const action of ["finalize", "release"]) {
    const step = await route(homeworkPost, "/api/activities/homework", instructor.token, { action, submission_ids: [submissionId] });
    assert.equal(step.status, 200, JSON.stringify(step.body));
    const [result] = (step.body.record as { results: { submission_id: string; ok: boolean }[] }).results;
    assert.equal(result?.ok, true, `${action}: ${JSON.stringify(step.body)}`);
  }
  const seen = await route(homeworkGet, `/api/activities/homework?id=${id}`, one.token);
  const mine = (seen.body.submissions as Record<string, unknown>[])[0];
  // The learner API reports a released result as "graded" (its evaluation_status is "released").
  assert.deepEqual([mine.status, mine.evaluation_status, Number(mine.score)], ["graded", "released", 90]);
});

test("3. file-only homework: a file is enough and a written answer is not accepted", async () => {
  const id = await publishHomework("file only", { submission_format: "file", required_file_count: 1, accepted_file_types: "any" });
  const textOnly = await submit(two.token, id, "Here is my report.");
  assert.equal(textOnly.status, 422);
  const report = await upload(two.token, id, "report.pdf", "application/pdf", PDF);
  assert.equal(report.status, 201, JSON.stringify(report.body));
  const withAnswer = await submit(two.token, id, "Here is my report.", [fileId(report)]);
  assert.equal(withAnswer.status, 422);
  assert.equal(withAnswer.body.error, "This homework accepts files only. Remove the written answer, then submit your file.");
  const accepted = await submit(two.token, id, "", [fileId(report)]);
  assert.equal(accepted.status, 200, JSON.stringify(accepted.body));
});

test("4. answer-only homework refuses files and accepts a written answer", async () => {
  const id = await publishHomework("answer only", { submission_format: "answer", required_file_count: 0, accepted_file_types: "any" });
  const file = await upload(three.token, id, "notes.png", "image/png", PNG);
  assert.equal(file.status, 422, JSON.stringify(file.body));
  assert.equal(file.body.error, "This homework accepts a written answer only. Remove the attached files.");
  const accepted = await submit(three.token, id, "Written answer only.");
  assert.equal(accepted.status, 200, JSON.stringify(accepted.body));
});

test("5. legacy homework still takes a written answer or a file", async () => {
  const id = await publishHomework("legacy", {});
  const listed = await route(homeworkGet, `/api/activities/homework?id=${id}`, one.token);
  assert.equal((listed.body.homework as Record<string, unknown>[])[0].submission_format, "answer_or_file");
  const empty = await submit(two.token, id, "");
  assert.equal(empty.status, 422);
  assert.equal(empty.body.error, "Write an answer or attach a file before submitting.");
  const text = await submit(three.token, id, "Legacy written answer.");
  assert.equal(text.status, 200, JSON.stringify(text.body));
  const file = await upload(one.token, id, "legacy.pdf", "application/pdf", PDF);
  assert.equal(file.status, 201, JSON.stringify(file.body));
  const fileOnly = await submit(one.token, id, "", [fileId(file)]);
  assert.equal(fileOnly.status, 200, JSON.stringify(fileOnly.body));
});
