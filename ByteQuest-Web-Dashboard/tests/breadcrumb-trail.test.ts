import assert from "node:assert/strict";
import { readdirSync, statSync } from "node:fs";
import { join, relative, sep } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { breadcrumbTrail, crumbLabel } from "../src/lib/navigation/breadcrumb-trail";

const appDir = fileURLToPath(new URL("../src/app/", import.meta.url));
const sampleId = "949eee08-b7a9-4ec5-a4ec-3c9f8b400083";

/** Every route of the dashboard that renders a page, e.g. "/classes/[id]". */
function pageRoutes(dir = appDir): string[] {
  const routes: string[] = [];
  for (const entry of readdirSync(dir)) {
    const path = join(dir, entry);
    if (statSync(path).isDirectory()) routes.push(...pageRoutes(path));
    else if (entry === "page.tsx") {
      const route = relative(appDir, dir).split(sep).filter((part) => part && !/^\(.*\)$/.test(part));
      routes.push(`/${route.join("/")}`);
    }
  }
  return routes;
}

function matcher(route: string): RegExp {
  const pattern = route.split("/").map((part) => (/^\[.+\]$/.test(part) ? "[^/]+" : part.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"))).join("/");
  return new RegExp(`^${pattern || "/"}$`);
}

// Production QA 2026-11-20: the "Assignments" crumb on a homework page led to
// /classes/<id>/assignments, which had no page (404, and a 404 RSC prefetch
// on every visit); /progress/learners and /users/<id> had the same gap.
test("every breadcrumb link of every dashboard page leads to a page", () => {
  const routes = pageRoutes();
  assert.ok(routes.includes("/classes/[id]/assignments/[assignmentId]"), "route scan found the app pages");
  const pages = routes.map(matcher);
  // Breadcrumbs render inside the signed-in dashboard layout only.
  const publicRoute = /^\/(auth|login|signup)(\/|$)/;
  for (const route of routes.filter((route) => !publicRoute.test(route))) {
    const pathname = route.replace(/\[[^\]]+\]/g, sampleId);
    for (const crumb of breadcrumbTrail(pathname)) {
      assert.ok(
        pages.some((page) => page.test(crumb.href)),
        `${route}: the "${crumb.label}" crumb links to ${crumb.href}, which has no page`,
      );
    }
  }
});

test("record ids read as the record they open, never as a raw id", () => {
  assert.deepEqual(breadcrumbTrail(`/classes/${sampleId}/assignments/${sampleId}`), [
    { href: "/classes", label: "Classes" },
    { href: `/classes/${sampleId}`, label: "Class" },
    { href: `/classes/${sampleId}/assignments`, label: "Assignments" },
    { href: `/classes/${sampleId}/assignments/${sampleId}`, label: "Assignment" },
  ]);
  assert.equal(crumbLabel(sampleId, "quizzes"), "Quiz");
  assert.equal(crumbLabel(sampleId, "learners"), "Learner");
  assert.equal(crumbLabel(sampleId, "unknown"), "Details");
  assert.equal(crumbLabel("assessment-criteria"), "Assessment criteria");
  assert.equal(crumbLabel("%E0%A4%A"), "%E0%A4%A", "a malformed escape is shown as typed");
});

test("workspace prefixes are not crumbs", () => {
  assert.deepEqual(breadcrumbTrail("/admin/analytics"), [{ href: "/admin/analytics", label: "Analytics" }]);
  assert.deepEqual(breadcrumbTrail("/instructor/dashboard"), []);
});
