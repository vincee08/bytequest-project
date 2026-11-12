// Revoke disposable local test refresh sessions after a runner diagnostic leak.
import fs from "node:fs";
import { createClient } from "@supabase/supabase-js";
if (process.env.NEXT_PUBLIC_SUPABASE_URL !== "http://127.0.0.1:58921")
  throw new Error("Dedicated QA API required.");
const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const service = createClient(url, process.env.SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});
const account = JSON.parse(
  fs.readFileSync(".tmp/quiz-preview-accounts.json", "utf8"),
).accounts.instructor;
const client = createClient(url, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});
const { data, error } = await client.auth.signInWithPassword({
  email: account.email,
  password: account.password,
});
if (error || !data.session) throw new Error("QA sign-in failed.");
const revoked = await service.auth.admin.signOut(
  data.session.access_token,
  "global",
);
if (revoked.error) throw new Error("QA refresh-session revocation failed.");
console.log(
  "Affected local QA Instructor refresh sessions ended. Existing access tokens expire normally. Sign in again for owner testing.",
);
