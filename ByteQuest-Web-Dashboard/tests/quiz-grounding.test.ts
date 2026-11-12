import assert from "node:assert/strict";
import { test } from "node:test";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "../src/types/database.generated";
import { loadApprovedQuizGrounding } from "../src/lib/ai/quiz-grounding";

function context(
  change?: (tables: Record<string, Record<string, unknown>[]>) => void,
) {
  const tables: Record<string, Record<string, unknown>[]> = {
    coc_modules: [
      {
        id: "coc",
        coc_code: "COC2",
        title: "Networks",
        competency_id: "competency",
      },
    ],
    competencies: [
      {
        id: "competency",
        competency_code: "ELC724332",
        name: "Networks",
        source_trace: "Reviewed source section",
        tesda_source_id: "source",
      },
    ],
    tesda_sources: [
      {
        id: "source",
        qualification_code: "CSS",
        title: "Approved test source",
        edition: "Test",
        source_reference: "Test reference",
        status: "active",
        approved_at: "2026-01-01",
        activated_at: "2026-01-01",
      },
    ],
    module_versions: [
      {
        id: "module",
        module_id: "coc",
        tesda_source_id: "source",
        title: "Module",
        version_number: 1,
        status: "published",
        source_trace: {},
      },
    ],
    activity_versions: [
      {
        id: "activity",
        module_version_id: "module",
        mission_id: "mission",
        title: "Activity",
        version_number: 1,
        status: "published",
      },
    ],
    missions: [
      {
        id: "mission",
        coc_id: "coc",
        competency_id: "competency",
        mission_number: 1,
        title: "Mission",
        objective: "Verify network connectivity",
        scenario: "Inspect a small network",
        skills_assessed: ["Verification"],
      },
    ],
    rubric_versions: [
      {
        id: "rubric",
        activity_version_id: "activity",
        tesda_source_id: "source",
        title: "Rubric",
        version_number: 1,
        status: "approved",
        approved_at: "2026-01-01",
      },
    ],
    rubric_criteria: [
      {
        rubric_version_id: "rubric",
        criterion_code: "VERIFY",
        title: "Verify",
        source_trace: "Approved section",
        is_required: true,
      },
    ],
  };
  change?.(tables);
  return {
    from(name: string) {
      let rows = tables[name] ?? [];
      const query = {
        select() {
          return query;
        },
        eq(key: string, value: unknown) {
          rows = rows.filter((row) => row[key] === value);
          return query;
        },
        order() {
          return query;
        },
        limit() {
          return query;
        },
        maybeSingle: async () => ({ data: rows[0] ?? null }),
        then(resolve: (value: unknown) => unknown) {
          return Promise.resolve({ data: rows }).then(resolve);
        },
      };
      return query;
    },
  } as unknown as SupabaseClient<Database>;
}
test("approved COC mode loads only the selected published activity and approved source/rubric", async () => {
  const value = await loadApprovedQuizGrounding(context(), "coc", "activity");
  assert.equal(value.activity.id, "activity");
  assert.equal(value.source.id, "source");
  assert.equal(value.rubric.id, "rubric");
});
test("missing approval, inactive sources, unpublished content and missing source traces remain blocked", async () => {
  for (const mutate of [
    (tables: Record<string, Record<string, unknown>[]>) => {
      tables.tesda_sources[0].approved_at = null;
    },
    (tables: Record<string, Record<string, unknown>[]>) => {
      tables.tesda_sources[0].status = "pending_tesda_validation";
    },
    (tables: Record<string, Record<string, unknown>[]>) => {
      tables.module_versions[0].status = "draft";
    },
    (tables: Record<string, Record<string, unknown>[]>) => {
      tables.rubric_versions[0].status = "pending_tesda_validation";
    },
    (tables: Record<string, Record<string, unknown>[]>) => {
      tables.rubric_criteria[0].source_trace = "";
    },
  ])
    await assert.rejects(
      loadApprovedQuizGrounding(context(mutate), "coc", "activity"),
      /CONTEXT_/,
    );
  await assert.rejects(
    loadApprovedQuizGrounding(context(), "coc", "foreign-activity"),
    /CONTEXT_NOT_APPROVED/,
  );
});
