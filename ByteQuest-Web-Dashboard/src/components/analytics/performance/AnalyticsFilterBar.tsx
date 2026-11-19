"use client";

import type { ReactNode } from "react";
import { RotateCcw, SlidersHorizontal } from "lucide-react";
import { Button } from "@/components/ui/button";
import type { FilterOptions } from "@/lib/analytics/performance-types";
import {
  RANGE_LABELS,
  RANGE_PRESETS,
  activeFilterCount,
  analyticsHref,
  applyFilterChange,
  type AnalyticsFilterKey,
  type AnalyticsQuery,
  type RangePreset,
} from "@/lib/analytics/query";

const SELECT_CLASS =
  "h-10 w-full min-w-0 rounded-lg border border-input bg-card px-3 text-sm font-normal text-foreground shadow-xs transition-[border-color,box-shadow] duration-150 hover:border-primary/40 focus-visible:border-primary/50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/25 disabled:cursor-not-allowed disabled:opacity-60";

export function AnalyticsFilterBar({
  query,
  options,
  pathname,
  pending,
  navigate,
  hidden = [],
}: {
  query: AnalyticsQuery;
  options: FilterOptions;
  pathname: string;
  pending: boolean;
  navigate: (href: string) => void;
  hidden?: AnalyticsFilterKey[];
}) {
  const catalog = options;
  const show = (key: AnalyticsFilterKey) => !hidden.includes(key);
  const modules = options.modules.filter((item) => !query.cocCode || item.coc_code === query.cocCode);
  const topics = options.topics.filter((item) =>
    (!query.moduleId || item.module_id === query.moduleId) && (!query.cocCode || item.coc_code === query.cocCode));
  const missions = options.missions.filter((item) =>
    (!query.cocCode || item.coc_code === query.cocCode) && (!query.moduleId || item.module_id === query.moduleId));
  const quizzes = options.quizzes.filter((item) => !query.cocCode || !item.coc_code || item.coc_code === query.cocCode);
  const learners = options.learners.filter((item) => !query.classId || item.class_ids.includes(query.classId));

  function change(key: AnalyticsFilterKey, value: string) {
    navigate(analyticsHref(pathname, applyFilterChange(query, key, value || null, catalog)));
  }

  function changeRange(value: RangePreset) {
    navigate(analyticsHref(pathname, query, { range: value }));
  }

  function changeDate(boundary: "fromDate" | "toDate", value: string) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return;
    navigate(analyticsHref(pathname, query, { range: "custom", [boundary]: value }));
  }

  const filters = activeFilterCount(query);

  return (
    <section aria-label="Analytics filters" aria-busy={pending} className="print-hidden rounded-xl border border-border/85 bg-card p-4 shadow-xs">
      <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
        <p className="flex items-center gap-2 text-xs font-semibold text-foreground">
          <SlidersHorizontal className="h-4 w-4 text-primary" aria-hidden="true" />
          Filters
          <span className="font-normal text-muted-foreground">
            {filters ? `${filters} active · ` : ""}every tab and export uses these filters
          </span>
        </p>
        <Button type="button" variant="ghost" size="sm" className="h-9" disabled={pending || (filters === 0 && query.range === "30")}
          onClick={() => navigate(`${pathname}?tab=${query.tab}&range=30`)}>
          <RotateCcw className="mr-1.5 h-3.5 w-3.5" aria-hidden="true" />Clear filters
        </Button>
      </div>
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4 2xl:grid-cols-8">
        {show("classId") ? (
          <Field label="Class">
            <select className={SELECT_CLASS} value={query.classId ?? ""} disabled={pending} onChange={(event) => change("classId", event.target.value)}>
              <option value="">All classes ({options.classes.length})</option>
              {options.classes.map((item) => <option key={item.id} value={item.id}>{item.title}</option>)}
            </select>
          </Field>
        ) : null}
        {show("cocCode") ? (
          <Field label="COC">
            <select className={SELECT_CLASS} value={query.cocCode ?? ""} disabled={pending} onChange={(event) => change("cocCode", event.target.value)}>
              <option value="">All COCs</option>
              {options.cocs.map((item) => <option key={item.code} value={item.code}>{item.code.toUpperCase()} · {item.title}</option>)}
            </select>
          </Field>
        ) : null}
        {show("moduleId") ? (
          <Field label="Module">
            <select className={SELECT_CLASS} value={query.moduleId ?? ""} disabled={pending} onChange={(event) => change("moduleId", event.target.value)}>
              <option value="">All modules</option>
              {modules.map((item) => <option key={item.id} value={item.id}>{item.code} · {item.title}</option>)}
            </select>
          </Field>
        ) : null}
        {show("topicId") ? (
          <Field label="Topic">
            <select className={SELECT_CLASS} value={query.topicId ?? ""} disabled={pending || topics.length === 0} onChange={(event) => change("topicId", event.target.value)}>
              <option value="">{topics.length ? "All topics" : "No published topics"}</option>
              {topics.map((item) => <option key={item.id} value={item.id}>{item.title}</option>)}
            </select>
          </Field>
        ) : null}
        {show("missionCode") ? (
          <Field label="Mission">
            <select className={SELECT_CLASS} value={query.missionCode ?? ""} disabled={pending} onChange={(event) => change("missionCode", event.target.value)}>
              <option value="">All missions</option>
              {missions.map((item) => (
                <option key={item.mission_code} value={item.mission_code}>{item.coc_code.toUpperCase()} M{item.mission_number} · {item.title}</option>
              ))}
            </select>
          </Field>
        ) : null}
        {show("quizId") ? (
          <Field label="Quiz">
            <select className={SELECT_CLASS} value={query.quizId ?? ""} disabled={pending || quizzes.length === 0} onChange={(event) => change("quizId", event.target.value)}>
              <option value="">{quizzes.length ? "All quizzes" : "No published quizzes"}</option>
              {quizzes.map((item) => <option key={item.id} value={item.id}>{item.title}</option>)}
            </select>
          </Field>
        ) : null}
        {show("learnerId") ? (
          <Field label="Learner">
            <select className={SELECT_CLASS} value={query.learnerId ?? ""} disabled={pending || learners.length === 0} onChange={(event) => change("learnerId", event.target.value)}>
              <option value="">All learners ({learners.length})</option>
              {learners.map((item) => (
                <option key={item.id} value={item.id}>{item.name || "Unnamed learner"}{item.student_id ? ` · ${item.student_id}` : ""}</option>
              ))}
            </select>
          </Field>
        ) : null}
        <Field label="Period">
          <select className={SELECT_CLASS} value={query.range} disabled={pending} onChange={(event) => changeRange(event.target.value as RangePreset)}>
            {RANGE_PRESETS.map((value) => <option key={value} value={value}>{RANGE_LABELS[value]}</option>)}
          </select>
        </Field>
      </div>
      {query.range === "custom" ? (
        <div className="mt-3 grid gap-3 border-t border-border/70 pt-3 sm:grid-cols-2 lg:max-w-xl">
          <Field label="From (Manila date)">
            <input type="date" className={SELECT_CLASS} value={query.fromDate} max={query.toDate} disabled={pending}
              onChange={(event) => changeDate("fromDate", event.target.value)} />
          </Field>
          <Field label="To (Manila date)">
            <input type="date" className={SELECT_CLASS} value={query.toDate} min={query.fromDate} disabled={pending}
              onChange={(event) => changeDate("toDate", event.target.value)} />
          </Field>
          <p className="text-[11px] text-muted-foreground sm:col-span-2">Custom periods can cover at most 366 days.</p>
        </div>
      ) : null}
      <p className="sr-only" aria-live="polite">{pending ? "Updating analytics for the selected filters" : "Analytics up to date"}</p>
    </section>
  );
}

function Field({ label, children }: { label: string; children: ReactNode }) {
  return (
    <label className="grid min-w-0 gap-1.5 text-xs font-medium text-foreground">
      {label}
      {children}
    </label>
  );
}
