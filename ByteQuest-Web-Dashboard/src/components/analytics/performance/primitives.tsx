"use client";

import type { ReactNode } from "react";
import { CircleDashed, Link2Off } from "lucide-react";
import { SectionHeading } from "@/components/dashboard/SectionHeading";
import { statusPresentation } from "@/lib/analytics/format";
import type { LearnerStatus } from "@/lib/analytics/performance-types";
import { cn } from "@/lib/utils";

export function Panel({
  id,
  title,
  description,
  action,
  children,
  className,
}: {
  id?: string;
  title: string;
  description?: string;
  action?: ReactNode;
  children: ReactNode;
  className?: string;
}) {
  return (
    <section id={id} aria-label={title} className={cn("overflow-hidden rounded-xl border border-border bg-card", className)}>
      <SectionHeading title={title} description={description} action={action} />
      {children}
    </section>
  );
}

export function EmptyState({ title, description }: { title: string; description?: string }) {
  return (
    <div className="px-5 py-12 text-center" role="status">
      <CircleDashed className="mx-auto h-6 w-6 text-muted-foreground" aria-hidden="true" />
      <p className="mt-3 text-sm font-medium text-foreground">{title}</p>
      {description ? <p className="mx-auto mt-1 max-w-xl text-sm text-muted-foreground">{description}</p> : null}
    </div>
  );
}

/** A source that cannot be positioned on the selected curriculum filter. */
export function NotApplicable({ source }: { source: string }) {
  return (
    <div className="flex items-start gap-3 px-5 py-6 text-sm text-muted-foreground" role="note">
      <Link2Off className="mt-0.5 h-4 w-4 shrink-0" aria-hidden="true" />
      <p>{source} are not linked to the selected curriculum filter, so they are excluded instead of being mixed in.</p>
    </div>
  );
}

export function StatusBadge({ status }: { status: LearnerStatus }) {
  const presentation = statusPresentation(status);
  return (
    <span
      className={cn("inline-flex min-h-7 items-center rounded-md border px-2.5 text-xs font-semibold", presentation.badgeClassName)}
      title={presentation.description}
    >
      {presentation.label}
    </span>
  );
}

export type Column<T> = {
  key: string;
  label: string;
  align?: "left" | "right";
  render: (row: T) => ReactNode;
  className?: string;
};

export function DataTable<T>({
  caption,
  columns,
  rows,
  rowKey,
  minWidth = 720,
  emptyTitle = "No rows match these filters.",
}: {
  caption: string;
  columns: Column<T>[];
  rows: T[];
  rowKey: (row: T, index: number) => string;
  minWidth?: number;
  emptyTitle?: string;
}) {
  if (!rows.length) return <EmptyState title={emptyTitle} />;
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-left text-sm" style={{ minWidth }}>
        <caption className="sr-only">{caption}</caption>
        <thead className="bg-muted/45 text-xs text-muted-foreground">
          <tr>
            {columns.map((column) => (
              <th key={column.key} scope="col" className={cn("px-4 py-3 font-medium first:pl-5 last:pr-5", column.align === "right" && "text-right")}>
                {column.label}
              </th>
            ))}
          </tr>
        </thead>
        <tbody className="divide-y divide-border">
          {rows.map((row, index) => (
            <tr key={rowKey(row, index)} className="align-top transition-colors duration-150 hover:bg-muted/30">
              {columns.map((column) => (
                <td key={column.key} className={cn("px-4 py-3 first:pl-5 last:pr-5", column.align === "right" && "text-right tabular-nums", column.className)}>
                  {column.render(row)}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export function Stat({ label, value, helper }: { label: string; value: ReactNode; helper?: string }) {
  return (
    <div className="min-w-0 rounded-lg border border-border/70 bg-background px-3.5 py-3">
      <p className="text-[11px] font-semibold uppercase tracking-[0.04em] text-muted-foreground">{label}</p>
      <p className="mt-1 text-lg font-bold tabular-nums tracking-tight text-foreground">{value}</p>
      {helper ? <p className="mt-0.5 text-[11px] leading-4 text-muted-foreground">{helper}</p> : null}
    </div>
  );
}
