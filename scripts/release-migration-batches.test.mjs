// Release batches (final review SQL-A C1 / SQL-B I1) and the SQL runner's
// plan check (dashboard-server M6). No database needed.
// Run: node --test scripts/release-migration-batches.test.mjs
import assert from "node:assert/strict";
import { test } from "node:test";
import { buildRelease, classify, inspectMigration, splitTopLevel } from "./release-migration-batches.mjs";
import { suiteOutcome, resolveTarget as suiteTarget } from "./run-local-sql-tests.mjs";
import { EXPECTED_CHANGES, preservationProblems, resolveTarget as rehearsalTarget } from "./rehearse-release-batches.mjs";

test("the re-defense set splits into the enum batch and one transactional batch", () => {
  const release = buildRelease();
  assert.ok(release.batchA.length >= 1);
  // Detected from the SQL: every Batch A file adds enum values, no other does.
  assert.ok(release.batchA.every((item) => item.body.toLowerCase().includes("add value if not exists")));
  assert.ok(release.batchA.some((item) => item.version === "20261119130000"));
  assert.ok(release.batchB.every((item) => !/alter\s+type[^;]+add\s+value/i.test(item.body)));
  assert.equal(release.batchA.length + release.batchB.length, release.manifest.migrations);
  assert.ok(release.manifest.first_version >= "20261119100000");
  // Batch B: one BEGIN/COMMIT, the guard, every version recorded, timeouts reset per file.
  const kinds = splitTopLevel(release.sql.b).map(classify);
  assert.equal(kinds.filter((kind) => kind === "begin").length, 1);
  assert.equal(kinds.filter((kind) => kind === "commit").length, 1);
  assert.equal(kinds[0], "begin");
  assert.equal(kinds.at(-1), "commit");
  assert.match(release.sql.b, /RELEASE_BATCH_A_NOT_APPLIED/);
  assert.match(release.sql.b, /RELEASE_BATCH_B_ALREADY_APPLIED/);
  for (const item of release.batchB) assert.ok(release.sql.b.includes(`values ('${item.version}', '${item.name}'`), item.file);
  // The release defaults are reset before each file (a file's own SET LOCAL then governs only itself).
  assert.equal((release.sql.b.match(/-- >>> [^\n]+\nset local lock_timeout = '5s';\nset local statement_timeout = '120s';\n/g) ?? []).length, release.batchB.length);
  assert.match(release.sql.a, /on conflict \(version\) do nothing/);
});

test("stripping keeps every statement but the file's own BEGIN and COMMIT", () => {
  const sql = "-- header\nbegin;\nset local lock_timeout = '5s';\ncreate function f() returns void language plpgsql as $$\nbegin\n  perform 1; -- ; not a boundary\nend\n$$;\ncomment on function f() is 'it''s; fine';\ncommit;\n";
  const item = inspectMigration("20261120100000_example.sql", sql);
  assert.equal(item.batch, "B");
  assert.ok(!/^begin;$/m.test(item.body) && !/^commit;$/m.test(item.body));
  assert.ok(item.body.includes("perform 1; -- ; not a boundary") && item.body.includes("'it''s; fine'"));
  assert.equal(item.statements, 3);
});

test("files that cannot be batched safely are refused", () => {
  const wrap = (inner) => `begin;\n${inner}\ncommit;\n`;
  assert.throws(() => inspectMigration("20261120100001_a.sql", "create table t(x int);\n"), /BEGIN/);
  assert.throws(() => inspectMigration("20261120100002_b.sql", wrap("create table t(x int);\ncommit;\nbegin;")), /only top-level/);
  assert.throws(() => inspectMigration("20261120100003_c.sql", wrap("savepoint s;")), /transaction control/);
  assert.throws(() => inspectMigration("20261120100004_d.sql", wrap("create index concurrently i on t(x);")), /cannot run in a transaction/);
  assert.throws(() => inspectMigration("20261120100005_e.sql", wrap("alter type public.k add value if not exists 'x';\ncreate table t(x int);")), /split the enum additions/);
  assert.throws(() => inspectMigration("20261120100006_f.sql", wrap("alter type public.k add value 'x';")), /IF NOT EXISTS/);
  assert.equal(inspectMigration("20261120100007_g.sql", wrap("alter type public.k add value if not exists 'x';")).batch, "A");
});

test("a pgTAP suite that ran fewer assertions than planned fails", () => {
  assert.equal(suiteOutcome("1..3\nok 1 - a\nok 2 - b\nok 3 - c\n", 0).ok, true);
  assert.equal(suiteOutcome("1..3\nok 1 - a\nok 2 - b\n# Looks like you planned 3 tests but ran 2\n", 0).ok, false);
  assert.equal(suiteOutcome("1..3\nok 1 - a\nok 2 - b\n", 0).ok, false);
  assert.equal(suiteOutcome("ok 1 - plain suite without a plan\n", 0).ok, true);
  assert.equal(suiteOutcome("1..1\nnot ok 1 - x\n", 0).ok, false);
  assert.equal(suiteOutcome("psql:<stdin>:3: ERROR:  boom\n", 3).ok, false);
});

test("the SQL runner and the rehearsal refuse anything but local or isolated targets", () => {
  const isolated = { Name: "/bytequest-recovery-rslm-redefense-release-1", State: { Running: true }, Config: { Labels: { "bytequest.purpose": "hosted-recovery-redefense" } }, HostConfig: { NetworkMode: "none", ReadonlyRootfs: true, PortBindings: {} } };
  const networked = { ...isolated, HostConfig: { ...isolated.HostConfig, NetworkMode: "bridge" } };
  const inspect = (state) => () => state;
  assert.equal(suiteTarget({ container: "bytequest-recovery-rslm-redefense-release-1", database: "postgres" }, inspect(isolated)).psql[1], "/bq-recovery");
  assert.throws(() => suiteTarget({ container: "bytequest-recovery-rslm-redefense-release-1", database: "postgres" }, inspect(networked)), /Refusing/);
  assert.throws(() => suiteTarget({ container: "some-other-db", database: "postgres" }, inspect(isolated)), /Refusing/);
  assert.equal(rehearsalTarget({ container: "bytequest-recovery-rslm-redefense-release-1" }, inspect(isolated)).kind, "rehearsal");
  assert.throws(() => rehearsalTarget({ container: "bytequest-recovery-rslm-redefense-release-1" }, inspect(networked)), /guard failed/);
  assert.throws(() => rehearsalTarget({ localDb: "postgres" }, inspect({ State: { Running: true } })), /bq_<name>/);
});

test("only the documented backfills may change pre-existing rows; deletions never", () => {
  assert.deepEqual(preservationProblems([{ table: "public.homework_submissions", kind: "changed", rows: 3 }, { table: "public.audit_events", kind: "inserted", rows: 4 }]), []);
  assert.equal(preservationProblems([{ table: "public.audit_events", kind: "deleted", rows: 1 }]).length, 1);
  assert.equal(preservationProblems([{ table: "public.profiles", kind: "changed", rows: 1 }]).length, 1);
  assert.equal(preservationProblems([{ table: "public.audit_events", kind: "changed", rows: 1 }]).length, 1);
  assert.ok(Object.values(EXPECTED_CHANGES).every((entry) => entry.why.length > 10));
});
