import type { LearnerStatus, StatusReason } from "@/lib/analytics/performance-types";

/** Shown wherever a metric has no data (PostgreSQL returned null). */
export const NO_DATA = "—";

const MANILA = "Asia/Manila";

export function formatPercent(value: number | null | undefined): string {
  if (value === null || value === undefined || Number.isNaN(value)) return NO_DATA;
  return `${Number.isInteger(value) ? value.toFixed(0) : value.toFixed(1)}%`;
}

export function formatNumber(value: number | null | undefined, fractionDigits = 1): string {
  if (value === null || value === undefined || Number.isNaN(value)) return NO_DATA;
  return Number.isInteger(value) ? String(value) : value.toFixed(fractionDigits);
}

export function formatCount(value: number): string {
  return new Intl.NumberFormat("en-PH").format(value);
}

/** 206.7 -> "3m 27s"; 45 -> "45s"; 3720 -> "1h 2m". */
export function formatDuration(seconds: number | null | undefined): string {
  if (seconds === null || seconds === undefined || Number.isNaN(seconds)) return NO_DATA;
  const total = Math.max(0, Math.round(seconds));
  const hours = Math.floor(total / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  const rest = total % 60;
  if (hours) return `${hours}h ${minutes}m`;
  if (minutes) return `${minutes}m ${rest.toString().padStart(2, "0")}s`;
  return `${rest}s`;
}

export function formatDate(value: string | null | undefined): string {
  if (!value) return NO_DATA;
  return new Intl.DateTimeFormat("en-PH", { dateStyle: "medium", timeZone: MANILA }).format(new Date(value));
}

export function formatDateTime(value: string | null | undefined): string {
  if (!value) return NO_DATA;
  return new Intl.DateTimeFormat("en-PH", { dateStyle: "medium", timeStyle: "short", timeZone: MANILA }).format(new Date(value));
}

export function formatShortDay(value: string): string {
  return new Intl.DateTimeFormat("en-PH", { month: "short", day: "numeric", timeZone: "UTC" }).format(new Date(`${value}T00:00:00Z`));
}

/** "Updated hh:mm:ss" clock (24-hour, Manila). */
export function formatClock(value: string | Date): string {
  return new Intl.DateTimeFormat("en-GB", {
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
    timeZone: MANILA,
  }).format(typeof value === "string" ? new Date(value) : value);
}

/** "Nov 1 – Nov 19, 2026" from the period returned by PostgreSQL. */
export function describePeriod(period: { from: string; to: string }): string {
  const format = new Intl.DateTimeFormat("en-PH", { month: "short", day: "numeric", year: "numeric", timeZone: MANILA });
  return `${format.format(new Date(period.from))} – ${format.format(new Date(period.to))}`;
}

export type StatusPresentation = {
  label: string;
  description: string;
  tone: "positive" | "attention" | "critical";
  badgeClassName: string;
};

export const STATUS_PRESENTATION: Record<LearnerStatus, StatusPresentation> = {
  on_track: {
    label: "On track",
    description: "No falling-behind or struggling rule applies.",
    tone: "positive",
    badgeClassName: "border-emerald-200 bg-emerald-50 text-emerald-800",
  },
  struggling: {
    label: "Struggling",
    description: "Quiz average below 75 %, a not-yet-competent released result, or 3+ incomplete runs on one mission.",
    tone: "attention",
    badgeClassName: "border-amber-200 bg-amber-50 text-amber-900",
  },
  falling_behind: {
    label: "Falling behind",
    description: "No activity for 14 days, learning progress below half of the class median, or homework or a quiz past its deadline without a submission.",
    tone: "critical",
    badgeClassName: "border-red-200 bg-red-50 text-red-800",
  },
};

export function statusPresentation(status: LearnerStatus): StatusPresentation {
  return STATUS_PRESENTATION[status];
}

/** One readable sentence per status reason, using the values PostgreSQL returned. */
export function reasonText(reason: StatusReason): string {
  switch (reason.code) {
    case "inactive":
      return reason.last_activity_at
        ? `No recorded activity for ${reason.days_inactive ?? reason.threshold_days ?? 14} days (last ${formatDate(reason.last_activity_at)})`
        : `No recorded activity since enrolment (${reason.days_inactive ?? reason.threshold_days ?? 14} days)`;
    case "below_class_median":
      return `Progress ${formatPercent(reason.progress_percent)} is below half of the ${reason.class_title ?? "class"} median (${formatPercent(reason.class_median)})`;
    case "missed_deadlines": {
      const items = reason.items ?? [];
      const count = reason.missed_count ?? items.length;
      const named = items.map((item) => `${item.title} (${item.kind}, due ${formatDate(item.deadline_at)})`);
      const more = count > named.length ? `, and ${count - named.length} more` : "";
      return `Missed ${count} deadline${count === 1 ? "" : "s"} without submitting${named.length ? `: ${named.join(", ")}${more}` : ""}`;
    }
    case "quiz_average_low":
      return `Quiz average ${formatPercent(reason.quiz_avg)} is below ${reason.threshold ?? 75}%`;
    case "not_yet_competent": {
      const missions = (reason.missions ?? []).map((item) => (typeof item === "string" ? item : item.title ?? item.mission_code));
      return `Not yet competent: ${missions.join(", ") || "a released assessment"}`;
    }
    case "repeated_incomplete_runs": {
      const missions = (reason.missions ?? []).map((item) =>
        typeof item === "string" ? item : `${item.title ?? item.mission_code} (${item.incomplete_runs} incomplete runs)`);
      return `Repeated incomplete practice: ${missions.join(", ")}`;
    }
    default:
      return "Support signal";
  }
}

export const OUTCOME_LABELS: Record<string, string> = {
  competent: "Competent",
  not_yet_competent: "Not yet competent",
  pending_tesda_validation: "Pending validation",
  satisfied: "Satisfied",
  not_satisfied: "Not satisfied",
  requires_review: "Requires review",
  not_evaluated: "Not evaluated",
};

export function outcomeLabel(value: string | null | undefined): string {
  if (!value) return NO_DATA;
  return OUTCOME_LABELS[value] ?? value.replaceAll("_", " ").replace(/^\w/, (letter) => letter.toUpperCase());
}

export const COC_LABEL = (code: string | null | undefined) => (code ? code.toUpperCase() : NO_DATA);
