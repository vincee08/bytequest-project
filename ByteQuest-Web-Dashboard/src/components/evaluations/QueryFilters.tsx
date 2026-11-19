"use client";

import { useState, useTransition } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { Filter, RotateCcw } from "lucide-react";
import { Button } from "@/components/ui/button";

export type FilterOption = { value: string; label: string; parent?: string };
export type FilterSelect = {
  name: string;
  label: string;
  allLabel: string;
  value: string;
  options: FilterOption[];
  /** Only options whose `parent` matches this select's current value are offered. */
  parentName?: string;
};
export type FilterToggle = { name: string; label: string; checked: boolean };

/** URL-driven filters: Apply pushes ?name=value, so every view is a deep link. */
export function QueryFilters({
  selects,
  toggles = [],
  keep = [],
  ariaLabel,
}: {
  selects: FilterSelect[];
  toggles?: FilterToggle[];
  keep?: string[];
  ariaLabel: string;
}) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const [pending, startTransition] = useTransition();
  const [values, setValues] = useState<Record<string, string>>(
    Object.fromEntries(selects.map((select) => [select.name, select.value])),
  );
  const [checked, setChecked] = useState<Record<string, boolean>>(
    Object.fromEntries(toggles.map((toggle) => [toggle.name, toggle.checked])),
  );

  const visibleOptions = (select: FilterSelect) =>
    select.parentName && values[select.parentName]
      ? select.options.filter((option) => !option.parent || option.parent === values[select.parentName!])
      : select.options;

  const change = (name: string, value: string) => {
    setValues((current) => {
      const next = { ...current, [name]: value };
      // Clear dependent selections that no longer belong to the new parent.
      for (const select of selects) {
        if (select.parentName === name && next[select.name]) {
          const option = select.options.find((item) => item.value === next[select.name]);
          if (value && option?.parent && option.parent !== value) next[select.name] = "";
        }
      }
      return next;
    });
  };

  const apply = () => {
    const next = new URLSearchParams();
    for (const key of keep) {
      const value = searchParams.get(key);
      if (value) next.set(key, value);
    }
    for (const [name, value] of Object.entries(values)) if (value) next.set(name, value);
    for (const [name, value] of Object.entries(checked)) if (value) next.set(name, "1");
    startTransition(() => router.push(next.toString() ? `${pathname}?${next.toString()}` : pathname));
  };

  const clear = () => {
    const next = new URLSearchParams();
    for (const key of keep) {
      const value = searchParams.get(key);
      if (value) next.set(key, value);
    }
    setValues(Object.fromEntries(selects.map((select) => [select.name, ""])));
    setChecked(Object.fromEntries(toggles.map((toggle) => [toggle.name, false])));
    startTransition(() => router.push(next.toString() ? `${pathname}?${next.toString()}` : pathname));
  };

  return (
    <form
      onSubmit={(event) => { event.preventDefault(); apply(); }}
      className="rounded-xl border border-border/85 bg-card p-4 shadow-xs"
      aria-label={ariaLabel}
      aria-busy={pending}
    >
      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-[repeat(auto-fit,minmax(170px,1fr))] xl:items-end">
        {selects.map((select) => (
          <label key={select.name} className="grid min-w-0 gap-1.5 text-xs font-medium text-foreground">
            {select.label}
            <select
              name={select.name}
              value={values[select.name] ?? ""}
              onChange={(event) => change(select.name, event.target.value)}
              className="h-11 min-w-0 rounded-lg border border-input bg-card px-3 text-sm font-normal text-foreground shadow-xs transition-[border-color,box-shadow] duration-150 hover:border-primary/40 focus-visible:border-primary/50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/25"
            >
              <option value="">{select.allLabel}</option>
              {visibleOptions(select).map((option) => (
                <option key={option.value} value={option.value}>{option.label}</option>
              ))}
            </select>
          </label>
        ))}
        {toggles.map((toggle) => (
          <label key={toggle.name} className="flex min-h-11 items-center gap-2 text-sm font-medium">
            <input
              type="checkbox"
              name={toggle.name}
              checked={checked[toggle.name] ?? false}
              onChange={(event) => setChecked((current) => ({ ...current, [toggle.name]: event.target.checked }))}
              className="h-5 w-5 rounded border-input accent-primary"
            />
            {toggle.label}
          </label>
        ))}
        <div className="flex items-center gap-2">
          <Button type="submit" disabled={pending} className="min-h-11 flex-1 xl:flex-none">
            <Filter className="mr-2 h-4 w-4" aria-hidden="true" />
            {pending ? "Applying…" : "Apply filters"}
          </Button>
          <Button type="button" variant="ghost" size="icon" className="h-11 w-11" onClick={clear} disabled={pending} aria-label="Clear filters">
            <RotateCcw className="h-4 w-4" aria-hidden="true" />
          </Button>
        </div>
      </div>
      <p className="sr-only" aria-live="polite">{pending ? "Applying filters" : ""}</p>
    </form>
  );
}
