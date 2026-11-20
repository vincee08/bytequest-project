import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { endRefusedSignIn } from "../src/lib/auth/refused-sign-in";

// QA audit 2026-11-20: a learner who tried the staff dashboard was refused
// with a global sign-out, which revoked the learner app's session as well.

test("a refused dashboard sign-in ends only its own session", async () => {
  const calls: unknown[] = [];
  await endRefusedSignIn({
    async signOut(options) {
      calls.push(options);
      return { error: null };
    },
  });
  assert.deepEqual(calls, [{ scope: "local" }]);
});

test("the login form never refuses with a global sign-out", () => {
  const source = readFileSync(new URL("../src/components/auth/LoginForm.tsx", import.meta.url), "utf8");
  assert.doesNotMatch(source, /\.signOut\(\s*\)/, "a bare signOut() defaults to the global scope");
  assert.equal(source.match(/endRefusedSignIn\(supabase\.auth\)/g)?.length, 3,
    "missing profile, inactive account and learner account are all refused locally");
});
