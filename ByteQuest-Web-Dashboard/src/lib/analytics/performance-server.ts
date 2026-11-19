import "server-only";

import type { SupabaseClient } from "@supabase/supabase-js";
import type { ZodType, ZodTypeDef } from "zod";
import { createServerSupabaseClient } from "@/lib/supabase/server";
import type { Database, Json } from "@/types/database.generated";
import {
  analyticsErrorCode,
  classPerformanceSchema,
  criteriaAnalyticsSchema,
  filterOptionsSchema,
  learnerPerformanceSchema,
  learnerProfileSchema,
  missionAnalyticsSchema,
  overviewSchema,
  quizAnalyticsSchema,
  type AnalyticsErrorCode,
  type FilterOptions,
  type LearnerProfile,
} from "@/lib/analytics/performance-types";
import type { AnalyticsTabData, AnalyticsViewResult } from "@/lib/analytics/performance-csv";
import { toRpcFilters, type AnalyticsQuery, type AnalyticsTab } from "@/lib/analytics/query";

type FiltersArg = { p_filters: Json };
type AnalyticsDatabase = Omit<Database, "public"> & {
  public: Omit<Database["public"], "Functions"> & {
    Functions: Database["public"]["Functions"] & {
      get_analytics_filter_options: { Args: Record<string, never>; Returns: Json };
      get_analytics_overview: { Args: FiltersArg; Returns: Json };
      get_class_performance: { Args: FiltersArg; Returns: Json };
      get_learner_performance: { Args: FiltersArg; Returns: Json };
      get_learner_profile_analytics: { Args: { p_learner: string; p_filters: Json }; Returns: Json };
      get_quiz_analytics: { Args: { p_quiz_id: string | null; p_filters: Json }; Returns: Json };
      get_mission_analytics: { Args: FiltersArg; Returns: Json };
      get_criteria_analytics: { Args: FiltersArg; Returns: Json };
    };
  };
};
type AnalyticsFunction = keyof AnalyticsDatabase["public"]["Functions"];

export class AnalyticsRequestError extends Error {
  constructor(readonly code: AnalyticsErrorCode, options?: { cause?: unknown }) {
    super(code, options);
    this.name = "AnalyticsRequestError";
  }
}

async function analyticsClient() {
  return (await createServerSupabaseClient()) as unknown as SupabaseClient<AnalyticsDatabase>;
}

async function invoke<T>(
  client: SupabaseClient<AnalyticsDatabase>,
  fn: AnalyticsFunction,
  args: Record<string, Json | string | null>,
  schema: ZodType<T, ZodTypeDef, unknown>,
): Promise<T> {
  const { data, error } = await client.rpc(fn as never, args as never);
  if (error) throw new AnalyticsRequestError(analyticsErrorCode(error.message), { cause: error });
  const parsed = schema.safeParse(data);
  if (!parsed.success) throw new AnalyticsRequestError("ANALYTICS_UNAVAILABLE", { cause: parsed.error });
  return parsed.data;
}

/** Loads the data behind one analytics tab for the caller's RLS scope. */
export async function loadAnalyticsTab(query: AnalyticsQuery, tab: AnalyticsTab = query.tab): Promise<AnalyticsTabData> {
  const client = await analyticsClient();
  const filters = toRpcFilters(query) as Json;
  switch (tab) {
    case "overview":
      return { tab, data: await invoke(client, "get_analytics_overview", { p_filters: filters }, overviewSchema) };
    case "classes":
      return { tab, data: await invoke(client, "get_class_performance", { p_filters: filters }, classPerformanceSchema) };
    case "learners":
      return { tab, data: await invoke(client, "get_learner_performance", { p_filters: filters }, learnerPerformanceSchema) };
    case "quizzes":
      return {
        tab,
        data: await invoke(client, "get_quiz_analytics", { p_quiz_id: query.quizId, p_filters: filters }, quizAnalyticsSchema),
      };
    case "missions":
      return { tab, data: await invoke(client, "get_mission_analytics", { p_filters: filters }, missionAnalyticsSchema) };
    case "criteria":
      return { tab, data: await invoke(client, "get_criteria_analytics", { p_filters: filters }, criteriaAnalyticsSchema) };
  }
}

export async function loadAnalyticsFilterOptions(): Promise<FilterOptions> {
  const client = await analyticsClient();
  return invoke(client, "get_analytics_filter_options", {}, filterOptionsSchema);
}

export async function loadLearnerProfile(learnerId: string, query: AnalyticsQuery): Promise<LearnerProfile> {
  const client = await analyticsClient();
  const filters = { ...toRpcFilters(query) };
  delete filters.learner_id;
  return invoke(client, "get_learner_profile_analytics", { p_learner: learnerId, p_filters: filters as Json }, learnerProfileSchema);
}

/** Options + active tab in parallel; known scope/filter errors become an inline state. */
export async function loadAnalyticsView(query: AnalyticsQuery): Promise<AnalyticsViewResult> {
  const [options, view] = await Promise.allSettled([loadAnalyticsFilterOptions(), loadAnalyticsTab(query)]);
  const resolvedOptions = options.status === "fulfilled" ? options.value : null;
  if (view.status === "fulfilled" && resolvedOptions) return { ok: true, options: resolvedOptions, view: view.value };
  const failure = view.status === "rejected" ? view.reason : options.status === "rejected" ? options.reason : null;
  if (failure instanceof AnalyticsRequestError) return { ok: false, code: failure.code, options: resolvedOptions };
  throw failure instanceof Error ? failure : new Error("Analytics are unavailable.");
}
