/**
 * Shared analytics filter state. The URL is the source of truth: every filter
 * change re-renders the server page, which re-queries the SECURITY INVOKER
 * analytics RPCs with `toRpcFilters(query)`. PostgreSQL validates the same
 * filters again (unknown keys, UUIDs, 366-day limit, class ownership).
 */

export const ANALYTICS_TABS = ["overview", "classes", "learners", "quizzes", "missions", "criteria"] as const;
export type AnalyticsTab = (typeof ANALYTICS_TABS)[number];

export const ANALYTICS_TAB_LABELS: Record<AnalyticsTab, string> = {
  overview: "Overview",
  classes: "Classes",
  learners: "Learners",
  quizzes: "Quizzes",
  missions: "Missions",
  criteria: "Criteria",
};

export const RANGE_PRESETS = ["7", "30", "90", "365", "custom"] as const;
export type RangePreset = (typeof RANGE_PRESETS)[number];

export const RANGE_LABELS: Record<RangePreset, string> = {
  "7": "Last 7 days",
  "30": "Last 30 days",
  "90": "Last 90 days",
  "365": "Last 12 months",
  custom: "Custom range",
};

export type AnalyticsQuery = {
  tab: AnalyticsTab;
  classId: string | null;
  cocCode: string | null;
  moduleId: string | null;
  topicId: string | null;
  missionCode: string | null;
  quizId: string | null;
  learnerId: string | null;
  range: RangePreset;
  /** Inclusive Manila calendar dates (YYYY-MM-DD) shown in the date inputs. */
  fromDate: string;
  toDate: string;
  /** ISO timestamps sent to PostgreSQL. */
  from: string;
  to: string;
};

export type AnalyticsFilterKey = "classId" | "cocCode" | "moduleId" | "topicId" | "missionCode" | "quizId" | "learnerId";

type SearchParamsInput = URLSearchParams | Record<string, string | string[] | undefined>;

const DAY_MS = 86_400_000;
const MAX_RANGE_DAYS = 366;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

/** URL parameter name for each filter. */
export const FILTER_PARAM: Record<AnalyticsFilterKey, string> = {
  classId: "class",
  cocCode: "coc",
  moduleId: "module",
  topicId: "topic",
  missionCode: "mission",
  quizId: "quiz",
  learnerId: "learner",
};

function read(params: SearchParamsInput, key: string): string | undefined {
  if (params instanceof URLSearchParams) return params.get(key) ?? undefined;
  const value = params[key];
  return Array.isArray(value) ? value[0] : value;
}

function uuidOrNull(value: string | undefined): string | null {
  return value && UUID_PATTERN.test(value) ? value.toLowerCase() : null;
}

/** Calendar date (YYYY-MM-DD) of an instant in Asia/Manila. */
export function manilaDate(instant: Date): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Manila",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(instant);
}

/** Start (00:00:00.000) or end (23:59:59.999) of a Manila calendar date, as ISO. */
export function manilaBoundary(date: string, boundary: "start" | "end"): string | null {
  if (!DATE_PATTERN.test(date)) return null;
  const suffix = boundary === "start" ? "T00:00:00.000+08:00" : "T23:59:59.999+08:00";
  const parsed = new Date(`${date}${suffix}`);
  if (Number.isNaN(parsed.getTime())) return null;
  // Reject impossible dates such as 2026-02-31 that Date silently rolls over.
  if (manilaDate(parsed) !== date) return null;
  return parsed.toISOString();
}

function presetWindow(range: Exclude<RangePreset, "custom">, now: Date) {
  const days = Number(range);
  const toDate = manilaDate(now);
  const fromDate = manilaDate(new Date(now.getTime() - (days - 1) * DAY_MS));
  return {
    fromDate,
    toDate,
    from: manilaBoundary(fromDate, "start") as string,
    to: now.toISOString(),
  };
}

export function parseAnalyticsQuery(
  params: SearchParamsInput,
  now: Date = new Date(),
  defaults: { tab?: AnalyticsTab; range?: Exclude<RangePreset, "custom"> } = {},
): AnalyticsQuery {
  const tabValue = read(params, "tab");
  const tab = (ANALYTICS_TABS as readonly string[]).includes(tabValue ?? "")
    ? (tabValue as AnalyticsTab)
    : defaults.tab ?? "overview";
  const cocValue = read(params, "coc")?.toLowerCase();
  const missionValue = read(params, "mission")?.toLowerCase();
  const fallbackRange = defaults.range ?? "30";
  const rangeValue = read(params, "range");
  let range: RangePreset = (RANGE_PRESETS as readonly string[]).includes(rangeValue ?? "")
    ? (rangeValue as RangePreset)
    : fallbackRange;

  let window = range === "custom" ? null : presetWindow(range, now);
  if (range === "custom") {
    const fromDate = read(params, "from") ?? "";
    const toDate = read(params, "to") ?? "";
    const from = manilaBoundary(fromDate, "start");
    const to = manilaBoundary(toDate, "end");
    const valid = from !== null && to !== null && from <= to
      && new Date(to).getTime() - new Date(from).getTime() <= MAX_RANGE_DAYS * DAY_MS;
    if (valid) {
      window = { fromDate, toDate, from: from as string, to: to as string };
    } else {
      range = fallbackRange;
      window = presetWindow(fallbackRange, now);
    }
  }

  return {
    tab,
    classId: uuidOrNull(read(params, "class")),
    cocCode: cocValue && /^coc[1-4]$/.test(cocValue) ? cocValue : null,
    moduleId: uuidOrNull(read(params, "module")),
    topicId: uuidOrNull(read(params, "topic")),
    missionCode: missionValue && /^coc[1-4]_m[1-5]$/.test(missionValue) ? missionValue : null,
    quizId: uuidOrNull(read(params, "quiz")),
    learnerId: uuidOrNull(read(params, "learner")),
    range,
    ...(window as NonNullable<typeof window>),
  };
}

/** Serializes a query to URL parameters; `parseAnalyticsQuery` round-trips it. */
export function analyticsSearchParams(query: AnalyticsQuery, overrides: Partial<AnalyticsQuery> = {}): URLSearchParams {
  const next = { ...query, ...overrides };
  const params = new URLSearchParams();
  params.set("tab", next.tab);
  for (const key of Object.keys(FILTER_PARAM) as AnalyticsFilterKey[]) {
    const value = next[key];
    if (value) params.set(FILTER_PARAM[key], value);
  }
  params.set("range", next.range);
  if (next.range === "custom") {
    params.set("from", next.fromDate);
    params.set("to", next.toDate);
  }
  return params;
}

export function analyticsHref(pathname: string, query: AnalyticsQuery, overrides: Partial<AnalyticsQuery> = {}): string {
  return `${pathname}?${analyticsSearchParams(query, overrides).toString()}`;
}

/** The `p_filters` object for the analytics RPCs (snake_case, unset filters omitted). */
export function toRpcFilters(query: AnalyticsQuery): Record<string, string> {
  const filters: Record<string, string> = { from: query.from, to: query.to };
  if (query.classId) filters.class_id = query.classId;
  if (query.cocCode) filters.coc_code = query.cocCode;
  if (query.moduleId) filters.module_id = query.moduleId;
  if (query.topicId) filters.topic_id = query.topicId;
  if (query.missionCode) filters.mission_code = query.missionCode;
  if (query.quizId) filters.quiz_id = query.quizId;
  if (query.learnerId) filters.learner_id = query.learnerId;
  return filters;
}

export type FilterCatalog = {
  modules: Array<{ id: string; coc_code: string }>;
  topics: Array<{ id: string; module_id: string; coc_code: string }>;
  missions: Array<{ mission_code: string; coc_code: string; module_id: string | null }>;
  quizzes: Array<{ id: string; coc_code: string | null }>;
  learners: Array<{ id: string; class_ids: string[] }>;
};

/**
 * Applies one filter change and clears dependent filters that would no longer
 * be consistent (a module from another COC, a topic outside the module, a
 * mission outside the COC/module, a quiz from another COC, a learner outside
 * the class), so the URL never carries a contradictory combination.
 */
export function applyFilterChange(
  query: AnalyticsQuery,
  key: AnalyticsFilterKey,
  value: string | null,
  catalog: FilterCatalog,
): AnalyticsQuery {
  const next: AnalyticsQuery = { ...query, [key]: value || null };
  const moduleCoc = next.moduleId ? catalog.modules.find((item) => item.id === next.moduleId)?.coc_code ?? null : null;

  if (key === "moduleId" && moduleCoc) next.cocCode = moduleCoc;
  if (key === "topicId" && next.topicId) {
    const topic = catalog.topics.find((item) => item.id === next.topicId);
    if (topic) {
      next.moduleId = topic.module_id;
      next.cocCode = topic.coc_code;
    }
  }
  if (key === "missionCode" && next.missionCode) {
    const mission = catalog.missions.find((item) => item.mission_code === next.missionCode);
    if (mission) {
      next.cocCode = mission.coc_code;
      if (next.moduleId && mission.module_id !== next.moduleId) next.moduleId = null;
    }
  }

  if (next.cocCode && next.moduleId) {
    const coc = catalog.modules.find((item) => item.id === next.moduleId)?.coc_code;
    if (coc && coc !== next.cocCode) next.moduleId = null;
  }
  if (next.topicId) {
    const topic = catalog.topics.find((item) => item.id === next.topicId);
    if (topic && ((next.moduleId && topic.module_id !== next.moduleId) || (next.cocCode && topic.coc_code !== next.cocCode))) {
      next.topicId = null;
    }
  }
  if (next.missionCode) {
    const mission = catalog.missions.find((item) => item.mission_code === next.missionCode);
    if (mission && ((next.cocCode && mission.coc_code !== next.cocCode) || (next.moduleId && mission.module_id !== next.moduleId))) {
      next.missionCode = null;
    }
  }
  if (next.quizId && next.cocCode) {
    const quiz = catalog.quizzes.find((item) => item.id === next.quizId);
    if (quiz && quiz.coc_code && quiz.coc_code !== next.cocCode) next.quizId = null;
  }
  if (next.learnerId && next.classId) {
    const learner = catalog.learners.find((item) => item.id === next.learnerId);
    if (learner && !learner.class_ids.includes(next.classId)) next.learnerId = null;
  }
  return next;
}

export function activeFilterCount(query: AnalyticsQuery): number {
  return (Object.keys(FILTER_PARAM) as AnalyticsFilterKey[]).filter((key) => Boolean(query[key])).length;
}
