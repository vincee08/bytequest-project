import fs from "node:fs";
import assert from "node:assert/strict";
import { createClient } from "@supabase/supabase-js";
if (process.env.NEXT_PUBLIC_SUPABASE_URL !== "http://127.0.0.1:58921")
  throw new Error("Dedicated QA API required.");
const fixture = JSON.parse(
  fs.readFileSync(".tmp/quiz-preview-accounts.json", "utf8"),
);
const client = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
  { auth: { persistSession: false, autoRefreshToken: false } },
);
async function ok(promise) {
  const { data, error } = await promise;
  assert(!error, error?.message);
  return data;
}
await ok(
  client.auth.signInWithPassword({
    email: fixture.accounts.instructor.email,
    password: fixture.accounts.instructor.password,
  }),
);
let cls = await ok(
  client
    .from("classes")
    .select("id,title,status")
    .eq("instructor_id", fixture.accounts.instructor.id)
    .eq("class_code", "OWNER-PDF-QA")
    .maybeSingle(),
);
if (!cls)
  cls = await ok(
    client.rpc("create_class", {
      p_title: "Owner PDF Quiz Testing",
      p_class_code: "OWNER-PDF-QA",
    }),
  );
assert.equal(
  cls.status,
  "active",
  "The owner class was archived; do not reset its state automatically.",
);
for (const name of ["learner", "resumeLearner"]) {
  const membership = await ok(
    client
      .from("class_memberships")
      .select("id")
      .eq("class_id", cls.id)
      .eq("learner_id", fixture.accounts[name].id)
      .maybeSingle(),
  );
  if (!membership)
    await ok(
      client.rpc("enroll_learner", {
        p_class_id: cls.id,
        p_learner_id: fixture.accounts[name].id,
      }),
    );
}
const state = {
  classId: cls.id,
  classTitle: cls.title,
  classUrl: `http://localhost:3008/classes/${cls.id}?tab=resources`,
  instructorUrl: "http://localhost:3008",
  learnerUrl: "http://127.0.0.1:3009",
  accountFile: ".tmp/quiz-preview-accounts.json",
  samplePdf: ".tmp/bytequest-sample-networking.pdf",
};
fs.writeFileSync(
  ".tmp/quiz-resource-owner-setup.json",
  JSON.stringify(state, null, 2),
);
console.log(
  `Owner class ready: ${state.classUrl}. Existing QA accounts retained; no learner attempt was started.`,
);
