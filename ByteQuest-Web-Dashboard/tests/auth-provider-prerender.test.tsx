import assert from "node:assert/strict";
import test from "node:test";
import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { AuthProvider } from "../src/hooks/use-auth";

test("AuthProvider prerenders public pages without Supabase configuration", () => {
  const variableNames = [
    "NEXT_PUBLIC_SUPABASE_URL",
    "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY",
    "NEXT_PUBLIC_SUPABASE_ANON_KEY",
  ] as const;
  const originalValues = new Map(
    variableNames.map((name) => [name, process.env[name]]),
  );

  for (const name of variableNames) delete process.env[name];

  try {
    const markup = renderToStaticMarkup(
      <AuthProvider>
        <main>Public fallback</main>
      </AuthProvider>,
    );

    assert.match(markup, /Public fallback/);
  } finally {
    for (const name of variableNames) {
      const value = originalValues.get(name);
      if (value === undefined) delete process.env[name];
      else process.env[name] = value;
    }
  }
});
