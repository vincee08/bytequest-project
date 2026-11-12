// Owner-authorized ONE request with synthetic content only. No production use.
import assert from "node:assert/strict";
import fs from "node:fs";
import { randomUUID } from "node:crypto";
import { createServerClient } from "@supabase/ssr";
import { textPdf } from "./fixtures/resource-pdf.mjs";
const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
if (url !== "http://127.0.0.1:58921")
  throw new Error("Dedicated QA API required.");
if (!process.env.OPENROUTER_API_KEY?.trim()) {
  console.log(
    "BLOCKED: local OpenRouter key is missing; no provider request or test write made.",
  );
  process.exit(2);
}
const account = JSON.parse(
  fs.readFileSync(".tmp/quiz-preview-accounts.json", "utf8"),
).accounts.instructor;
const cookies = [];
const client = createServerClient(
  url,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
  {
    cookies: {
      getAll: () => cookies,
      setAll: (values) => {
        for (const value of values) {
          const index = cookies.findIndex(
            (cookie) => cookie.name === value.name,
          );
          if (index < 0) cookies.push(value);
          else cookies[index] = value;
        }
      },
    },
  },
);
async function ok(promise) {
  const { data, error } = await promise;
  assert(!error, error?.message);
  return data;
}
await ok(
  client.auth.signInWithPassword({
    email: account.email,
    password: account.password,
  }),
);
const base = "http://localhost:3008";
const headers = {
  Cookie: cookies.map((cookie) => `${cookie.name}=${cookie.value}`).join("; "),
};
const status = await (
  await fetch(`${base}/api/instructor/quizzes/ai-draft`, { headers })
).json();
assert(
  status.configured && !status.simulated,
  "Start the local preview with ai-start first.",
);
const cls = await ok(
  client.rpc("create_class", {
    p_title: "Synthetic live-provider QA",
    p_class_code: `LIVE-${randomUUID().slice(0, 8)}`,
  }),
);
const body = new FormData();
body.set("title", "Synthetic networking reference");
body.set(
  "file",
  new File([textPdf()], "synthetic-network.pdf", { type: "application/pdf" }),
);
const upload = await fetch(`${base}/api/classes/${cls.id}/resources`, {
  method: "POST",
  headers,
  body,
});
assert(upload.ok, `Synthetic PDF upload failed (${upload.status}).`);
const resource = (await upload.json()).resource;
const quiz = await ok(
  client.rpc("create_instructor_quiz", {
    p_title: "Synthetic live-provider draft — review required",
    p_topic: "Network devices",
  }),
);
const version = await ok(
  client.from("quiz_versions").select("id").eq("quiz_id", quiz.id).single(),
);
const response = await fetch(`${base}/api/instructor/quizzes/ai-draft`, {
  method: "POST",
  headers: { ...headers, "Content-Type": "application/json" },
  body: JSON.stringify({
    quizVersionId: version.id,
    sourceMode: "class_resource",
    classId: cls.id,
    resourceId: resource.id,
    externalConsent: true,
    requestId: randomUUID(),
    topic: "Router versus switch",
    difficulty: "foundation",
    itemCount: 1,
    itemTypes: ["multiple_choice"],
  }),
});
const result = await response.json();
assert.equal(response.status, 201, result.error);
const items = await ok(
  client
    .from("quiz_items")
    .select("review_status,origin")
    .eq("quiz_version_id", version.id),
);
assert.equal(items.length, 1);
assert(
  items.every(
    (item) =>
      item.review_status === "draft" && item.origin === "ai_generated_draft",
  ),
);
console.log(
  "PASS REAL OpenRouter: one synthetic-PDF request returned one validated editable draft; nothing approved or published.",
);
