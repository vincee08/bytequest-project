import { randomUUID } from "node:crypto";
import { createBrowserClient } from "@supabase/ssr";
import { createClient } from "@supabase/supabase-js";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const publicKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const password = process.env.BYTEQUEST_E2E_PASSWORD;
if (!url || !publicKey || !serviceKey || !password ||
    !["127.0.0.1", "localhost"].includes(new URL(url).hostname)) {
  throw new Error("An isolated local Supabase stack and transient E2E credentials are required.");
}

const service = createClient(url, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } });
const dashboardUrl = process.env.BYTEQUEST_DASHBOARD_URL;
const runId = `bq-concerns-${Date.now()}-${randomUUID().slice(0, 8)}`;
const users = new Map();
const emails = new Map();
const clients = new Map();
const results = [];
let classId;

function assert(condition, message) {
  if (!condition) throw new Error(message);
}
function record(name) {
  results.push({ name, status: "PASS" });
}
async function denied(name, request) {
  const response = await request();
  assert(response.error || (Array.isArray(response.data) && response.data.length === 0), `${name}: unexpectedly allowed`);
  record(name);
}

async function createUsers() {
  for (const [name, role] of [["admin", "admin"], ["instructor", "instructor"],
    ["instructor2", "instructor"], ["learner", "learner"]]) {
    const email = `${runId}-${name}@bytequest-e2e.invalid`;
    const created = await service.auth.admin.createUser({
      email, password, email_confirm: true,
      user_metadata: { full_name: `Concerns E2E ${name}`, bytequest_test_account: true, bytequest_test_run: runId },
    });
    if (created.error || !created.data.user) throw created.error ?? new Error(`${name} creation failed`);
    users.set(name, created.data.user.id);
    emails.set(name, email);
    const profile = await service.from("profiles").update({ role, status: "active" }).eq("user_id", created.data.user.id);
    if (profile.error) throw profile.error;
    const client = createClient(url, publicKey, { auth: { autoRefreshToken: false, persistSession: false } });
    const signedIn = await client.auth.signInWithPassword({ email, password });
    if (signedIn.error || signedIn.data.user?.id !== created.data.user.id) throw signedIn.error ?? new Error("Auth/profile mismatch");
    clients.set(name, client);
  }
  record("four disposable Auth sessions match backend roles");
}

async function createDashboardCookie(role) {
  const cookies = new Map();
  const browser = createBrowserClient(url, publicKey, {
    isSingleton: false,
    cookies: {
      getAll: () => [...cookies].map(([name, value]) => ({ name, value })),
      setAll: (updates) => updates.forEach(({ name, value }) => {
        if (value) cookies.set(name, value);
        else cookies.delete(name);
      }),
    },
  });
  const signedIn = await browser.auth.signInWithPassword({ email: emails.get(role), password });
  if (signedIn.error) throw signedIn.error;
  return [...cookies].map(([name, value]) => `${name}=${value}`).join("; ");
}

async function verifyDashboardBoundary() {
  if (!dashboardUrl) return;
  const base = dashboardUrl.replace(/\/$/, "");
  const instructorCookie = await createDashboardCookie("instructor");
  const adminCookie = await createDashboardCookie("admin");
  const request = (path, cookie) => fetch(`${base}${path}`, {
    headers: { cookie }, redirect: "manual",
  });
  const instructorPage = await request("/concerns", instructorCookie);
  const instructorHtml = await instructorPage.text();
  assert(instructorPage.status === 200 && instructorHtml.includes("Training concerns"),
    "Authenticated Instructor concern page did not render");
  const instructorBlocked = await request("/admin/concerns", instructorCookie);
  assert(instructorBlocked.status === 307 && instructorBlocked.headers.get("location")?.endsWith("/instructor/dashboard"),
    "Instructor was not redirected from the Admin concern page");
  const adminPage = await request("/admin/concerns", adminCookie);
  const adminHtml = await adminPage.text();
  assert(adminPage.status === 200 && adminHtml.includes("System incidents"),
    "Authenticated Admin incident page did not render");
  const adminBlocked = await request("/concerns", adminCookie);
  assert(adminBlocked.status === 307 && adminBlocked.headers.get("location")?.endsWith("/admin/dashboard"),
    "Admin was not redirected from the Instructor concern page");
  record("authenticated dashboard pages render only within the matching staff role");
}

async function verify() {
  const instructor = clients.get("instructor");
  const instructor2 = clients.get("instructor2");
  const admin = clients.get("admin");
  const learner = clients.get("learner");
  const classroom = await instructor.rpc("create_class", {
    p_title: `Concerns E2E ${runId}`, p_class_code: `CN-${randomUUID().slice(0, 8)}`,
  });
  if (classroom.error) throw classroom.error;
  classId = classroom.data.id;

  const training = await instructor.from("support_concerns").insert({
    scope: "training", class_id: classId, title: "Equipment inspection needed",
    details: "The learner workstation needs Instructor inspection before the next activity.",
  }).select("*").single();
  if (training.error) throw training.error;
  assert(training.data.opened_by === users.get("instructor") &&
    training.data.history.length === 1 &&
    training.data.history[0].actor_id === users.get("instructor"), "Training concern actor/history mismatch");
  record("Instructor opens an owned-class training concern with server-recorded history");

  await denied("Instructor cannot open a system incident", () => instructor.from("support_concerns").insert({
    scope: "system", title: "Forbidden platform incident",
    details: "Instructor must not perform Administrator-only incident intake.",
  }));
  await denied("Learner cannot open a training concern", () => learner.from("support_concerns").insert({
    scope: "training", class_id: classId, title: "Forbidden learner concern",
    details: "Learner must not author an Instructor-owned training concern.",
  }));
  await denied("Other Instructor cannot read owned training concern", () => instructor2.from("support_concerns")
    .select("id").eq("id", training.data.id));

  const system = await admin.from("support_concerns").insert({
    scope: "system", title: "Platform configuration incident",
    details: "Administrator will review a test-only account configuration issue.",
  }).select("*").single();
  if (system.error) throw system.error;
  assert(system.data.opened_by === users.get("admin"), "System incident actor mismatch");
  record("Administrator opens a system incident");
  await denied("Administrator cannot open an Instructor training concern", () => admin.from("support_concerns").insert({
    scope: "training", class_id: classId, title: "Forbidden Admin training concern",
    details: "Administrator oversight cannot impersonate routine Instructor intake.",
  }));
  await denied("Instructor cannot read system incident", () => instructor.from("support_concerns")
    .select("id").eq("id", system.data.id));
  await denied("Learner cannot read staff concerns", () => learner.from("support_concerns").select("id"));

  const oversight = await admin.from("support_concerns").select("id").eq("id", training.data.id).single();
  assert(!oversight.error && oversight.data.id === training.data.id, "Admin training-history oversight missing");
  record("Administrator can review training concern without managing it");
  await denied("Administrator cannot update Instructor training concern", () => admin.from("support_concerns")
    .update({ status: "resolved", status_reason: "Forbidden Admin transition." })
    .eq("id", training.data.id).select("id"));
  await denied("Instructor cannot rewrite concern history", () => instructor.from("support_concerns")
    .update({ history: [] }).eq("id", training.data.id));
  await denied("A status change without a clear reason is rejected", () => instructor.from("support_concerns")
    .update({ status: "in_progress", status_reason: "Bad" }).eq("id", training.data.id));

  const transitioned = await instructor.from("support_concerns")
    .update({ status: "in_progress", status_reason: "Instructor is inspecting the workstation." })
    .eq("id", training.data.id).select("*").single();
  if (transitioned.error) throw transitioned.error;
  assert(transitioned.data.history.length === 2 &&
    transitioned.data.history[1].actor_id === users.get("instructor") &&
    transitioned.data.history[1].reason === "Instructor is inspecting the workstation.", "Status history is incomplete");
  record("Instructor transition preserves original event and reasoned actor/time history");

  const resolved = await admin.from("support_concerns")
    .update({ status: "resolved", status_reason: "Administrator completed the configuration review." })
    .eq("id", system.data.id).select("*").single();
  if (resolved.error) throw resolved.error;
  assert(resolved.data.resolved_at && resolved.data.history.length === 2, "System incident resolution history missing");
  record("Administrator resolution is retained with timestamp and prior status");
}

async function retire() {
  if (classId && clients.has("instructor")) {
    const archived = await clients.get("instructor").rpc("archive_class", {
      p_class_id: classId, p_reason: "Retire local-only concern E2E class while retaining issue history.",
    });
    if (archived.error) throw archived.error;
  }
  for (const client of clients.values()) await client.auth.signOut();
  if (users.size) {
    const ids = [...users.values()];
    const deactivated = await service.from("profiles").update({
      status: "deactivated", deactivated_at: new Date().toISOString(),
      deactivation_reason: `Disposable local support-concerns fixture ${runId} retired.`,
    }).in("user_id", ids);
    if (deactivated.error) throw deactivated.error;
    for (const id of ids) {
      const banned = await service.auth.admin.updateUserById(id, { ban_duration: "876000h" });
      if (banned.error) throw banned.error;
    }
  }
  record("disposable identities disabled and concern history retained");
}

let failed = false;
try {
  await createUsers();
  await verify();
  await verifyDashboardBoundary();
} catch (error) {
  failed = true;
  results.push({ name: "authenticated support-concerns lifecycle", status: "FAIL",
    detail: error instanceof Error ? error.message : String(error) });
} finally {
  try { await retire(); } catch (error) {
    failed = true;
    results.push({ name: "fixture retirement", status: "FAIL",
      detail: error instanceof Error ? error.message : String(error) });
  }
}

console.log(JSON.stringify({ runId, results }, null, 2));
if (failed) process.exitCode = 1;
