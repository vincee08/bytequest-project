import "server-only";

import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database, Json } from "@/types/database.generated";
import { learnerSearchRpcArgs, type LearnerSearchFilters, type LearnerSearchResult } from "./search";

type SearchDatabase = Omit<Database, "public"> & {
  public: Omit<Database["public"], "Functions"> & {
    Functions: Database["public"]["Functions"] & {
      search_learners: {
        Args: { p_query: string | null; p_class_id: string | null; p_status: string | null; p_sort: string; p_limit: number; p_offset: number };
        Returns: Json;
      };
    };
  };
};

/**
 * Runs public.search_learners with the caller's own session (RLS decides the
 * scope: admins see every learner, instructors only learners in their own
 * active classes). Returns a safe message instead of database details.
 */
export async function runLearnerSearch(
  client: SupabaseClient<Database>,
  filters: LearnerSearchFilters,
): Promise<{ data: LearnerSearchResult; error: null } | { data: null; error: string }> {
  try {
    const { data, error } = await (client as unknown as SupabaseClient<SearchDatabase>).rpc("search_learners", learnerSearchRpcArgs(filters) as never); // NULL filters mean "no filter"; generated RPC types cannot express nullable parameters.
    if (error || !data) return { data: null, error: "Learner search is unavailable right now. Try again in a moment." };
    return { data: data as unknown as LearnerSearchResult, error: null };
  } catch {
    return { data: null, error: "Learner search is unavailable right now. Check the connection and try again." };
  }
}
