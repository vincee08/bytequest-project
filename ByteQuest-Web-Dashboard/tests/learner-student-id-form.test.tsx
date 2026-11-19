import assert from "node:assert/strict";
import { test } from "node:test";
import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { AppRouterContext, type AppRouterInstance } from "next/dist/shared/lib/app-router-context.shared-runtime";
import { StudentIdForm } from "../src/components/users/StudentIdForm";

const router: AppRouterInstance = { back() {}, forward() {}, refresh() {}, push() {}, replace() {}, prefetch() {} };
const render = (node: React.ReactNode) => renderToStaticMarkup(<AppRouterContext.Provider value={router}>{node}</AppRouterContext.Provider>);
const buttons = (html: string) => html.split("<button").slice(1);

test("a staff-managed ID shows its state, can be changed or cleared, and cannot be resaved unchanged", () => {
  const html = render(<StudentIdForm userId="u1" studentId="2026-0001" managed />);
  assert.match(html, /Staff-managed/);
  assert.match(html, /value="2026-0001"/);
  const [save, clear] = buttons(html);
  assert.match(save, /^[^>]*disabled=""/);
  assert.match(save, /Save student ID/);
  assert.match(clear, /Clear student ID/);
  assert.doesNotMatch(clear, /^[^>]*disabled=""/);
});

test("a learner without an ID can be given one; nothing to clear", () => {
  const html = render(<StudentIdForm userId="u2" studentId={null} managed={false} />);
  assert.match(html, /Set by learner/);
  const all = buttons(html);
  assert.equal(all.length, 1);
  assert.match(all[0], /Confirm and lock/);
  assert.match(all[0], /^[^>]*disabled=""/);
});
