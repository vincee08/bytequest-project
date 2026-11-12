"use client";

import React, { useEffect, useId, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { Check, ChevronLeft, ChevronRight, Loader2, Search, UserPlus, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { enrollmentLabels, type EnrollmentLearner } from "@/lib/learners/enrollment";

class EnrollmentRequestError extends Error {}

export function EnrollLearnerForm({ classId }: { classId: string }) {
  const router = useRouter();
  const id = useId();
  const inputRef = useRef<HTMLInputElement>(null);
  const submittingRef = useRef(false);
  const [query, setQuery] = useState("");
  const [page, setPage] = useState(0);
  const [results, setResults] = useState<EnrollmentLearner[]>([]);
  const [hasMore, setHasMore] = useState(false);
  const [selected, setSelected] = useState<EnrollmentLearner | null>(null);
  const [open, setOpen] = useState(false);
  const [activeIndex, setActiveIndex] = useState(-1);
  const [loading, setLoading] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");
  const [feedback, setFeedback] = useState("");
  const term = query.trim();
  const listId = `${id}-results`;
  const expanded = open && !selected && term.length >= 2;

  useEffect(() => {
    const normalizedQuery = query.trim();
    setResults([]);
    setHasMore(false);
    setActiveIndex(-1);
    if (selected || normalizedQuery.length < 2) { setLoading(false); return; }
    const controller = new AbortController();
    setLoading(true);
    const timer = setTimeout(async () => {
      try {
        const params = new URLSearchParams({ q: normalizedQuery, page: String(page) });
        const response = await fetch(`/api/classes/${classId}/learners?${params}`, {
          signal: AbortSignal.any([controller.signal, AbortSignal.timeout(12_000)]), cache: "no-store",
        });
        const data = await response.json();
        if (controller.signal.aborted) return;
        if (!response.ok) throw new EnrollmentRequestError(data.error ?? "Learners could not be loaded. Try again.");
        setResults(data.learners);
        setHasMore(data.hasMore);
        setError("");
      } catch (cause) {
        if (!controller.signal.aborted) setError(cause instanceof EnrollmentRequestError ? cause.message : "Learner search could not be completed. Check your connection and try again.");
      } finally {
        if (!controller.signal.aborted) setLoading(false);
      }
    }, 300);
    return () => { clearTimeout(timer); controller.abort(); };
  }, [classId, query, page, selected]);

  useEffect(() => {
    if (expanded && activeIndex >= 0) document.getElementById(`${listId}-${activeIndex}`)?.scrollIntoView({ block: "nearest" });
  }, [activeIndex, expanded, listId]);

  function choose(learner: EnrollmentLearner) {
    setSelected(learner);
    setQuery(learner.fullName || learner.email);
    setOpen(false);
    setError("");
    setFeedback("");
    inputRef.current?.focus();
  }

  function changePage(next: number) {
    setPage(next);
    inputRef.current?.focus();
  }

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    if (submittingRef.current || selected?.enrollment === "active") return;
    if (!selected) { setError("Select a registered learner from the search results."); inputRef.current?.focus(); return; }
    submittingRef.current = true;
    setSubmitting(true);
    setError("");
    setFeedback("");
    try {
      const response = await fetch(`/api/classes/${classId}/learners`, {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ learnerId: selected.id }),
        signal: AbortSignal.timeout(20_000),
      });
      const data = await response.json();
      if (response.status === 409) {
        setSelected({ ...selected, enrollment: "active" });
        router.refresh();
      }
      if (!response.ok) throw new EnrollmentRequestError(data.error ?? "Enrollment could not be confirmed. Refresh the class before retrying.");
      setSelected({ ...selected, enrollment: "active" });
      setFeedback(`${selected.fullName || selected.email} is enrolled. The class membership list has been refreshed.`);
      router.refresh();
    } catch (cause) {
      setError(cause instanceof EnrollmentRequestError ? cause.message : "Enrollment could not be confirmed. Refresh the class before retrying.");
    } finally {
      submittingRef.current = false;
      setSubmitting(false);
    }
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-3" aria-label="Enroll a learner" aria-busy={submitting}>
      <div className="flex flex-col gap-3 sm:flex-row sm:items-start">
        <div className="min-w-0 flex-1 space-y-2">
          <Label htmlFor={`${id}-search`}>Search learner by name or email</Label>
          <div className="relative" onBlur={(event) => {
            if (!event.currentTarget.contains(event.relatedTarget as Node | null)) setOpen(false);
          }} onKeyDown={(event) => {
            if (event.key === "Escape") { setOpen(false); inputRef.current?.focus(); }
          }}>
            <Search className="pointer-events-none absolute left-3 top-3.5 h-4 w-4 text-muted-foreground" aria-hidden="true" />
            <Input id={`${id}-search`} ref={inputRef} role="combobox" aria-autocomplete="list" aria-expanded={expanded}
              aria-controls={expanded ? listId : undefined} aria-activedescendant={expanded && activeIndex >= 0 ? `${listId}-${activeIndex}` : undefined}
              aria-describedby={`${id}-hint`} autoComplete="off" maxLength={100} value={query} disabled={submitting}
              placeholder="Enter a learner name or email" className="min-h-11 pl-9 pr-11 text-base sm:text-sm"
              onFocus={() => setOpen(true)} onChange={(event) => {
                setQuery(event.target.value); setSelected(null); setPage(0); setResults([]); setActiveIndex(-1);
                setError(""); setFeedback(""); setOpen(true);
              }} onKeyDown={(event) => {
                if (event.nativeEvent.isComposing) return;
                if (event.key === "ArrowDown" || event.key === "ArrowUp") {
                  event.preventDefault(); setOpen(true);
                  if (results.length) setActiveIndex((current) => event.key === "ArrowDown" ? Math.min(current + 1, results.length - 1) : current < 0 ? results.length - 1 : Math.max(0, current - 1));
                }
                if (event.key === "Enter" && expanded) {
                  event.preventDefault(); if (activeIndex >= 0 && results[activeIndex]) choose(results[activeIndex]);
                }
              }} />
            {query ? <Button type="button" variant="ghost" size="icon" className="absolute right-0 top-0 h-11 w-11" disabled={submitting}
              aria-label="Clear learner selection and search" onClick={() => {
                setQuery(""); setSelected(null); setResults([]); setPage(0); setError(""); setFeedback(""); setOpen(false); inputRef.current?.focus();
              }}><X className="h-4 w-4" aria-hidden="true" /></Button> : null}
            {expanded ? <div className="absolute inset-x-0 top-full z-30 mt-1 overflow-hidden rounded-lg border border-border bg-popover text-popover-foreground shadow-lg">
              <div role="listbox" id={listId} aria-label="Registered learners" aria-busy={loading} className="max-h-64 overflow-y-auto overscroll-contain p-1">
                {results.map((learner, index) => <button key={learner.id} type="button" role="option" tabIndex={-1}
                  id={`${listId}-${index}`} aria-selected={activeIndex === index} onMouseDown={(event) => event.preventDefault()}
                  onClick={() => choose(learner)} onPointerMove={() => setActiveIndex(index)}
                  className={`flex min-h-16 w-full items-center gap-3 rounded-md px-3 py-2 text-left ${activeIndex === index ? "bg-accent text-accent-foreground" : "hover:bg-muted"}`}>
                  <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-primary/10 text-xs font-semibold text-primary" aria-hidden="true">
                    {(learner.fullName || learner.email).trim().split(/\s+/).slice(0, 2).map((word) => word[0]).join("").toUpperCase()}
                  </span>
                  <span className="min-w-0 flex-1 [overflow-wrap:anywhere]"><span className="block text-sm font-medium">{learner.fullName || "Unnamed learner"}</span>
                    <span className="block text-xs text-muted-foreground">{learner.email}</span>
                    <span className="mt-0.5 block text-xs text-muted-foreground">{enrollmentLabels[learner.enrollment]}</span>
                  </span>
                  {learner.enrollment === "active" ? <Check className="h-4 w-4 shrink-0 text-primary" aria-hidden="true" /> : null}
                </button>)}
              </div>
              <p className="px-4 py-2 text-xs text-muted-foreground" role="status" aria-live="polite">
                {loading ? <span className="flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" />Searching registered learners…</span>
                  : error ? "Search is unavailable. See the message below."
                  : results.length ? `${results.length} matches on page ${page + 1}. Use arrow keys and Enter to select.` : "No registered learners match. Try a different name or email."}
              </p>
              {page > 0 || hasMore ? <div className="flex items-center justify-between gap-3 border-t border-border p-2">
                <Button type="button" variant="ghost" className="min-h-11" disabled={!page || loading} onClick={() => changePage(page - 1)} aria-label="Previous learner results"><ChevronLeft className="mr-1 h-4 w-4" aria-hidden="true" />Previous</Button>
                <Button type="button" variant="ghost" className="min-h-11" disabled={!hasMore || loading} onClick={() => changePage(page + 1)} aria-label="Next learner results">Next<ChevronRight className="ml-1 h-4 w-4" aria-hidden="true" /></Button>
              </div> : null}
            </div> : null}
          </div>
          <p id={`${id}-hint`} className="text-xs text-muted-foreground">Type at least two characters. Only existing active learner accounts are available.</p>
        </div>
        <Button type="submit" disabled={!selected || selected.enrollment === "active" || submitting} className="min-h-11 sm:mt-7">
          {submitting ? <Loader2 className="mr-2 h-4 w-4 animate-spin" aria-hidden="true" /> : <UserPlus className="mr-2 h-4 w-4" aria-hidden="true" />}
          {submitting ? "Enrolling…" : selected?.enrollment === "active" ? "Already enrolled" : "Enroll learner"}
        </Button>
      </div>
      {selected ? <div className="flex min-w-0 items-start gap-3 rounded-lg border border-primary/20 bg-primary/5 p-3">
        <Check className="mt-0.5 h-4 w-4 shrink-0 text-primary" aria-hidden="true" />
        <div className="min-w-0 text-sm [overflow-wrap:anywhere]"><p className="font-medium">Selected: {selected.fullName || "Unnamed learner"}</p><p className="text-muted-foreground">{selected.email}</p>
          <p className="mt-1 text-xs text-muted-foreground">{enrollmentLabels[selected.enrollment]}{selected.enrollment === "previously_enrolled" ? ". Enrolling creates a new membership and retains the previous record." : ""}</p>
        </div>
      </div> : null}
      {error ? <p role="alert" className="text-sm text-destructive">{error}</p> : null}
      {feedback ? <p role="status" className="text-sm text-foreground">{feedback}</p> : null}
    </form>
  );
}
