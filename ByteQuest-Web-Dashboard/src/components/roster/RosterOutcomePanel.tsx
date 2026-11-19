import React from "react";
import { AlertTriangle, CheckCircle2, Clock3, Download, SkipForward, UserPlus } from "lucide-react";
import type { LucideIcon } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import {
  rosterAppliedLabels,
  rosterErrorReportCsv,
  rosterGroupRows,
  rosterImportableCount,
  rosterProblemRows,
  rosterStatusLabels,
  type RosterFileInfo,
  type RosterGroupKey,
  type RosterOutcome,
  type RosterRowStatus,
} from "@/lib/roster/types";

const groupStyle: Record<RosterGroupKey, { icon: LucideIcon; tone: string }> = {
  enroll_now: { icon: UserPlus, tone: "border-emerald-200 bg-emerald-50 text-emerald-900" },
  pending: { icon: Clock3, tone: "border-primary/20 bg-primary/[0.06] text-primary" },
  skip: { icon: SkipForward, tone: "border-border bg-muted/40 text-foreground" },
  invalid: { icon: AlertTriangle, tone: "border-red-200 bg-red-50 text-red-900" },
};

function statusVariant(status: RosterRowStatus): "default" | "secondary" | "outline" | "destructive" {
  if (status === "enroll_now") return "secondary";
  if (status === "pending") return "default";
  if (status === "invalid") return "destructive";
  return "outline";
}

export function rosterErrorReportHref(outcome: RosterOutcome) {
  // A UTF-8 BOM keeps accented names readable when the report opens in Excel.
  return `data:text/csv;charset=utf-8,${encodeURIComponent(`﻿${rosterErrorReportCsv(outcome.rows)}`)}`;
}

/** Summary counts, file details and the grouped per-row table for a preview or an applied import. */
export function RosterOutcomePanel({
  outcome,
  file,
  mode,
}: {
  outcome: RosterOutcome;
  file: RosterFileInfo;
  mode: "preview" | "result";
}) {
  const groups = rosterGroupRows(outcome.rows);
  const problems = rosterProblemRows(outcome.rows);
  const labels = mode === "result" ? rosterAppliedLabels : rosterStatusLabels;
  const reportName = `roster-errors-${(file.name.replace(/\.[^.]+$/, "") || "import").replace(/[^a-z0-9._-]+/gi, "-").slice(0, 60)}.csv`;
  const details = [
    `Sheet "${file.sheetName}", headers on row ${file.headerRow}`,
    `${outcome.summary.total} learner row${outcome.summary.total === 1 ? "" : "s"} read`,
    file.blankRowsSkipped ? `${file.blankRowsSkipped} blank row${file.blankRowsSkipped === 1 ? "" : "s"} skipped` : null,
    file.exampleRowsSkipped ? `${file.exampleRowsSkipped} example row${file.exampleRowsSkipped === 1 ? "" : "s"} ignored` : null,
    file.ignoredColumns.length ? `Ignored columns: ${file.ignoredColumns.join(", ")}` : null,
  ].filter(Boolean);

  return (
    <div className="space-y-5">
      <p className="text-xs leading-5 text-muted-foreground">{details.join(" · ")}</p>

      <ul className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4" aria-label={mode === "result" ? "Import summary" : "Preview summary"}>
        {groups.map((group) => {
          const { icon: Icon, tone } = groupStyle[group.key];
          return (
            <li key={group.key} className={`rounded-xl border p-4 ${tone}`}>
              <div className="flex items-center justify-between gap-3">
                <span className="text-sm font-semibold">{mode === "result" && group.key === "enroll_now" ? "Enrolled" : group.title}</span>
                <Icon className="h-4 w-4 shrink-0" aria-hidden="true" />
              </div>
              <p className="mt-2 text-2xl font-bold tabular-nums" data-testid={`roster-count-${group.key}`}>{group.rows.length}</p>
              <p className="mt-1 text-[11px] leading-4 opacity-80">{group.description}</p>
            </li>
          );
        })}
      </ul>

      {problems.length ? (
        <a
          href={rosterErrorReportHref(outcome)}
          download={reportName}
          className="inline-flex min-h-11 items-center gap-2 rounded-lg border border-border bg-card px-4 text-sm font-semibold hover:border-primary/30 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
        >
          <Download className="h-4 w-4" aria-hidden="true" />
          Download error report (CSV, {problems.length} row{problems.length === 1 ? "" : "s"})
        </a>
      ) : (
        <p className="flex items-center gap-2 text-sm text-emerald-800"><CheckCircle2 className="h-4 w-4" aria-hidden="true" />No invalid or conflicting rows.</p>
      )}

      {groups.filter((group) => group.rows.length).map((group) => (
        <section key={group.key} className="overflow-hidden rounded-xl border border-border bg-card" aria-labelledby={`roster-group-${group.key}`}>
          <div className="flex flex-wrap items-center justify-between gap-2 border-b border-border px-4 py-3">
            <h3 id={`roster-group-${group.key}`} className="text-sm font-semibold">
              {mode === "result" && group.key === "enroll_now" ? "Enrolled" : group.title} <span className="tabular-nums text-muted-foreground">({group.rows.length})</span>
            </h3>
            <p className="text-xs text-muted-foreground">{group.description}</p>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full min-w-[860px] text-left text-sm">
              <thead className="bg-muted/45 text-xs text-muted-foreground">
                <tr>
                  <th scope="col" className="px-4 py-2.5 font-medium">Row</th>
                  <th scope="col" className="px-3 py-2.5 font-medium">Student ID</th>
                  <th scope="col" className="px-3 py-2.5 font-medium">Learner</th>
                  <th scope="col" className="px-3 py-2.5 font-medium">Email</th>
                  <th scope="col" className="px-3 py-2.5 font-medium">Course / section</th>
                  <th scope="col" className="px-3 py-2.5 font-medium">Status</th>
                  <th scope="col" className="px-4 py-2.5 font-medium">Details</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border">
                {group.rows.map((row) => (
                  <tr key={`${row.row_number}-${row.email ?? ""}`} className="align-top">
                    <td className="px-4 py-2.5 tabular-nums text-muted-foreground">{row.row_number}</td>
                    <td className="px-3 py-2.5 font-mono text-xs">{row.student_id || "—"}</td>
                    <td className="px-3 py-2.5">
                      <span className="font-medium">{[row.last_name, row.first_name].filter(Boolean).join(", ") || "—"}</span>
                      {row.learner_name ? <span className="mt-0.5 block text-xs text-muted-foreground">Account: {row.learner_name}</span> : null}
                    </td>
                    <td className="break-all px-3 py-2.5 text-xs">{row.email || "—"}</td>
                    <td className="px-3 py-2.5 text-xs">{row.course_section || "—"}</td>
                    <td className="px-3 py-2.5"><Badge variant={statusVariant(row.status)}>{labels[row.status]}</Badge></td>
                    <td className="px-4 py-2.5 text-xs leading-5 text-muted-foreground">
                      {row.message}
                      {row.student_id_assigned ? <span className="mt-0.5 block text-emerald-800">Student ID set on the learner profile.</span> : null}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      ))}

      {mode === "preview" && rosterImportableCount(outcome.summary) === 0 ? (
        <p role="status" className="rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-950">
          Nothing in this file can be imported. Fix the rows listed above, save the workbook and preview it again.
        </p>
      ) : null}
    </div>
  );
}
