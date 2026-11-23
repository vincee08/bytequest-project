import Link from "next/link";
import { AlertTriangle, CheckCircle2, CircleDashed, TrendingDown, type LucideIcon } from "lucide-react";
import { SectionHeading } from "@/components/dashboard/SectionHeading";
import { describePeriod, formatDate, formatPercent, reasonText, statusPresentation } from "@/lib/analytics/format";
import { groupLearnersByStatus, type LearnerStatusGroup, type LearnerStatusState } from "@/lib/analytics/learner-status";
import type { LearnerRow, LearnerStatus } from "@/lib/analytics/performance-types";
import { cn } from "@/lib/utils";

const STATUS_ICON: Record<LearnerStatus, LucideIcon> = {
  falling_behind: TrendingDown,
  struggling: AlertTriangle,
  on_track: CheckCircle2,
};

const STATUS_EMPTY: Record<LearnerStatus, string> = {
  falling_behind: "No learner is falling behind in this scope.",
  struggling: "No learner meets a struggling rule in this scope.",
  on_track: "No learner is on track in this scope yet.",
};

/**
 * Who is falling behind, struggling or on track, by name, with the documented
 * rule that applies. No client state, so it renders on the server dashboard
 * and inside the analytics overview alike.
 */
export function LearnerStatusBoard({
  status,
  scopeLabel,
  profileQuery,
  allHref,
  limit,
  className,
}: {
  status: LearnerStatusState;
  /** Population wording, e.g. "your active classes". */
  scopeLabel: string;
  /** Analytics filters carried into the learner profile link. */
  profileQuery?: string;
  /** The full learner list (analytics Learners tab). */
  allHref?: string;
  /** Learners listed per status; the rest are counted and linked. */
  limit?: number;
  className?: string;
}) {
  const ready = status.state === "ready" ? status.data : null;
  const description = ready
    ? `Learners in ${scopeLabel} by follow-up status · ${describePeriod(ready.period)}. Each learner shows the rule that applies.`
    : "Learners by follow-up status.";

  return (
    <section aria-label="Learner status" className={cn("overflow-hidden rounded-xl border border-border bg-card", className)}>
      <SectionHeading
        title="Learner status"
        description={description}
        action={allHref && ready ? (
          <Link href={allHref} className="inline-flex min-h-9 items-center text-xs font-medium text-primary hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
            Open the learner list
          </Link>
        ) : undefined}
      />
      {!ready ? (
        <div className="flex items-start gap-3 px-5 py-6 text-sm text-muted-foreground" role="status">
          <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" aria-hidden="true" />
          <p>Learner status could not be loaded right now. The other figures are not affected; refresh the page to try again.</p>
        </div>
      ) : ready.learners.length === 0 ? (
        <div className="px-5 py-10 text-center" role="status">
          <CircleDashed className="mx-auto h-6 w-6 text-muted-foreground" aria-hidden="true" />
          <p className="mt-3 text-sm font-medium text-foreground">No active learners in scope</p>
          <p className="mx-auto mt-1 max-w-xl text-sm text-muted-foreground">Statuses appear once learners are enrolled in the selected classes.</p>
        </div>
      ) : (
        <div className="grid divide-y divide-border/70 lg:grid-cols-3 lg:divide-x lg:divide-y-0">
          {groupLearnersByStatus(ready, limit).map((group) => (
            <StatusColumn key={group.status} group={group} profileQuery={profileQuery} allHref={allHref} />
          ))}
        </div>
      )}
      <p className="border-t border-border/70 px-5 py-2.5 text-xs leading-5 text-muted-foreground">
        Statuses are follow-up signals computed from the documented thresholds, not TESDA competency decisions.
      </p>
    </section>
  );
}

function StatusColumn({ group, profileQuery, allHref }: { group: LearnerStatusGroup; profileQuery?: string; allHref?: string }) {
  const presentation = statusPresentation(group.status);
  const Icon = STATUS_ICON[group.status];
  const noun = `learner${group.count === 1 ? "" : "s"}`;
  return (
    <div className="flex min-w-0 flex-col p-4 sm:p-5">
      <div className="flex items-start gap-3">
        <span className={cn("flex h-9 w-9 shrink-0 items-center justify-center rounded-lg border", presentation.badgeClassName)}>
          <Icon className="h-4 w-4" aria-hidden="true" />
        </span>
        <div className="min-w-0 flex-1">
          <h3 className="text-sm font-semibold text-foreground">{presentation.label}</h3>
          <p className="mt-0.5 text-[11px] leading-4 text-muted-foreground">{presentation.description}</p>
        </div>
        <p className="text-2xl font-bold leading-none tabular-nums tracking-[-0.02em] text-foreground">
          {group.count}<span className="sr-only"> {noun}</span>
        </p>
      </div>
      {group.learners.length ? (
        <ul className="mt-3 divide-y divide-border/70" aria-label={`${presentation.label} learners`}>
          {group.learners.map((row) => <LearnerItem key={row.id} row={row} profileQuery={profileQuery} />)}
        </ul>
      ) : (
        <p className="mt-3 rounded-lg border border-dashed border-border px-3 py-4 text-center text-xs text-muted-foreground">
          {STATUS_EMPTY[group.status]}
        </p>
      )}
      {group.hidden > 0 ? (
        allHref ? (
          <Link href={allHref} className="mt-2 inline-flex min-h-9 items-center text-xs font-medium text-primary hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
            +{group.hidden} more {presentation.label.toLowerCase()} in the learner list
          </Link>
        ) : <p className="mt-2 text-xs text-muted-foreground">+{group.hidden} more {presentation.label.toLowerCase()}</p>
      ) : null}
    </div>
  );
}

function LearnerItem({ row, profileQuery }: { row: LearnerRow; profileQuery?: string }) {
  const classes = row.classes.map((item) => item.title).join(", ");
  const identity = [row.student_id, classes || "No class in scope"].filter(Boolean).join(" · ");
  const detail = [
    row.progress_percent !== null ? `Progress ${formatPercent(row.progress_percent)}` : null,
    row.last_activity_at ? `Last activity ${formatDate(row.last_activity_at)}` : null,
  ].filter(Boolean).join(" · ");
  return (
    <li className="py-2.5">
      <Link href={`/progress/learners/${row.id}${profileQuery ? `?${profileQuery}` : ""}`}
        className="text-sm font-medium text-primary hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
        {row.name || "Unnamed learner"}
      </Link>
      <p className="mt-0.5 break-words text-xs text-muted-foreground">{identity}</p>
      {row.reasons.length ? (
        <ul className="mt-1 space-y-0.5 text-xs leading-5 text-foreground/85">
          {row.reasons.map((reason) => <li key={reason.code}>{reasonText(reason)}</li>)}
        </ul>
      ) : (
        <p className="mt-1 text-xs leading-5 text-muted-foreground">{detail || "No falling-behind or struggling rule applies."}</p>
      )}
    </li>
  );
}
