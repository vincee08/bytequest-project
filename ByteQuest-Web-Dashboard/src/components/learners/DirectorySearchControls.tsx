"use client";

import React, { useEffect, useId, useRef, useState, useTransition } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Loader2, Search, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

export type DirectorySelect = {
  name: string;
  label: string;
  value: string;
  options: { value: string; label: string }[];
};

export const SEARCH_DEBOUNCE_MS = 350;

/** URL for the current form values: empty values and "all" selections are omitted, page resets. */
export function directoryHref(action: string, entries: Iterable<[string, string]>) {
  const query = new URLSearchParams();
  for (const [key, raw] of entries) {
    const value = raw.trim();
    if (value && !(key !== "q" && value === "all")) query.set(key, value);
  }
  const text = query.toString();
  return text ? `${action}?${text}` : action;
}

/**
 * Directory filters kept in the URL. Works as a plain GET form without
 * JavaScript; with JavaScript the search box is debounced and selects apply
 * immediately. Any change returns to page one.
 */
export function DirectorySearchControls({
  action,
  query,
  label,
  placeholder,
  selects,
  hidden = {},
  clearHref,
  filtered,
}: {
  action: string;
  query: string;
  label: string;
  placeholder: string;
  selects: DirectorySelect[];
  hidden?: Record<string, string>;
  clearHref: string;
  filtered: boolean;
}) {
  const router = useRouter();
  const id = useId();
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const selectKey = selects.map((select) => `${select.name}=${select.value}`).join("&");
  const [text, setText] = useState(query);
  const [chosen, setChosen] = useState<Record<string, string>>(() => Object.fromEntries(selects.map((select) => [select.name, select.value])));
  // What this component last navigated to; any other value came from outside
  // (Clear filters, back button) and replaces the local state.
  const applied = useRef({ query, selectKey });
  const [pending, startTransition] = useTransition();

  useEffect(() => {
    if (query !== applied.current.query) setText(query);
    if (selectKey !== applied.current.selectKey) setChosen(Object.fromEntries(selects.map((select) => [select.name, select.value])));
    applied.current = { query, selectKey };
    // selects is derived from selectKey
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [query, selectKey]);
  useEffect(() => () => { if (timer.current) clearTimeout(timer.current); }, []);

  function apply(nextText: string, nextChosen: Record<string, string>) {
    if (timer.current) clearTimeout(timer.current);
    const entries: [string, string][] = [["q", nextText], ...Object.entries(nextChosen), ...Object.entries(hidden)];
    applied.current = {
      query: nextText.trim(),
      selectKey: selects.map((select) => `${select.name}=${nextChosen[select.name] ?? select.value}`).join("&"),
    };
    const href = directoryHref(action, entries);
    startTransition(() => router.replace(href, { scroll: false }));
  }

  return (
    <form
      action={action}
      method="get"
      role="search"
      aria-label={label}
      className="rounded-xl border border-border bg-card p-4"
      onSubmit={(event) => { event.preventDefault(); apply(text, chosen); }}
    >
      {Object.entries(hidden).map(([name, hiddenValue]) => <input key={name} type="hidden" name={name} value={hiddenValue} />)}
      <div className="grid gap-3 md:grid-cols-[minmax(0,2fr)_repeat(auto-fit,minmax(10rem,1fr))] md:items-end">
        <div className="space-y-1.5">
          <Label htmlFor={`${id}-q`}>{label}</Label>
          <div className="relative">
            <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" aria-hidden="true" />
            <Input
              id={`${id}-q`}
              name="q"
              type="search"
              value={text}
              maxLength={100}
              autoComplete="off"
              placeholder={placeholder}
              className="min-h-11 pl-9"
              onChange={(event) => {
                const next = event.target.value;
                setText(next);
                if (timer.current) clearTimeout(timer.current);
                timer.current = setTimeout(() => apply(next, chosen), SEARCH_DEBOUNCE_MS);
              }}
            />
          </div>
        </div>
        {selects.map((select) => (
          <div key={select.name} className="space-y-1.5">
            <Label htmlFor={`${id}-${select.name}`}>{select.label}</Label>
            <select
              id={`${id}-${select.name}`}
              name={select.name}
              value={chosen[select.name] ?? select.value}
              onChange={(event) => {
                const next = { ...chosen, [select.name]: event.target.value };
                setChosen(next);
                apply(text, next);
              }}
              className="flex min-h-11 w-full rounded-lg border border-input bg-card px-3 text-sm shadow-xs focus-visible:border-primary/45 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/25"
            >
              {select.options.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
            </select>
          </div>
        ))}
      </div>
      <div className="mt-3 flex flex-wrap items-center gap-2">
        <Button type="submit" size="sm" className="min-h-11">
          <Search className="mr-2 h-4 w-4" aria-hidden="true" />Search
        </Button>
        {filtered ? (
          <Button asChild variant="ghost" size="sm" className="min-h-11">
            <Link href={clearHref} scroll={false}><X className="mr-2 h-4 w-4" aria-hidden="true" />Clear filters</Link>
          </Button>
        ) : null}
        <p className="flex items-center gap-2 text-xs text-muted-foreground" aria-live="polite">
          {pending ? <><Loader2 className="h-3.5 w-3.5 animate-spin" aria-hidden="true" />Updating results…</> : null}
        </p>
      </div>
    </form>
  );
}
