import React, { type ReactNode } from "react";
import Link from "next/link";
import { ArrowDown, ArrowUp, ArrowUpDown, Lock, Search, Users } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { SearchPagination } from "@/components/learners/SearchPagination";
import {
  learnerSearchHref,
  learnerSortHref,
  pageWindow,
  type LearnerSearchFilters,
  type LearnerSearchResult,
  type LearnerSearchRow,
  type LearnerSortKey,
} from "@/lib/learners/search";

const dateFormat = new Intl.DateTimeFormat("en-PH", { dateStyle: "medium", timeZone: "Asia/Manila" });
const formatDate = (value: string | null) => (value ? dateFormat.format(new Date(value)) : "No activity yet");

function SortHeader({ basePath, filters, column, children }: { basePath: string; filters: LearnerSearchFilters; column: LearnerSortKey; children: ReactNode }) {
  const active = filters.sort === column;
  const Icon = !active ? ArrowUpDown : filters.direction === "asc" ? ArrowUp : ArrowDown;
  return (
    <th scope="col" aria-sort={active ? (filters.direction === "asc" ? "ascending" : "descending") : "none"} className="px-3 py-2.5 font-medium first:pl-5">
      <Link href={learnerSortHref(basePath, filters, column)} scroll={false} className="inline-flex min-h-8 items-center gap-1 rounded hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
        {children}<Icon className={`h-3.5 w-3.5 ${active ? "text-primary" : "opacity-50"}`} aria-hidden="true" />
        <span className="sr-only">{active ? `, sorted ${filters.direction === "asc" ? "ascending" : "descending"}. Activate to reverse.` : ", activate to sort"}</span>
      </Link>
    </th>
  );
}

/** Inline error state for a directory request; nothing was changed. */
export function DirectoryError({ message, retryHref }: { message: string; retryHref: string }) {
  return (
    <section role="alert" className="rounded-xl border border-destructive/25 bg-card px-5 py-10 text-center">
      <p className="text-sm font-semibold text-foreground">{message}</p>
      <p className="mt-1 text-sm text-muted-foreground">No learner or account data was changed.</p>
      <Link href={retryHref} className="mt-4 inline-flex min-h-11 items-center rounded-lg border border-border px-4 text-sm font-semibold hover:border-primary/30 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">Try again</Link>
    </section>
  );
}

/**
 * Server-rendered learner search results: sortable headers, account and class
 * columns, an optional extra column, empty and past-the-end states, pagination.
 */
export function LearnerDirectoryTable({
  basePath,
  filters,
  result,
  rowHref,
  extra,
  showCreated = false,
  emptyTitle,
  emptyText,
}: {
  basePath: string;
  filters: LearnerSearchFilters;
  result: LearnerSearchResult;
  rowHref: (row: LearnerSearchRow) => string;
  extra?: { header: string; render: (row: LearnerSearchRow) => ReactNode };
  showCreated?: boolean;
  emptyTitle: string;
  emptyText: string;
}) {
  const filtered = Boolean(filters.q || filters.classId || filters.status !== "all");
  const { from, to } = pageWindow(result.total, filters.page);
  const pastEnd = result.total > 0 && result.rows.length === 0 && from > to;

  return (
    <section className="overflow-hidden rounded-xl border border-border bg-card" aria-label="Learner results">
      {result.rows.length ? (
        <div className="relative overflow-x-auto">
          <table className="w-full min-w-[880px] text-left text-sm">
            <thead className="bg-muted/45 text-xs text-muted-foreground">
              <tr>
                <SortHeader basePath={basePath} filters={filters} column="name">Learner</SortHeader>
                <SortHeader basePath={basePath} filters={filters} column="student_id">Student ID</SortHeader>
                <th scope="col" className="px-3 py-2.5 font-medium">Classes</th>
                <th scope="col" className="px-3 py-2.5 font-medium">Account</th>
                <SortHeader basePath={basePath} filters={filters} column="last_activity">Last activity</SortHeader>
                {showCreated ? <SortHeader basePath={basePath} filters={filters} column="created">Joined</SortHeader> : null}
                {extra ? <th scope="col" className="px-5 py-2.5 font-medium">{extra.header}</th> : null}
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {result.rows.map((row) => (
                <tr key={row.user_id} className="align-top transition-colors hover:bg-muted/25">
                  <td className="px-5 py-3">
                    <Link href={rowHref(row)} className="font-semibold text-foreground hover:text-primary focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">{row.full_name || "Learner"}</Link>
                    <p className="mt-0.5 break-all text-xs text-muted-foreground">{row.email}</p>
                  </td>
                  <td className="px-3 py-3">
                    {row.learner_id ? (
                      <span className="inline-flex items-center gap-1 font-mono text-xs">
                        {row.learner_id}
                        {row.learner_id_managed ? <><Lock className="h-3 w-3 text-muted-foreground" aria-hidden="true" /><span className="sr-only">(staff-managed)</span></> : null}
                      </span>
                    ) : <span className="text-xs text-muted-foreground">Not set</span>}
                  </td>
                  <td className="px-3 py-3 text-xs">
                    {row.classes.length ? <ul className="space-y-0.5">{row.classes.map((item) => <li key={item.id}>{item.title}</li>)}</ul> : <span className="text-muted-foreground">No active class</span>}
                  </td>
                  <td className="px-3 py-3"><Badge variant={row.status === "active" ? "secondary" : "outline"}>{row.status}</Badge></td>
                  <td className="px-3 py-3 text-xs text-muted-foreground">{formatDate(row.last_activity_at)}</td>
                  {showCreated ? <td className="px-3 py-3 text-xs text-muted-foreground">{formatDate(row.created_at)}</td> : null}
                  {extra ? <td className="px-5 py-3">{extra.render(row)}</td> : null}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : (
        <div className="px-5 py-14 text-center" role="status">
          {pastEnd ? <Search className="mx-auto h-7 w-7 text-muted-foreground" aria-hidden="true" /> : <Users className="mx-auto h-7 w-7 text-muted-foreground" aria-hidden="true" />}
          <p className="mt-3 text-sm font-semibold">{pastEnd ? "This page is past the last result." : filtered ? "No learners match these filters." : emptyTitle}</p>
          <p className="mx-auto mt-1 max-w-md text-sm text-muted-foreground">{pastEnd ? "Go back to the first page of results." : filtered ? "Try a different name, email, student ID or class, or clear the filters." : emptyText}</p>
          {pastEnd || filtered ? (
            <Link href={pastEnd ? learnerSearchHref(basePath, filters, { page: 1 }) : basePath} scroll={false} className="mt-4 inline-flex min-h-11 items-center rounded-lg border border-border px-4 text-sm font-semibold hover:border-primary/30 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
              {pastEnd ? "First page" : "Clear filters"}
            </Link>
          ) : null}
        </div>
      )}
      <SearchPagination total={result.total} page={filters.page} hrefFor={(page) => learnerSearchHref(basePath, filters, { page })} />
    </section>
  );
}
