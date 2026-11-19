"use client";

import React, { useId, useRef, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { CheckCircle2, FileSpreadsheet, Loader2, RotateCcw, Upload } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { RosterOutcomePanel } from "@/components/roster/RosterOutcomePanel";
import {
  ROSTER_ACCEPT,
  ROSTER_MAX_ROWS,
  rosterFileProblem,
  rosterImportableCount,
  type RosterImportResponse,
  type RosterPreviewResponse,
} from "@/lib/roster/types";

type Stage =
  | { kind: "idle" }
  | { kind: "preview"; data: RosterPreviewResponse }
  | { kind: "result"; data: RosterImportResponse };

class RosterRequestError extends Error {}

async function postRoster<T>(url: string, body: FormData, fallback: string): Promise<T> {
  let response: Response;
  try {
    response = await fetch(url, { method: "POST", body, cache: "no-store", signal: AbortSignal.timeout(60_000) });
  } catch {
    throw new RosterRequestError(`${fallback} Check your connection and try again.`);
  }
  const data = await response.json().catch(() => null);
  if (!response.ok || !data) throw new RosterRequestError(data?.error ?? fallback);
  return data as T;
}

export function RosterImportWorkspace({ classId, classTitle }: { classId: string; classTitle: string }) {
  const router = useRouter();
  const inputId = useId();
  const fileRef = useRef<HTMLInputElement>(null);
  const busyRef = useRef(false);
  const [file, setFile] = useState<File | null>(null);
  const [stage, setStage] = useState<Stage>({ kind: "idle" });
  const [busy, setBusy] = useState<"preview" | "import" | null>(null);
  const [error, setError] = useState("");

  function reset() {
    setFile(null);
    setStage({ kind: "idle" });
    setError("");
    if (fileRef.current) fileRef.current.value = "";
    fileRef.current?.focus();
  }

  function chooseFile(next: File | null) {
    setFile(next);
    setStage({ kind: "idle" });
    setError(next ? rosterFileProblem(next) ?? "" : "");
  }

  async function preview() {
    const problem = rosterFileProblem(file);
    if (problem || !file) { setError(problem ?? ""); return; }
    if (busyRef.current) return;
    busyRef.current = true; setBusy("preview"); setError("");
    try {
      const body = new FormData();
      body.append("file", file);
      const data = await postRoster<RosterPreviewResponse>(`/api/roster/${classId}/preview`, body, "The roster preview could not be completed.");
      setStage({ kind: "preview", data });
    } catch (cause) {
      setStage({ kind: "idle" });
      setError(cause instanceof RosterRequestError ? cause.message : "The roster preview could not be completed.");
    } finally {
      busyRef.current = false; setBusy(null);
    }
  }

  async function confirmImport() {
    if (stage.kind !== "preview" || !file || busyRef.current) return;
    busyRef.current = true; setBusy("import"); setError("");
    try {
      const body = new FormData();
      body.append("file", file);
      body.append("expected_sha256", stage.data.file.sha256);
      const data = await postRoster<RosterImportResponse>(`/api/roster/${classId}/import`, body, "The import could not be confirmed. Nothing was changed.");
      setStage({ kind: "result", data });
      router.refresh();
    } catch (cause) {
      setError(cause instanceof RosterRequestError ? cause.message : "The import could not be confirmed. Refresh the class to check its learners before retrying.");
    } finally {
      busyRef.current = false; setBusy(null);
    }
  }

  const importable = stage.kind === "preview" ? rosterImportableCount(stage.data.preview.summary) : 0;

  return (
    <div className="space-y-6">
      <section className="rounded-xl border border-border bg-card p-5" aria-labelledby={`${inputId}-template`}>
        <h2 id={`${inputId}-template`} className="font-semibold">1. Get the roster template</h2>
        <p className="mb-4 mt-1 max-w-3xl text-sm leading-6 text-muted-foreground">
          Columns: <span className="font-mono text-xs">student_id, last_name, first_name, email, course_section</span>. Last name, first name and email are required.
          The example row is ignored. Headers such as &ldquo;Student ID&rdquo; or &ldquo;E-mail&rdquo; are also recognised, and extra columns are ignored.
        </p>
        <Button asChild variant="outline" className="min-h-11">
          <a href="/api/roster/template" download="bytequest-roster-template.xlsx">
            <FileSpreadsheet className="mr-2 h-4 w-4" aria-hidden="true" />Download template (.xlsx)
          </a>
        </Button>
      </section>

      <section className="rounded-xl border border-border bg-card p-5" aria-labelledby={`${inputId}-upload`}>
        <h2 id={`${inputId}-upload`} className="font-semibold">2. Upload and preview</h2>
        <p className="mb-4 mt-1 max-w-3xl text-sm leading-6 text-muted-foreground">
          Excel .xlsx or .xls, up to 2 MB and {ROSTER_MAX_ROWS.toLocaleString("en-US")} learners. The file is checked on the server and nothing changes in {classTitle} until you confirm.
        </p>
        <div className="flex flex-col gap-3 sm:flex-row sm:items-end">
          <div className="min-w-0 flex-1 space-y-2">
            <Label htmlFor={inputId}>Roster file</Label>
            <Input
              ref={fileRef}
              id={inputId}
              type="file"
              accept={ROSTER_ACCEPT}
              className="min-h-11 cursor-pointer"
              disabled={busy !== null}
              aria-describedby={error ? `${inputId}-error` : undefined}
              onChange={(event) => chooseFile(event.target.files?.[0] ?? null)}
            />
          </div>
          <Button type="button" className="min-h-11" onClick={preview} disabled={!file || busy !== null || Boolean(rosterFileProblem(file))}>
            {busy === "preview" ? <Loader2 className="mr-2 h-4 w-4 animate-spin" aria-hidden="true" /> : <Upload className="mr-2 h-4 w-4" aria-hidden="true" />}
            {busy === "preview" ? "Checking file…" : "Preview roster"}
          </Button>
        </div>
        {error ? <p id={`${inputId}-error`} role="alert" className="mt-3 text-sm text-destructive">{error}</p> : null}
        <p className="sr-only" aria-live="polite">
          {busy === "preview" ? "Checking the roster file." : busy === "import" ? "Importing the roster." : stage.kind === "preview" ? "Preview ready." : stage.kind === "result" ? "Import complete." : ""}
        </p>
      </section>

      {stage.kind === "preview" ? (
        <section className="space-y-5 rounded-xl border border-border bg-card p-5" aria-labelledby={`${inputId}-preview`}>
          <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
            <div>
              <h2 id={`${inputId}-preview`} className="font-semibold">3. Review the preview</h2>
              <p className="mt-1 break-all text-sm text-muted-foreground">{stage.data.file.name}</p>
            </div>
            <div className="flex flex-wrap gap-2">
              <Button type="button" variant="outline" className="min-h-11" onClick={reset} disabled={busy !== null}>
                <RotateCcw className="mr-2 h-4 w-4" aria-hidden="true" />Choose another file
              </Button>
              <Button type="button" className="min-h-11" onClick={confirmImport} disabled={busy !== null || importable === 0}>
                {busy === "import" ? <Loader2 className="mr-2 h-4 w-4 animate-spin" aria-hidden="true" /> : <CheckCircle2 className="mr-2 h-4 w-4" aria-hidden="true" />}
                {busy === "import" ? "Importing…" : `Confirm import (${stage.data.preview.summary.enroll_now} enroll now, ${stage.data.preview.summary.pending} pending)`}
              </Button>
            </div>
          </div>
          <RosterOutcomePanel outcome={stage.data.preview} file={stage.data.file} mode="preview" />
        </section>
      ) : null}

      {stage.kind === "result" ? (
        <section className="space-y-5 rounded-xl border border-emerald-200 bg-card p-5" aria-labelledby={`${inputId}-result`}>
          <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
            <div role="status">
              <h2 id={`${inputId}-result`} className="flex items-center gap-2 font-semibold text-emerald-900">
                <CheckCircle2 className="h-5 w-5" aria-hidden="true" />Import complete
              </h2>
              <p className="mt-1 text-sm text-muted-foreground">
                {stage.data.result.summary.enroll_now} enrolled now · {stage.data.result.summary.pending} pending sign-up ·{" "}
                {stage.data.result.summary.already_enrolled + stage.data.result.summary.conflict_student_id + stage.data.result.summary.staff_account} skipped ·{" "}
                {stage.data.result.summary.invalid} invalid (not imported)
              </p>
            </div>
            <div className="flex flex-wrap gap-2">
              <Button asChild variant="outline" className="min-h-11"><Link href={`/classes/${classId}?tab=learners`}>Back to class learners</Link></Button>
              <Button type="button" className="min-h-11" onClick={reset}><RotateCcw className="mr-2 h-4 w-4" aria-hidden="true" />Import another file</Button>
            </div>
          </div>
          <RosterOutcomePanel outcome={stage.data.result} file={stage.data.file} mode="result" />
        </section>
      ) : null}
    </div>
  );
}
