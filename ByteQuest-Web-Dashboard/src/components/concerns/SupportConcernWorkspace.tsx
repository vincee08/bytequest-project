"use client";

import { useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { createClient } from "@/lib/supabase/client";
import type { Database, Json } from "@/types/database.generated";

type Concern = Database["public"]["Tables"]["support_concerns"]["Row"];
type Scope = "training" | "system";
type Status = "open" | "in_progress" | "resolved";

function formatDate(value: string) {
  return new Intl.DateTimeFormat("en-PH", { dateStyle: "medium", timeStyle: "short" }).format(new Date(value));
}

function historyEntries(history: Json): { event: string; actor_role: string; at: string; reason?: string }[] {
  if (!Array.isArray(history)) return [];
  return history.flatMap((value) => {
    if (value === null || typeof value !== "object" || Array.isArray(value)) return [];
    if (typeof value.event !== "string" || typeof value.actor_role !== "string" || typeof value.at !== "string") return [];
    return [{ event: value.event, actor_role: value.actor_role, at: value.at, reason: typeof value.reason === "string" ? value.reason : undefined }];
  });
}

function ConcernCard({ concern, canManage, classTitle }: { concern: Concern; canManage: boolean; classTitle?: string }) {
  const router = useRouter();
  const [nextStatus, setNextStatus] = useState<Status>(concern.status as Status);
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const history = historyEntries(concern.history);

  const changeStatus = async (event: FormEvent) => {
    event.preventDefault();
    if (nextStatus === concern.status || reason.trim().length < 5) {
      toast.error("Choose a different status and provide a clear reason of at least five characters.");
      return;
    }
    setBusy(true);
    try {
      const { error } = await createClient()
        .from("support_concerns")
        .update({ status: nextStatus, status_reason: reason.trim() })
        .eq("id", concern.id)
        .select("id")
        .single();
      if (error) throw error;
      toast.success("Concern status and audit history updated.");
      setReason("");
      router.refresh();
    } catch {
      toast.error("The concern could not be updated. Check your role and try again.");
    } finally {
      setBusy(false);
    }
  };

  return <article className="rounded-xl border border-border bg-card p-4 sm:p-5">
    <div className="flex flex-wrap items-start justify-between gap-3">
      <div className="min-w-0">
        <h3 className="font-semibold text-foreground">{concern.title}</h3>
        <p className="mt-1 text-xs text-muted-foreground">
          {classTitle ? `${classTitle} · ` : ""}Opened {formatDate(concern.created_at)}
        </p>
      </div>
      <Badge variant={concern.status === "resolved" ? "secondary" : "outline"}>
        {concern.status.replaceAll("_", " ")}
      </Badge>
    </div>
    <p className="mt-3 whitespace-pre-wrap text-sm leading-6 text-foreground/85">{concern.details}</p>
    {canManage ? <form onSubmit={changeStatus} className="mt-4 grid gap-3 border-t border-border pt-4 sm:grid-cols-[12rem_minmax(0,1fr)_auto] sm:items-end">
      <div className="space-y-1"><Label htmlFor={`status-${concern.id}`}>New status</Label>
        <Select value={nextStatus} onValueChange={(value) => setNextStatus(value as Status)}>
          <SelectTrigger id={`status-${concern.id}`}><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value="open">Open</SelectItem>
            <SelectItem value="in_progress">In progress</SelectItem>
            <SelectItem value="resolved">Resolved</SelectItem>
          </SelectContent>
        </Select>
      </div>
      <div className="space-y-1"><Label htmlFor={`reason-${concern.id}`}>Reason for status change</Label>
        <Input id={`reason-${concern.id}`} value={reason} onChange={(event) => setReason(event.target.value)} maxLength={500} placeholder="What changed?" />
      </div>
      <Button type="submit" disabled={busy || nextStatus === concern.status || reason.trim().length < 5} className="min-h-11">{busy ? "Saving…" : "Update"}</Button>
    </form> : null}
    <details className="mt-4 border-t border-border pt-3 text-xs text-muted-foreground">
      <summary className="cursor-pointer font-medium text-foreground">Status history ({history.length})</summary>
      <ol className="mt-2 space-y-2">
        {history.map((entry, index) => <li key={`${entry.at}-${index}`}>
          {formatDate(entry.at)} · {entry.actor_role} · {entry.event.replaceAll("_", " ")}{entry.reason ? ` — ${entry.reason}` : ""}
        </li>)}
      </ol>
    </details>
  </article>;
}

export function SupportConcernWorkspace({ scope, concerns, classes = [], oversight = [] }: {
  scope: Scope;
  concerns: Concern[];
  classes?: { id: string; title: string }[];
  oversight?: Concern[];
}) {
  const router = useRouter();
  const [classId, setClassId] = useState(classes[0]?.id ?? "");
  const [title, setTitle] = useState("");
  const [details, setDetails] = useState("");
  const [busy, setBusy] = useState(false);
  const classById = new Map(classes.map((classroom) => [classroom.id, classroom.title]));
  const canOpen = scope === "system" || classes.length > 0;

  const openConcern = async (event: FormEvent) => {
    event.preventDefault();
    if (!canOpen || (scope === "training" && !classId) || title.trim().length < 5 || details.trim().length < 10) {
      toast.error("Choose a class and enter a title and description with enough detail.");
      return;
    }
    setBusy(true);
    try {
      const { error } = await createClient()
        .from("support_concerns")
        .insert({ scope, class_id: scope === "training" ? classId : null, title: title.trim(), details: details.trim() })
        .select("id")
        .single();
      if (error) throw error;
      setTitle("");
      setDetails("");
      toast.success(scope === "training" ? "Training concern recorded." : "System incident recorded.");
      router.refresh();
    } catch {
      toast.error("The concern could not be recorded. Check your scope and try again.");
    } finally {
      setBusy(false);
    }
  };

  return <div className="space-y-6">
    <section className="rounded-xl border border-border bg-card p-4 sm:p-5">
      <h2 className="font-semibold">Open a {scope === "training" ? "training concern" : "system incident"}</h2>
      <p className="mt-1 text-sm text-muted-foreground">{scope === "training"
        ? "Record a class-related learning, equipment, material, or assessment concern. It remains in Instructor scope."
        : "Record an account, security, configuration, or platform concern in Administrator scope."}</p>
      {!canOpen ? <p className="mt-3 text-sm text-muted-foreground">Create an active class first to open a training concern.</p> : null}
      <form onSubmit={openConcern} className="mt-4 grid gap-4">
        {scope === "training" ? <div className="space-y-1"><Label htmlFor="concern-class">Class</Label>
          <Select value={classId} onValueChange={setClassId} disabled={!canOpen}>
            <SelectTrigger id="concern-class"><SelectValue placeholder="Choose an active class" /></SelectTrigger>
            <SelectContent>{classes.map((classroom) => <SelectItem key={classroom.id} value={classroom.id}>{classroom.title}</SelectItem>)}</SelectContent>
          </Select>
        </div> : null}
        <div className="space-y-1"><Label htmlFor="concern-title">Title</Label>
          <Input id="concern-title" value={title} onChange={(event) => setTitle(event.target.value)} maxLength={160} minLength={5} required disabled={!canOpen} />
        </div>
        <div className="space-y-1"><Label htmlFor="concern-details">Description</Label>
          <Textarea id="concern-details" value={details} onChange={(event) => setDetails(event.target.value)} maxLength={4000} minLength={10} rows={4} required disabled={!canOpen} />
        </div>
        <div><Button type="submit" disabled={!canOpen || busy} className="min-h-11">{busy ? "Recording…" : "Record concern"}</Button></div>
      </form>
    </section>

    <section className="space-y-3">
      <h2 className="font-semibold">{scope === "training" ? "Your training concerns" : "System incidents"}</h2>
      {concerns.length ? concerns.map((concern) => <ConcernCard key={concern.id} concern={concern} canManage classTitle={classById.get(concern.class_id ?? "")} />)
        : <p className="rounded-xl border border-border bg-card p-5 text-sm text-muted-foreground">No concerns have been recorded in this scope.</p>}
    </section>
    {scope === "system" ? <section className="space-y-3">
      <h2 className="font-semibold">Training concern oversight</h2>
      <p className="text-sm text-muted-foreground">Administrators can review Instructor history here but cannot change training concern status.</p>
      {oversight.length ? oversight.map((concern) => <ConcernCard key={concern.id} concern={concern} canManage={false} />)
        : <p className="rounded-xl border border-border bg-card p-5 text-sm text-muted-foreground">No training concerns require oversight.</p>}
    </section> : null}
  </div>;
}
