import "server-only";

import { createClient } from "@supabase/supabase-js";
import type { Database } from "@/types/database.generated";

export function createAdminSupabaseClient(timeoutMs?: number) {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!url || !serviceRoleKey) {
    throw new Error("Supabase server administration configuration is missing.");
  }

  return createClient<Database>(url, serviceRoleKey, {
    ...(timeoutMs
      ? {
          global: {
            fetch: (input: RequestInfo | URL, init?: RequestInit) =>
              fetch(input, {
                ...init,
                signal: init?.signal
                  ? AbortSignal.any([
                      init.signal,
                      AbortSignal.timeout(timeoutMs),
                    ])
                  : AbortSignal.timeout(timeoutMs),
              }),
          },
        }
      : {}),
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}
