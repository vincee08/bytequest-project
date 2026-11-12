import assert from "node:assert/strict";
import { test } from "node:test";
import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { AppRouterContext, type AppRouterInstance } from "next/dist/shared/lib/app-router-context.shared-runtime";
import { EnrollLearnerForm } from "../src/components/classes/EnrollLearnerForm";

test("enrollment prerenders a labelled combobox and requires a selected profile", () => {
  const router: AppRouterInstance = { back() {}, forward() {}, refresh() {}, push() {}, replace() {}, prefetch() {} };
  const html = renderToStaticMarkup(<AppRouterContext.Provider value={router}><EnrollLearnerForm classId="75d06c08-b60b-4cbc-a26e-fc0bb344b58e" /></AppRouterContext.Provider>);
  assert.match(html, /role="combobox"/);
  assert.match(html, /aria-label="Enroll a learner"/);
  assert.match(html, /Search learner by name or email/);
  assert.match(html, /aria-expanded="false"/);
  assert.match(html, /type="submit" disabled=""/);
  assert(!html.includes('type="email"'));
  assert(!html.includes('role="option"'));
});
