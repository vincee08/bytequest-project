import { z } from "zod";

/** Client-safe learner/account directory filters (URL state) and search_learners arguments. */

export const LEARNER_PAGE_SIZE = 25;
export const learnerSortKeys = ["name", "student_id", "last_activity", "created"] as const;
export type LearnerSortKey = (typeof learnerSortKeys)[number];
export type SortDirection = "asc" | "desc";
export const learnerSortDefaults: Record<LearnerSortKey, SortDirection> = {
  name: "asc",
  student_id: "asc",
  last_activity: "desc",
  created: "desc",
};
export const learnerStatusFilters = ["all", "active", "inactive"] as const;
export type LearnerStatusFilter = (typeof learnerStatusFilters)[number];
export const learnerStatusLabels: Record<LearnerStatusFilter, string> = {
  all: "All account statuses",
  active: "Active accounts",
  inactive: "Inactive accounts",
};

export type LearnerSearchFilters = {
  q: string;
  classId: string | null;
  status: LearnerStatusFilter;
  sort: LearnerSortKey;
  direction: SortDirection;
  page: number;
};

export type LearnerSearchRow = {
  user_id: string;
  full_name: string;
  email: string;
  learner_id: string | null;
  learner_id_managed: boolean;
  status: string;
  classes: { id: string; title: string }[];
  last_activity_at: string | null;
  created_at: string;
};
export type LearnerSearchResult = { total: number; limit: number; offset: number; rows: LearnerSearchRow[] };

type Params = Record<string, string | string[] | undefined>;
const first = (params: Params, key: string) => {
  const value = params[key];
  return Array.isArray(value) ? value[0] : value;
};

export function cleanSearchText(value: string | undefined, max = 100) {
  // eslint-disable-next-line no-control-regex
  return (value ?? "").replace(/[\u0000-\u001f\u007f]/g, "").trim().slice(0, max).trim();
}

function parsePage(value: string | undefined) {
  const page = Number.parseInt(value ?? "", 10);
  return Number.isFinite(page) && page >= 1 && page <= 10_000 ? page : 1;
}

export function parseLearnerSearchParams(params: Params): LearnerSearchFilters {
  const classId = first(params, "class");
  const status = first(params, "status");
  const sort = first(params, "sort");
  const key: LearnerSortKey = learnerSortKeys.includes(sort as LearnerSortKey) ? (sort as LearnerSortKey) : "name";
  const dir = first(params, "dir");
  return {
    q: cleanSearchText(first(params, "q")),
    classId: classId && z.string().uuid().safeParse(classId).success ? classId : null,
    status: learnerStatusFilters.includes(status as LearnerStatusFilter) ? (status as LearnerStatusFilter) : "all",
    sort: key,
    direction: dir === "asc" || dir === "desc" ? dir : learnerSortDefaults[key],
    page: parsePage(first(params, "page")),
  };
}

export function learnerSearchRpcArgs(filters: LearnerSearchFilters) {
  return {
    p_query: filters.q || null,
    p_class_id: filters.classId,
    p_status: filters.status === "all" ? null : filters.status,
    p_sort: `${filters.sort}.${filters.direction}`,
    p_limit: LEARNER_PAGE_SIZE,
    p_offset: (filters.page - 1) * LEARNER_PAGE_SIZE,
  };
}

/** Builds a directory URL, omitting default values. */
export function learnerSearchHref(basePath: string, filters: LearnerSearchFilters, overrides: Partial<LearnerSearchFilters>) {
  const next = { ...filters, ...overrides };
  const query = new URLSearchParams();
  if (next.q) query.set("q", next.q);
  if (next.classId) query.set("class", next.classId);
  if (next.status !== "all") query.set("status", next.status);
  if (next.sort !== "name") query.set("sort", next.sort);
  if (next.direction !== learnerSortDefaults[next.sort]) query.set("dir", next.direction);
  if (next.page > 1) query.set("page", String(next.page));
  const text = query.toString();
  return text ? `${basePath}?${text}` : basePath;
}

/** Header link: toggles the active column, otherwise sorts by the column's default direction. */
export function learnerSortHref(basePath: string, filters: LearnerSearchFilters, key: LearnerSortKey) {
  const direction: SortDirection = filters.sort === key
    ? (filters.direction === "asc" ? "desc" : "asc")
    : learnerSortDefaults[key];
  return learnerSearchHref(basePath, filters, { sort: key, direction, page: 1 });
}

export function pageWindow(total: number, page: number, size = LEARNER_PAGE_SIZE) {
  return {
    from: total === 0 ? 0 : (page - 1) * size + 1,
    to: Math.min(total, page * size),
    pages: Math.max(1, Math.ceil(total / size)),
  };
}

// ---------------------------------------------------------------------------
// Account directory (/users): every role, filtered server-side.
// ---------------------------------------------------------------------------
export const userRoleFilters = ["all", "learner", "instructor", "admin"] as const;
export type UserRoleFilter = (typeof userRoleFilters)[number];
export const userRoleLabels: Record<UserRoleFilter, string> = {
  all: "All roles",
  learner: "Learners",
  instructor: "Instructors",
  admin: "Administrators",
};
export const userSortKeys = ["created", "name"] as const;
export type UserSortKey = (typeof userSortKeys)[number];
export type UserDirectoryFilters = { q: string; role: UserRoleFilter; status: LearnerStatusFilter; sort: UserSortKey; page: number };

export function parseUserDirectoryParams(params: Params): UserDirectoryFilters {
  const role = first(params, "role");
  const status = first(params, "status");
  const sort = first(params, "sort");
  return {
    q: cleanSearchText(first(params, "q")),
    role: userRoleFilters.includes(role as UserRoleFilter) ? (role as UserRoleFilter) : "all",
    status: learnerStatusFilters.includes(status as LearnerStatusFilter) ? (status as LearnerStatusFilter) : "all",
    sort: userSortKeys.includes(sort as UserSortKey) ? (sort as UserSortKey) : "created",
    page: parsePage(first(params, "page")),
  };
}

/**
 * PostgREST `or` filter for the account directory: the phrase is a literal,
 * case-insensitive substring of the name, email or student ID. Values are
 * JSON-quoted and LIKE wildcards escaped, so input can never add operators.
 */
export function accountSearchFilter(term: string) {
  const value = JSON.stringify(`%${term.replace(/[\\%_]/g, "\\$&")}%`);
  return `full_name.ilike.${value},email.ilike.${value},learner_id.ilike.${value}`;
}

export function userDirectoryHref(filters: UserDirectoryFilters, overrides: Partial<UserDirectoryFilters>) {
  const next = { ...filters, ...overrides };
  const query = new URLSearchParams();
  if (next.q) query.set("q", next.q);
  if (next.role !== "all") query.set("role", next.role);
  if (next.status !== "all") query.set("status", next.status);
  if (next.sort !== "created") query.set("sort", next.sort);
  if (next.page > 1) query.set("page", String(next.page));
  const text = query.toString();
  return text ? `/users?${text}` : "/users";
}
