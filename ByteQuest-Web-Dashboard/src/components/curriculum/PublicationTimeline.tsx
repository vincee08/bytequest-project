import React from "react";
import { Badge } from "@/components/ui/badge";
import type { PublicationEvent, TopicRevision } from "@/lib/curriculum/types";
import { statusLabels } from "@/lib/curriculum/workflow";

const dateTime = new Intl.DateTimeFormat("en-PH", { dateStyle: "medium", timeStyle: "short" });

export function ContentStatusBadge({ status }: { status: TopicRevision["status"] }) {
  const variant = status === "published" ? "secondary" : status === "needs_revision" || status === "archived" ? "destructive" : status === "unpublished" ? "outline" : "default";
  return <Badge variant={variant}>{statusLabels[status]}</Badge>;
}

/** Append-only workflow history from content_publication_events. */
export function PublicationTimeline({
  events,
  revisions,
  people,
}: {
  events: PublicationEvent[];
  revisions: TopicRevision[];
  people: Record<string, string>;
}) {
  if (!events.length) return <p className="text-sm text-muted-foreground">No workflow history yet.</p>;
  const revisionNumber = new Map(revisions.map((revision) => [revision.id, revision.revision_number]));
  return (
    <ol className="space-y-3" aria-label="Publication history">
      {events.map((event) => (
        <li key={event.id} className="relative border-l-2 border-border pl-4">
          <span className="absolute -left-[5px] top-1.5 h-2 w-2 rounded-full bg-primary" aria-hidden="true" />
          <div className="flex flex-wrap items-center gap-2 text-sm">
            <span className="font-semibold">
              {event.from_status ? `${statusLabels[event.from_status]} → ${statusLabels[event.to_status]}` : statusLabels[event.to_status]}
            </span>
            {event.revision_id && revisionNumber.has(event.revision_id) ? (
              <Badge variant="outline">Revision {revisionNumber.get(event.revision_id)}</Badge>
            ) : null}
          </div>
          <p className="text-xs text-muted-foreground">
            {(event.actor_id && people[event.actor_id]) || "Staff member"} · {dateTime.format(new Date(event.occurred_at))}
          </p>
          {event.note ? <p className="mt-1 whitespace-pre-wrap text-sm text-foreground/85">{event.note}</p> : null}
        </li>
      ))}
    </ol>
  );
}
