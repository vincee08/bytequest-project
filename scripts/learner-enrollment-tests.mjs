// Local QA only. Synthetic registration + authenticated API/browser regressions.
import assert from "node:assert/strict";
import fs from "node:fs";
import { randomBytes, randomUUID } from "node:crypto";
import { pathToFileURL } from "node:url";
import { createClient } from "@supabase/supabase-js";
import { createServerClient } from "@supabase/ssr";
import { textPdf } from "./fixtures/resource-pdf.mjs";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
if (url !== "http://127.0.0.1:58921" || process.env.BQ_ISOLATED_QA !== "BQQuizQA20261112") throw new Error("Dedicated isolated QA required; no writes made.");
const base = "http://localhost:3008";
const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
const options = { auth: { persistSession: false, autoRefreshToken: false } };
const service = createClient(url, process.env.SUPABASE_SERVICE_ROLE_KEY, options);
const existing = JSON.parse(fs.readFileSync(".tmp/quiz-preview-accounts.json", "utf8")).accounts;
const run = randomUUID().slice(0, 8);
let stage = "setup";
let browser;
const checks = [];
function pass(label) { checks.push(label); console.log(`PASS ${label}`); }
async function ok(promise) { const { data, error } = await promise; assert(!error, "QA operation failed."); return data; }
async function session(account) {
  const cookies = [];
  const client = createServerClient(url, key, { cookies: {
    getAll: () => cookies,
    setAll: values => { for (const value of values) { const index = cookies.findIndex(cookie => cookie.name === value.name); if (index < 0) cookies.push(value); else cookies[index] = value; } },
  } });
  await ok(client.auth.signInWithPassword({ email: account.email, password: account.password }));
  return { client, cookies, header: cookies.map(cookie => `${cookie.name}=${cookie.value}`).join("; ") };
}
async function api(actor, classId, q, page = 0) {
  const response = await fetch(`${base}/api/classes/${classId}/learners?${new URLSearchParams({ q, page: String(page) })}`, { headers: actor ? { Cookie: actor.header } : {}, signal: AbortSignal.timeout(20_000) });
  return { status: response.status, headers: response.headers, data: await response.json() };
}
async function enroll(actor, classId, learnerId) {
  const response = await fetch(`${base}/api/classes/${classId}/learners`, { method: "POST", headers: { Cookie: actor.header, "Content-Type": "application/json" }, body: JSON.stringify({ learnerId }), signal: AbortSignal.timeout(20_000) });
  return { status: response.status, data: await response.json() };
}
async function prepareOwnerResources(teacher, classId, first, second) {
  stage = "owner class resource visibility";
  // Flutter currently lists classes from assigned activities/shared resources.
  // A tiny synthetic welcome PDF makes the otherwise empty QA class visible
  // after enrollment without changing the mobile app or consuming an attempt.
  const form = new FormData();
  form.set("title", "Enrollment QA welcome");
  form.set("file", new File([textPdf()], "enrollment-qa-welcome.pdf", { type: "application/pdf" }));
  const response = await fetch(`${base}/api/classes/${classId}/resources`, { method: "POST", headers: { Cookie: teacher.header }, body: form, signal: AbortSignal.timeout(35_000) });
  assert(response.ok, "Synthetic owner welcome resource upload failed.");
  const resource = (await response.json()).resource;
  const enrolled = await ok(first.client.from("learning_resources").select("id,class_id,classes(title)").eq("id", resource.id).eq("status", "active"));
  const unassigned = await ok(second.client.from("learning_resources").select("id").eq("id", resource.id));
  assert.equal(enrolled.length, 1); assert.equal(unassigned.length, 0);
  assert.equal(typeof enrolled[0].classes.title, "string");
  pass("synthetic welcome resource makes the QA class visible through Flutter's existing enrolled-only resource query");
  return resource.id;
}
async function main() {
  stage = "local environment and registration";
  const teacher = await session(existing.instructor);
  const other = await session(existing.otherInstructor);
  const learnerSession = await session(existing.learner);
  if (process.argv.includes("--prepare-owner")) {
    const saved = JSON.parse(fs.readFileSync(".tmp/learner-enrollment-qa.json", "utf8"));
    const registered = [];
    for (const account of saved.learners) {
      const client = createClient(url, key, options);
      await ok(client.auth.signInWithPassword({ email: account.email, password: account.password }));
      registered.push({ ...account, client });
    }
    const welcomeResourceId = await prepareOwnerResources(teacher, saved.classId, registered[0], registered[1]);
    fs.writeFileSync(".tmp/learner-enrollment-qa.json", JSON.stringify({ ...saved, welcomeResourceId }, null, 2));
    return;
  }
  let registered = [], uiClass, fullName;
  if (process.argv.includes("--browser-only")) {
    const saved = JSON.parse(fs.readFileSync(".tmp/learner-enrollment-qa.json", "utf8"));
    uiClass = await ok(teacher.client.rpc("create_class", { p_title: `Owner Enrollment Search QA ${run}`, p_class_code: `ENR-UI-${run}` })); fullName = saved.fullName;
    for (const account of saved.learners) {
      const client = createClient(url, key, options);
      await ok(client.auth.signInWithPassword({ email: account.email, password: account.password }));
      registered.push({ ...account, client });
    }
  } else {
  const ownerClass = await ok(teacher.client.rpc("create_class", { p_title: `Enrollment API QA ${run}`, p_class_code: `ENR-A-${run}` }));
  const secondClass = await ok(teacher.client.rpc("create_class", { p_title: `Enrollment second QA ${run}`, p_class_code: `ENR-B-${run}` }));
  uiClass = await ok(teacher.client.rpc("create_class", { p_title: `Owner Enrollment Search QA ${run}`, p_class_code: `ENR-UI-${run}` }));
  const foreign = await ok(other.client.rpc("create_class", { p_title: `Enrollment private QA ${run}`, p_class_code: `ENR-X-${run}` }));
  fullName = `Enrollment QA ${run} Dela Cruz`;
  for (const suffix of ["one", "two"]) {
    const client = createClient(url, key, options);
    const account = { email: `enrollment.${run}.${suffix}@bytequest.invalid`, password: `${randomBytes(24).toString("base64url")}Aa1!` };
    // Exact auth metadata contract used by Flutter AuthService.signUp.
    const result = await ok(client.auth.signUp({ email: account.email, password: account.password, options: { data: { full_name: fullName, email: account.email } } }));
    assert(result.user && result.session, "Local QA signup must return an authenticated disposable learner.");
    const profile = await ok(client.from("profiles").select("user_id,full_name,email,role,status").eq("user_id", result.user.id).single());
    assert.equal(profile.role, "learner"); assert.equal(profile.status, "active");
    assert.equal(profile.full_name, fullName); assert.equal(profile.email, account.email);
    registered.push({ ...account, id: profile.user_id, client });
  }
  assert.equal((await ok(service.from("profiles").select("user_id").in("user_id", registered.map(row => row.id)))).length, 2);
  fs.writeFileSync(".tmp/learner-enrollment-qa.json", JSON.stringify({ classId: uiClass.id, classUrl: `${base}/classes/${uiClass.id}?tab=learners`, fullName, learners: registered.map(({ client, ...account }) => account) }, null, 2));
  pass("regular mobile-contract signup creates one trusted learner profile per Auth identity");

  stage = "name and email search";
  const [first, second] = registered;
  for (const term of [fullName, `QA ${run}`, fullName.toUpperCase(), first.email, first.email.toUpperCase()]) {
    const result = await api(teacher, ownerClass.id, term);
    assert.equal(result.status, 200); assert(result.data.learners.some(row => row.id === first.id));
    assert.match(result.headers.get("cache-control"), /no-store/);
    assert(result.data.learners.every(row => Object.keys(row).sort().join(",") === "email,enrollment,fullName,id"));
  }
  const duplicates = (await api(teacher, ownerClass.id, fullName)).data.learners;
  assert.equal(duplicates.length, 2); assert.notEqual(duplicates[0].id, duplicates[1].id);
  assert.notEqual(duplicates[0].email, duplicates[1].email);
  assert.equal((await api(teacher, ownerClass.id, `absent-${run}`)).data.learners.length, 0);
  assert.equal((await api(teacher, ownerClass.id, existing.instructor.email)).data.learners.length, 0);
  for (const term of ["%_", 'x),role.eq.instructor,user_id.not.is.null', '"quote"']) {
    const result = await api(teacher, ownerClass.id, term); assert.equal(result.status, 200); assert.equal(result.data.learners.length, 0);
  }
  const punctuation = `QA ${run} O'Neil, "Cruz" _100% \\ Jr`;
  await ok(first.client.from("profiles").update({ full_name: punctuation }).eq("user_id", first.id));
  assert.equal((await api(teacher, ownerClass.id, punctuation)).data.learners[0]?.id, first.id);
  await ok(first.client.from("profiles").update({ full_name: fullName }).eq("user_id", first.id));
  pass("full/partial/case-insensitive names and emails, duplicate names, literal punctuation, safe filters and minimal fields");

  stage = "pagination and directory population";
  const directory = await ok(service.from("profiles").select("user_id,full_name,email").eq("role", "learner").eq("status", "active").ilike("full_name", "%QA%").order("full_name").order("user_id"));
  const a = await api(teacher, ownerClass.id, "QA"); const b = await api(teacher, ownerClass.id, "QA", 1);
  assert.equal(a.data.learners.length, 15); assert(a.data.hasMore); assert(b.data.learners.length > 0);
  assert.deepEqual(a.data.learners.map(row => row.id), directory.slice(0, 15).map(row => row.user_id));
  assert.deepEqual(b.data.learners.map(row => row.id), directory.slice(15, 30).map(row => row.user_id));
  assert.equal((await api(teacher, ownerClass.id, "x")).status, 400);
  assert.equal((await api(teacher, ownerClass.id, "QA", -1)).status, 400);
  assert.equal((await api(teacher, ownerClass.id, "**")).status, 400);
  pass("bounded deterministic pages match the active learner profiles backing the registered directory");

  stage = "authorization";
  assert.equal((await api(null, ownerClass.id, fullName)).status, 401);
  assert.equal((await api(other, ownerClass.id, fullName)).status, 403);
  assert.equal((await api(teacher, foreign.id, fullName)).status, 403);
  assert.equal((await api(learnerSession, ownerClass.id, fullName)).status, 403);
  assert.equal((await enroll(other, ownerClass.id, first.id)).status, 403);
  assert.equal((await enroll(learnerSession, ownerClass.id, first.id)).status, 403);
  assert.equal((await enroll(teacher, ownerClass.id, existing.instructor.id)).status, 422);
  assert.equal((await enroll(teacher, ownerClass.id, first.email)).status, 400);
  const hidden = await ok(teacher.client.from("profiles").select("user_id").eq("user_id", first.id));
  assert.equal(hidden.length, 0, "General instructor RLS must remain scoped; the approved directory proxy is the narrow exception.");
  pass("authentication, instructor role, owned-class scope, stable UUID validation and existing profile RLS remain enforced");

  stage = "enrollment and retained history";
  const initial = await enroll(teacher, ownerClass.id, first.id); assert.equal(initial.status, 201);
  assert.equal((await api(teacher, ownerClass.id, first.email)).data.learners[0].enrollment, "active");
  assert.equal((await enroll(teacher, ownerClass.id, first.id)).status, 409);
  assert.equal((await enroll(teacher, secondClass.id, first.id)).status, 201);
  await ok(teacher.client.rpc("deactivate_class_membership", { p_membership_id: initial.data.membershipId, p_reason: "Synthetic enrollment history regression" }));
  const old = await ok(service.from("class_memberships").select("*").eq("id", initial.data.membershipId).single());
  assert.equal((await api(teacher, ownerClass.id, first.email)).data.learners[0].enrollment, "previously_enrolled");
  const again = await enroll(teacher, ownerClass.id, first.id); assert.equal(again.status, 201);
  assert.notEqual(again.data.membershipId, old.id);
  assert.deepEqual(await ok(service.from("class_memberships").select("*").eq("id", old.id).single()), old);
  const parallel = await Promise.all(Array.from({ length: 10 }, () => enroll(teacher, ownerClass.id, second.id)));
  assert.equal(parallel.filter(row => row.status === 201).length, 1);
  assert(parallel.every(row => [201, 409].includes(row.status)));
  assert.equal((await ok(service.from("class_memberships").select("id").eq("class_id", ownerClass.id).eq("learner_id", second.id).eq("status", "active"))).length, 1);
  pass("stable-ID persistence, duplicate/concurrent protection, multi-class enrollment and immutable previous membership rows");

  stage = "stale account and archived class";
  await ok(service.from("profiles").update({ status: "deactivated", deactivated_at: new Date().toISOString(), deactivated_by: existing.instructor.id, deactivation_reason: "Synthetic eligibility regression" }).eq("user_id", second.id));
  assert.equal((await api(teacher, ownerClass.id, second.email)).data.learners.length, 0);
  assert.equal((await enroll(teacher, secondClass.id, second.id)).status, 422);
  await ok(service.from("profiles").update({ status: "active", deactivated_at: null, deactivated_by: null, deactivation_reason: null }).eq("user_id", second.id));
  await ok(teacher.client.rpc("archive_class", { p_class_id: secondClass.id, p_reason: "Synthetic archived-class regression" }));
  assert.equal((await api(teacher, secondClass.id, first.email)).status, 403);
  assert.equal((await enroll(teacher, secondClass.id, second.id)).status, 403);
  pass("ineligible/stale learner selections and archived classes are rejected server-side");
  }

  stage = "browser setup";
  const [first, second] = registered;
  const { chromium } = await import(pathToFileURL(process.env.BQ_PLAYWRIGHT_MODULE).href);
  browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport: { width: 1440, height: 1000 }, reducedMotion: "reduce" });
  await context.addCookies(teacher.cookies.map(cookie => ({ name: cookie.name, value: cookie.value, url: base, sameSite: "Lax" })));
  const page = await context.newPage();
  await page.goto(`${base}/classes/${uiClass.id}?tab=learners`);
  const form = page.getByRole("form", { name: "Enroll a learner" });
  const input = form.getByRole("combobox", { name: "Search learner by name or email" });
  stage = "debounce and keyboard";
  let searches = 0, posts = 0, postedId;
  page.on("request", request => { if (request.url().includes(`/api/classes/${uiClass.id}/learners`)) { if (request.method() === "GET") searches++; if (request.method() === "POST") { posts++; postedId = request.postDataJSON().learnerId; } } });
  await input.fill(`absent-${run}`); await page.getByText("No registered learners match. Try a different name or email.").waitFor();
  searches = 0;
  await input.fill("En"); await input.pressSequentially(fullName.slice(2), { delay: 15 });
  await page.getByRole("option").filter({ hasText: first.email }).waitFor();
  assert.equal(searches, 1, "Typing must produce one debounced request.");
  await input.press("Space");
  await page.getByRole("option").filter({ hasText: first.email }).waitFor();
  await input.press("ArrowDown"); assert(await input.getAttribute("aria-activedescendant"));
  await input.press("Escape"); assert.equal(await input.getAttribute("aria-expanded"), "false");
  await input.press("ArrowDown"); await input.press("Enter");
  assert.equal(await input.getAttribute("aria-expanded"), "false");
  assert.equal(await form.getByRole("button", { name: "Enroll learner", exact: true }).isEnabled(), true);
  await form.getByRole("button", { name: "Clear learner selection and search" }).click();
  await input.fill(first.email.toUpperCase());
  await page.getByRole("option").filter({ hasText: first.email }).click();
  assert(await form.getByText(first.email, { exact: true }).isVisible());
  pass("browser empty state, debounce, Arrow/Enter/Escape navigation, clear action and explicit email selection");

  stage = "browser pagination";
  await form.getByRole("button", { name: "Clear learner selection and search" }).click();
  await input.fill("QA");
  await page.getByRole("button", { name: "Next learner results" }).click();
  await page.getByRole("status").filter({ hasText: "matches on page 2" }).waitFor();
  assert(await input.evaluate(node => document.activeElement === node));
  await page.getByRole("button", { name: "Previous learner results" }).click();
  await page.getByRole("status").filter({ hasText: "matches on page 1" }).waitFor();
  await input.fill(first.email);
  await page.getByRole("option").filter({ hasText: first.email }).click();
  pass("dropdown pagination loads bounded results and returns keyboard focus to search");

  stage = "browser enrollment refresh";
  await page.route(`**/api/classes/${uiClass.id}/learners`, async route => {
    if (route.request().method() === "POST") await new Promise(resolve => setTimeout(resolve, 350));
    await route.continue();
  });
  await form.evaluate(node => { node.requestSubmit(); node.requestSubmit(); });
  assert.equal(await form.getByRole("button", { name: "Enrolling…", exact: true }).isDisabled(), true);
  await page.getByText(`${fullName} is enrolled. The class membership list has been refreshed.`, { exact: true }).waitFor();
  await page.getByRole("heading", { name: "Membership history" }).locator("..").locator("..").getByText(first.email, { exact: false }).waitFor();
  const metric = page.getByRole("region", { name: "Class detail metrics" }).locator("a").filter({ hasText: "Active learners" });
  await metric.locator("p.tabular-nums").filter({ hasText: /^1$/ }).waitFor();
  assert.equal(posts, 1); assert.equal(postedId, first.id);
  assert.equal(await form.getByRole("button", { name: "Already enrolled", exact: true }).isDisabled(), true);
  assert(await metric.isVisible());
  pass("one pending enrollment request, stable selected ID, success, membership refresh and active-count update");

  stage = "responsive and accessible states";
  for (const width of [320, 375, 768, 1440]) {
    await page.setViewportSize({ width, height: 1000 });
    await form.getByRole("button", { name: "Clear learner selection and search" }).click();
    await input.fill(fullName); await page.getByRole("option").filter({ hasText: second.email }).waitFor();
    const box = await input.boundingBox(); assert(box && box.width > 100 && box.height >= 44);
    assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1));
    await input.press("Escape");
  }
  pass("responsive 320/375/768/1440 layouts, labelled combobox, 44px controls and no page overflow");

  stage = "stale search cancellation";
  await page.route(`**/api/classes/${uiClass.id}/learners?**`, async route => {
    if (new URL(route.request().url()).searchParams.get("q") === first.email) {
      try { const response = await route.fetch(); await new Promise(resolve => setTimeout(resolve, 700)); await route.fulfill({ response }); } catch { /* expected cancellation */ }
    } else await route.continue();
  });
  const oldSearch = page.waitForRequest(request => request.method() === "GET" && request.url().includes(encodeURIComponent(first.email)));
  await input.fill(first.email); await oldSearch;
  await page.getByText("Searching registered learners…", { exact: true }).waitFor();
  await input.fill(second.email); await page.getByRole("option").filter({ hasText: second.email }).waitFor();
  await page.waitForTimeout(800);
  assert.equal(await page.getByRole("option").filter({ hasText: first.email }).count(), 0);
  await page.unroute(`**/api/classes/${uiClass.id}/learners?**`);
  pass("loading feedback and aborted stale searches cannot overwrite the current results");

  stage = "browser failure and retry";
  await page.unroute(`**/api/classes/${uiClass.id}/learners`);
  await page.route(`**/api/classes/${uiClass.id}/learners?**`, route => route.fulfill({ status: 503, contentType: "application/json", body: JSON.stringify({ error: "Synthetic search outage. Try again." }) }));
  await input.fill(`outage-${run}`); await form.getByRole("alert").filter({ hasText: "Synthetic search outage" }).waitFor();
  await page.unroute(`**/api/classes/${uiClass.id}/learners?**`);
  await input.fill(second.email); await page.getByRole("option").filter({ hasText: second.email }).waitFor();
  pass("search failure feedback and recovery preserve the usable form");

  stage = "learner class visibility and handoff";
  assert((await ok(first.client.from("class_memberships").select("class_id,status").eq("class_id", uiClass.id))).some(row => row.status === "active"));
  assert.equal((await ok(second.client.from("class_memberships").select("class_id").eq("class_id", uiClass.id))).length, 0);
  const welcomeResourceId = await prepareOwnerResources(teacher, uiClass.id, first, second);
  fs.writeFileSync(".tmp/learner-enrollment-qa.json", JSON.stringify({ classId: uiClass.id, classUrl: `${base}/classes/${uiClass.id}?tab=learners`, fullName, welcomeResourceId, instructorAccountFile: ".tmp/quiz-preview-accounts.json", learners: registered.map(({ client, ...account }) => account), checks }, null, 2));
  pass("enrolled learner can read their class membership; unenrolled peer cannot; private owner fixture saved");
}
try { await main(); console.log(`PASS enrollment integration: ${checks.length} groups. No hosted writes, quiz changes or provider calls.`); }
catch (error) {
  // Never print Playwright's request diagnostics, cookies, account data or URLs
  // with credentials. The stage identifies the failure without a raw payload.
  console.error(`FAIL enrollment integration at '${stage}' (${error?.name ?? "Error"}).`);
  process.exitCode = 1;
} finally { await browser?.close(); }
