"use client";

import { useEffect, useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { RefreshCw } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useAuth } from "@/hooks/use-auth";
import { formatClock } from "@/lib/analytics/format";
import { createClient } from "@/lib/supabase/client";
import { cn } from "@/lib/utils";

/**
 * Tables that feed the analytics but are not watched by the layout-wide
 * RealtimeRouteRefresh (which already covers assessment, quiz and homework
 * tables). RLS limits delivered events to the caller's own classes.
 */
export const ANALYTICS_REALTIME_TABLES = [
  "practice_mission_runs",
  "practice_mission_completions",
  "practice_coc_progress",
  "learner_topic_progress",
  "learner_module_completions",
] as const;

/** Polling fallback while the page is visible. */
export const ANALYTICS_POLL_MS = 30_000;

export function AnalyticsLiveRefresh({ generatedAt, className }: { generatedAt: string; className?: string }) {
  const router = useRouter();
  const { user } = useAuth();
  const [subscribed, setSubscribed] = useState(false);
  const [pending, startTransition] = useTransition();
  const debounce = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    if (!user) return;
    const supabase = createClient();
    let channel: ReturnType<typeof supabase.channel> | null = null;
    let cancelled = false;
    const queueRefresh = () => {
      if (debounce.current) clearTimeout(debounce.current);
      debounce.current = setTimeout(() => startTransition(() => router.refresh()), 400);
    };
    void supabase.auth.getSession().then(({ data }) => {
      if (cancelled || !data.session) return;
      supabase.realtime.setAuth(data.session.access_token);
      channel = supabase.channel(`analytics-live:${user.userId}`);
      for (const table of ANALYTICS_REALTIME_TABLES) {
        channel.on("postgres_changes", { event: "*", schema: "public", table }, queueRefresh);
      }
      channel.subscribe((status) => setSubscribed(status === "SUBSCRIBED"));
    });
    return () => {
      cancelled = true;
      if (debounce.current) clearTimeout(debounce.current);
      debounce.current = null;
      if (channel) void supabase.removeChannel(channel);
    };
  }, [router, user]);

  useEffect(() => {
    let interval: ReturnType<typeof setInterval> | null = null;
    const stop = () => {
      if (interval) clearInterval(interval);
      interval = null;
    };
    const start = () => {
      stop();
      if (document.visibilityState === "visible") {
        interval = setInterval(() => startTransition(() => router.refresh()), ANALYTICS_POLL_MS);
      }
    };
    const onVisibility = () => {
      if (document.visibilityState === "visible") {
        startTransition(() => router.refresh());
        start();
      } else {
        stop();
      }
    };
    start();
    document.addEventListener("visibilitychange", onVisibility);
    return () => {
      stop();
      document.removeEventListener("visibilitychange", onVisibility);
    };
  }, [router]);

  return (
    <div className={cn("flex flex-wrap items-center gap-2 text-xs text-muted-foreground", className)}>
      <span className="inline-flex items-center gap-1.5" aria-live="polite">
        <span className={cn("h-2 w-2 rounded-full", subscribed ? "bg-emerald-600" : "bg-amber-500")} aria-hidden="true" />
        <span>
          Updated <time dateTime={generatedAt} className="font-medium tabular-nums text-foreground">{formatClock(generatedAt)}</time>
        </span>
        <span className="hidden sm:inline">· {subscribed ? "Live updates on" : "Refreshing every 30 s"}</span>
      </span>
      <Button
        type="button"
        variant="ghost"
        size="sm"
        className="h-9 px-2.5"
        onClick={() => startTransition(() => router.refresh())}
        disabled={pending}
        aria-label="Refresh analytics now"
      >
        <RefreshCw className={cn("h-3.5 w-3.5", pending && "animate-spin motion-reduce:animate-none")} aria-hidden="true" />
        <span className="ml-1.5">{pending ? "Refreshing…" : "Refresh"}</span>
      </Button>
    </div>
  );
}
