export type Crumb = { label: string; href: string };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Workspace prefixes that are not pages of their own. */
const HIDDEN_SEGMENTS = new Set(["admin", "instructor", "dashboard"]);

/** A record id is named after the collection it belongs to, never shown raw. */
const RECORD_LABELS: Record<string, string> = {
  "assessment-criteria": "Criterion",
  assignments: "Assignment",
  attempts: "Attempt",
  classes: "Class",
  competencies: "Competency",
  learners: "Learner",
  modules: "Module",
  quizzes: "Quiz",
  scenarios: "Scenario",
  submissions: "Submission",
  users: "User",
};

export function crumbLabel(segment: string, parent?: string): string {
  if (UUID.test(segment)) return (parent && RECORD_LABELS[parent]) || "Details";
  let words = segment;
  try {
    words = decodeURIComponent(segment);
  } catch {
    // A malformed escape is shown as typed.
  }
  words = words.replace(/-/g, " ");
  return words.charAt(0).toUpperCase() + words.slice(1);
}

/**
 * The breadcrumb trail for a dashboard path, after the Dashboard home crumb.
 * Every href is a route with a page: intermediate segments that only group
 * child routes (a class's assignments, the learner list, a user) have small
 * redirect pages, so a crumb never leads to a 404.
 */
export function breadcrumbTrail(pathname: string): Crumb[] {
  const paths = pathname.split("/").filter(Boolean);
  return paths
    .map((segment, index) => ({
      segment,
      parent: paths[index - 1],
      href: `/${paths.slice(0, index + 1).join("/")}`,
    }))
    .filter(({ segment }) => !HIDDEN_SEGMENTS.has(segment))
    .map(({ segment, parent, href }) => ({ href, label: crumbLabel(segment, parent) }));
}
