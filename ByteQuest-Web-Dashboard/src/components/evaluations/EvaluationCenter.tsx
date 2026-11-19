"use client";

import React, { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { ArrowRight, CheckCircle2, ClipboardCheck, Loader2, Send, ShieldCheck } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  AlertDialog, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { cn } from "@/lib/utils";
import { bulkRequestBodies, queueActionLabel, queueScoreText, queueStatusText } from "@/lib/evaluations/display";
import {
  EVALUATION_STAGES, KIND_LABEL, STAGE_COPY, type BulkItemResult, type EvaluationStage, type QueueItem,
} from "@/lib/evaluations/requests";

type Outcome = { action: "finalize" | "release"; results: (BulkItemResult & { title: string })[] };

function when(value: string | null) {
  if (!value) return "Not submitted";
  return new Intl.DateTimeFormat("en-PH", { dateStyle: "medium", timeStyle: "short", timeZone: "Asia/Manila" }).format(new Date(value));
}

export function EvaluationCenter({
  stage, counts, items, total, limit, offset, quizAvailable, canAct, query,
}: {
  stage: EvaluationStage;
  counts: Record<EvaluationStage, number>;
  items: QueueItem[];
  total: number;
  limit: number;
  offset: number;
  quizAvailable: boolean;
  canAct: boolean;
  /** Current filters (short names), preserved by tab and page links. */
  query: Record<string, string>;
}) {
  const router = useRouter();
  const [selected, setSelected] = useState<string[]>([]);
  const [confirming, setConfirming] = useState(false);
  const [busy, setBusy] = useState(false);
  const [outcome, setOutcome] = useState<Outcome | null>(null);
  const [error, setError] = useState("");
  const bulkAction = stage === "finalize" ? "finalize" : stage === "release" ? "release" : null;
  const selectable = canAct && bulkAction !== null;
  const key = (item: QueueItem) => `${item.kind}:${item.id}`;
  const chosen = items.filter((item) => selected.includes(key(item)));
  const allChosen = items.length > 0 && chosen.length === items.length;

  const href = (next: Record<string, string | number | undefined>) => {
    const params = new URLSearchParams();
    for (const [name, value] of Object.entries({ ...query, ...next })) {
      if (value !== undefined && value !== "" && !(name === "offset" && Number(value) === 0)) params.set(name, String(value));
    }
    return `/evaluations?${params.toString()}`;
  };

  const run = async () => {
    if (!bulkAction || busy || !chosen.length) return;
    setBusy(true); setError(""); setOutcome(null);
    const results: Outcome["results"] = [];
    try {
      // Mixed selections send one request per kind (technical, homework, quiz).
      for (const body of bulkRequestBodies(chosen, bulkAction)) {
        const group = chosen.filter((item) => item.kind === body.kind);
        const response = await fetch("/api/evaluations", {
          method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body), signal: AbortSignal.timeout(60000),
        });
        const payload = await response.json().catch(() => ({}));
        if (!response.ok) {
          for (const item of group) results.push({ id: item.id, title: item.title, ok: false, error: payload.error ?? "The request could not be completed." });
          continue;
        }
        for (const result of (payload.results ?? []) as BulkItemResult[]) {
          results.push({ ...result, title: group.find((item) => item.id === result.id)?.title ?? "Item" });
        }
      }
      setOutcome({ action: bulkAction, results });
      setSelected([]);
      router.refresh();
    } catch {
      setError("The connection was interrupted. Refresh to check which items changed before retrying.");
    } finally {
      setBusy(false); setConfirming(false);
    }
  };

  const succeeded = outcome?.results.filter((result) => result.ok).length ?? 0;
  const failed = outcome?.results.filter((result) => !result.ok) ?? [];
  const copy = STAGE_COPY[stage];

  return (
    <div className="space-y-5">
      <nav aria-label="Evaluation stages" className="grid grid-cols-2 gap-2 lg:grid-cols-4">
        {EVALUATION_STAGES.map((value, index) => {
          const active = value === stage;
          return (
            <Link
              key={value}
              href={href({ tab: value, offset: undefined })}
              aria-current={active ? "page" : undefined}
              className={cn(
                "flex min-h-14 items-center justify-between gap-3 rounded-xl border px-4 py-3 transition-colors duration-150 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
                active ? "border-primary bg-primary/[0.06] text-foreground" : "border-border bg-card text-muted-foreground hover:border-primary/40 hover:text-foreground",
              )}
            >
              <span className="flex min-w-0 items-center gap-2">
                <span className={cn("flex h-6 w-6 shrink-0 items-center justify-center rounded-full text-xs font-bold", active ? "bg-primary text-primary-foreground" : "bg-muted text-foreground/70")}>{index + 1}</span>
                <span className="truncate text-sm font-semibold">{STAGE_COPY[value].label}</span>
              </span>
              <span className="text-lg font-bold tabular-nums" aria-label={`${counts[value]} items`}>{counts[value]}</span>
            </Link>
          );
        })}
      </nav>
      <p className="text-sm text-muted-foreground">{copy.help}{!quizAvailable ? " Quiz essays join this queue once quiz evaluation is installed on the server." : ""}</p>

      {outcome ? (
        <div role="status" className={cn("rounded-xl border p-4 text-sm", failed.length ? "border-amber-300 bg-amber-50 text-amber-950" : "border-emerald-300 bg-emerald-50 text-emerald-950")}>
          <p className="font-semibold">
            {succeeded} {outcome.action === "finalize" ? "finalized" : "released"}{failed.length ? ` · ${failed.length} not changed` : ""}.
          </p>
          {failed.length ? (
            <ul className="mt-2 list-disc space-y-1 pl-5">
              {failed.map((result) => <li key={result.id}><span className="font-medium">{result.title}:</span> {result.error}</li>)}
            </ul>
          ) : null}
        </div>
      ) : null}
      {error ? <p role="alert" className="rounded-xl border border-destructive p-4 text-sm text-destructive">{error}</p> : null}

      <section aria-labelledby="queue-title" className="overflow-hidden rounded-xl border border-border bg-card">
        <div className="flex flex-col gap-3 border-b border-border px-4 py-3 sm:flex-row sm:items-center sm:justify-between">
          <div className="flex items-center gap-3">
            {selectable && items.length ? (
              <input
                type="checkbox"
                className="h-5 w-5 accent-primary"
                checked={allChosen}
                onChange={(event) => setSelected(event.target.checked ? items.map(key) : [])}
                aria-label={`Select all ${items.length} items on this page`}
              />
            ) : null}
            <h2 id="queue-title" className="font-semibold">{copy.label} · {total} item{total === 1 ? "" : "s"}</h2>
          </div>
          {selectable ? (
            <Button className="min-h-11" disabled={!chosen.length || busy} onClick={() => setConfirming(true)}>
              {bulkAction === "finalize" ? <ShieldCheck className="mr-2 h-4 w-4" aria-hidden="true" /> : <Send className="mr-2 h-4 w-4" aria-hidden="true" />}
              {bulkAction === "finalize" ? "Finalize" : "Release"} selected ({chosen.length})
            </Button>
          ) : null}
        </div>
        {items.length ? (
          <ul className="divide-y divide-border">
            {items.map((item) => (
              <li key={key(item)} className="grid gap-3 px-4 py-4 md:grid-cols-[auto_minmax(0,1.4fr)_minmax(0,1fr)_minmax(0,0.8fr)_auto] md:items-center">
                <div className="flex items-center">
                  {selectable ? (
                    <input
                      type="checkbox"
                      className="h-5 w-5 accent-primary"
                      checked={selected.includes(key(item))}
                      onChange={(event) => setSelected((current) => event.target.checked ? [...current, key(item)] : current.filter((value) => value !== key(item)))}
                      aria-label={`Select ${item.title} for ${item.learner.name ?? "learner"}`}
                    />
                  ) : <span className="sr-only">{KIND_LABEL[item.kind]}</span>}
                </div>
                <div className="min-w-0">
                  <p className="break-words text-sm font-semibold">{item.title}</p>
                  <div className="mt-1 flex flex-wrap gap-1.5">
                    <Badge variant="outline">{KIND_LABEL[item.kind]}</Badge>
                    {item.coc_code ? <Badge variant="secondary">{item.coc_code.toUpperCase()}</Badge> : null}
                    {item.mission_code ? <Badge variant="outline">{item.mission_code.toUpperCase().replace("_", " ")}</Badge> : null}
                    {item.late ? <Badge variant="outline" className="border-amber-300 text-amber-900">Late</Badge> : null}
                  </div>
                </div>
                <div className="min-w-0 text-sm">
                  <p className="truncate font-medium">{item.learner.name ?? "Learner"}</p>
                  <p className="truncate text-xs text-muted-foreground">{item.class.title ?? "Class"} · {when(item.submitted_at)}</p>
                </div>
                <div className="text-sm">
                  <p className="font-medium tabular-nums">{queueScoreText(item)}</p>
                  <p className="text-xs text-muted-foreground">{queueStatusText(item)}</p>
                </div>
                <Button asChild variant={stage === "released" ? "ghost" : "outline"} className="min-h-11 justify-self-start md:justify-self-end">
                  <Link href={item.link}>{queueActionLabel(stage, item)}<ArrowRight className="ml-2 h-4 w-4" aria-hidden="true" /></Link>
                </Button>
              </li>
            ))}
          </ul>
        ) : (
          <div className="px-5 py-14 text-center">
            {stage === "released" ? <CheckCircle2 className="mx-auto h-7 w-7 text-muted-foreground" aria-hidden="true" /> : <ClipboardCheck className="mx-auto h-7 w-7 text-muted-foreground" aria-hidden="true" />}
            <p className="mt-3 text-sm font-semibold">{copy.empty}</p>
            <p className="mt-1 text-sm text-muted-foreground">{copy.emptyHelp}</p>
          </div>
        )}
        {total > limit ? (
          <div className="flex items-center justify-between gap-3 border-t border-border px-4 py-3 text-sm">
            <span className="text-muted-foreground">Showing {offset + 1}–{Math.min(offset + limit, total)} of {total}</span>
            <div className="flex gap-2">
              <Button asChild variant="outline" className="min-h-11" aria-disabled={offset === 0}>
                <Link href={href({ offset: Math.max(0, offset - limit) })} tabIndex={offset === 0 ? -1 : undefined} className={offset === 0 ? "pointer-events-none opacity-50" : undefined}>Previous</Link>
              </Button>
              <Button asChild variant="outline" className="min-h-11" aria-disabled={offset + limit >= total}>
                <Link href={href({ offset: offset + limit })} tabIndex={offset + limit >= total ? -1 : undefined} className={offset + limit >= total ? "pointer-events-none opacity-50" : undefined}>Next</Link>
              </Button>
            </div>
          </div>
        ) : null}
      </section>

      <AlertDialog open={confirming} onOpenChange={(open) => { if (!busy) setConfirming(open); }}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{bulkAction === "finalize" ? `Finalize ${chosen.length} result${chosen.length === 1 ? "" : "s"}?` : `Release ${chosen.length} result${chosen.length === 1 ? "" : "s"} to learners?`}</AlertDialogTitle>
            <AlertDialogDescription>
              {bulkAction === "finalize"
                ? "Finalizing locks each recorded evaluation and grade. Learners still cannot see them until you release."
                : "Learners will see each released score and feedback immediately and receive a notification. Release cannot be undone from this page."}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <ul className="max-h-48 list-disc space-y-1 overflow-y-auto pl-5 text-sm">
            {chosen.map((item) => <li key={key(item)}>{item.title} · {item.learner.name ?? "Learner"}</li>)}
          </ul>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={busy} className="min-h-11">Cancel</AlertDialogCancel>
            <Button className="min-h-11" onClick={() => void run()} disabled={busy}>
              {busy ? <Loader2 className="mr-2 h-4 w-4 animate-spin" aria-hidden="true" /> : null}
              {bulkAction === "finalize" ? "Finalize" : "Release"} {chosen.length}
            </Button>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
