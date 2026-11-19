import React from "react";
import Link from "next/link";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { pageWindow } from "@/lib/learners/search";

/** "Showing x–y of n" with previous/next links; disabled ends are not links. */
export function SearchPagination({ total, page, hrefFor, noun = "learners" }: { total: number; page: number; hrefFor: (page: number) => string; noun?: string }) {
  const { from, to, pages } = pageWindow(total, page);
  const linkClass = "inline-flex min-h-11 items-center gap-1 rounded-lg border border-border bg-card px-3 text-sm font-semibold hover:border-primary/30 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring";
  const disabledClass = "inline-flex min-h-11 items-center gap-1 rounded-lg border border-border/60 px-3 text-sm font-semibold text-muted-foreground/60";
  return (
    <nav aria-label={`${noun} pages`} className="flex flex-col gap-3 border-t border-border px-5 py-3 sm:flex-row sm:items-center sm:justify-between">
      <p className="text-xs text-muted-foreground" aria-live="polite">
        {total === 0 ? `No ${noun}` : from > to ? `Page ${page} is past the last result` : `Showing ${from}–${to} of ${total} ${noun}`} · Page {Math.min(page, pages)} of {pages}
      </p>
      <div className="flex gap-2">
        {page > 1 ? <Link href={hrefFor(Math.min(page - 1, pages))} scroll={false} className={linkClass}><ChevronLeft className="h-4 w-4" aria-hidden="true" />Previous</Link>
          : <span aria-disabled="true" className={disabledClass}><ChevronLeft className="h-4 w-4" aria-hidden="true" />Previous</span>}
        {page < pages ? <Link href={hrefFor(page + 1)} scroll={false} className={linkClass}>Next<ChevronRight className="h-4 w-4" aria-hidden="true" /></Link>
          : <span aria-disabled="true" className={disabledClass}>Next<ChevronRight className="h-4 w-4" aria-hidden="true" /></span>}
      </div>
    </nav>
  );
}
