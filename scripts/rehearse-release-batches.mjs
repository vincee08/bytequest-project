// Rehearses a targeted release on an ISOLATED copy (re-defense rollout plan
// step 3): applies exactly the Batch A / Batch B artifacts of
// scripts/release-migration-batches.mjs, as the hosted maintenance role
// (postgres), then checks that no pre-existing row changed except the
// documented backfills, and reads the result back.
//
// Targets (both are local Docker; neither can reach the hosted project):
//   --container <name>   a restored-production rehearsal container started by
//                        scripts/rehearse-production-release.mjs --restore-only
//                        (name bytequest-recovery-*, label bytequest.purpose=
//                        hosted-recovery-*, network none, read-only root, no
//                        published ports); psql over its private socket.
//   --local-db bq_<name> a scratch database inside the local stack container
//                        (tooling tests only; never the main "postgres").
// Usage:
//   node scripts/release-migration-batches.mjs --out .tmp/release-redefense
//   node scripts/rehearse-release-batches.mjs --artifacts .tmp/release-redefense --container <name>
//     [--with-suites] [--evidence <file.json>] [--apply-as postgres]
// --with-suites loads supabase/tests/fixtures/qa_fixture_users.sql into the
// copy and runs every rollback suite there (scripts/run-local-sql-tests.mjs).
// The copy keeps the applied release; it is a throwaway tmpfs restore or a
// scratch database. Plaintext evidence holds counts and table names only.
import fs from "node:fs";
import path from "node:path";
import { createHash } from "node:crypto";
import { execFileSync, spawnSync } from "node:child_process";
import { fileURLToPath, pathToFileURL } from "node:url";
import { buildRelease } from "./release-migration-batches.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const LOCAL_CONTAINER = "supabase_db_ByteQuest";
const SOCKET = "/bq-recovery";

/**
 * Pre-existing rows the release may change, with the migration that does it
 * (rollout plan "documented changes"). Deleting a pre-existing row is never
 * allowed; columns added by the release are not compared.
 */
export const EXPECTED_CHANGES = {
  "public.missions": { kinds: ["changed"], why: "catalog title sync (20261119100100 contract trigger)" },
  "public.practice_mission_contracts": { kinds: ["changed"], why: "catalog sync touch and COC1 M2 contract v3 (20261119100100, 20261119110200)" },
  "public.homework_submissions": { kinds: ["changed"], why: "release backfill of graded homework (20261119140100)" },
  "public.audit_events": { kinds: ["inserted"], why: "backfill audit rows (homework.release_backfill and others)" },
  "public.achievements": { kinds: ["changed", "inserted"], why: "achievement catalogue upsert (20261119160000:197)" },
  "public.user_achievements": { kinds: ["inserted"], why: "achievement backfill (20261119160000)" },
};

function parseArgs(argv) {
  const options = { artifacts: null, container: null, localDb: null, evidence: null, applyAs: "postgres", withSuites: false };
  for (let index = 0; index < argv.length; index++) {
    const arg = argv[index];
    const value = () => { const next = argv[++index]; if (!next || next.startsWith("--")) throw new Error(`${arg} needs a value`); return next; };
    if (arg === "--with-suites") options.withSuites = true;
    else if (arg === "--artifacts") options.artifacts = path.resolve(value());
    else if (arg === "--container") options.container = value();
    else if (arg === "--local-db") options.localDb = value();
    else if (arg === "--evidence") options.evidence = path.resolve(value());
    else if (arg === "--apply-as") options.applyAs = value();
    else throw new Error(`Unknown argument ${arg}`);
  }
  if (!options.artifacts) throw new Error("--artifacts <dir> is required");
  if (!!options.container === !!options.localDb) throw new Error("Choose exactly one target: --container <rehearsal container> or --local-db bq_<name>");
  if (!/^[a-z_][a-z0-9_]{0,62}$/.test(options.applyAs)) throw new Error("Invalid --apply-as role");
  return options;
}

/** Refuses anything but an isolated rehearsal container or a local scratch database. */
export function resolveTarget(options, inspect = (name) => JSON.parse(execFileSync("docker", ["inspect", name], { encoding: "utf8" }))[0]) {
  if (options.localDb) {
    if (!/^bq_[a-z0-9_]{1,40}$/.test(options.localDb)) throw new Error("--local-db must be a bq_<name> scratch database (never postgres)");
    const state = inspect(LOCAL_CONTAINER);
    if (state?.State?.Running !== true) throw new Error(`${LOCAL_CONTAINER} is not running`);
    return { kind: "local", container: LOCAL_CONTAINER, database: options.localDb, psql: ["-U", "postgres", "-d", options.localDb] };
  }
  const state = inspect(options.container);
  const labels = state?.Config?.Labels ?? {};
  if (!state || state.Name !== `/${options.container}` || !options.container.startsWith("bytequest-recovery-")
      || !String(labels["bytequest.purpose"] ?? "").startsWith("hosted-recovery-")
      || state.HostConfig?.NetworkMode !== "none" || !state.HostConfig?.ReadonlyRootfs
      || Object.keys(state.HostConfig?.PortBindings ?? {}).length !== 0 || state.State?.Running !== true) {
    throw new Error("Isolated rehearsal target guard failed: expected a running bytequest-recovery-* container with network none, read-only root, no ports and a hosted-recovery label");
  }
  return { kind: "rehearsal", container: options.container, database: "postgres", psql: ["-h", SOCKET, "-U", "supabase_admin", "-d", "postgres"] };
}

function psql(target, sql, { allowError = false } = {}) {
  const run = spawnSync("docker", ["exec", "-i", "-e", "PGTZ=UTC", target.container, "psql", ...target.psql, "-X", "-q", "-A", "-t", "-v", "ON_ERROR_STOP=1"],
    { input: sql, encoding: "utf8", maxBuffer: 256 * 1024 * 1024 });
  if (run.status !== 0 && !allowError) throw new Error(`psql failed (exit ${run.status}): ${(run.stderr || run.stdout).trim().split("\n").slice(-3).join(" | ")}`);
  return { status: run.status, stdout: run.stdout ?? "", stderr: run.stderr ?? "" };
}

const sha256 = (text) => createHash("sha256").update(text).digest("hex");

/** The artifacts must be the ones generated from the current migrations. */
export function verifyArtifacts(dir) {
  const manifest = JSON.parse(fs.readFileSync(path.join(dir, "manifest.json"), "utf8"));
  const current = buildRelease({ from: manifest.from, lockTimeout: manifest.lock_timeout, statementTimeout: manifest.statement_timeout });
  if (JSON.stringify(current.manifest) !== JSON.stringify(manifest)) {
    throw new Error("The release artifacts do not match the current migrations; regenerate them with scripts/release-migration-batches.mjs");
  }
  const files = {};
  for (const [name, digest] of Object.entries(manifest.artifacts)) {
    if (digest === null) continue;
    const text = fs.readFileSync(path.join(dir, name), "utf8");
    if (sha256(text) !== digest) throw new Error(`${name} does not match its manifest digest`);
    files[name] = text;
  }
  return { manifest, files };
}

const SESSION = "set timezone = 'UTC'; set datestyle = 'ISO, YMD'; set intervalstyle = 'postgres'; set extra_float_digits = 1;";
const CAPTURE = String.raw`
${SESSION}
drop schema if exists bq_rehearsal cascade;
create schema bq_rehearsal;
create table bq_rehearsal.tables(schema_name text, table_name text, columns text[], key_columns text[], primary key (schema_name, table_name));
create table bq_rehearsal.rows(schema_name text, table_name text, row_key text, row_hash text);
do $bq_capture$
declare r record; cols text[]; keys text[]; colsql text; keysql text;
begin
  for r in select n.nspname, c.relname, c.oid from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname in ('public', 'auth', 'storage') and c.relkind in ('r', 'p') and not c.relispartition loop
    select array_agg(attname::text order by attnum) into cols from pg_attribute where attrelid = r.oid and attnum > 0 and not attisdropped;
    select array_agg(a.attname::text order by array_position(i.indkey::int2[], a.attnum)) into keys
      from pg_index i join pg_attribute a on a.attrelid = i.indrelid and a.attnum = any(i.indkey) where i.indrelid = r.oid and i.indisprimary;
    insert into bq_rehearsal.tables values (r.nspname, r.relname, cols, keys);
    colsql := (select string_agg(format('%I', c), ',') from unnest(cols) c);
    keysql := case when keys is null then format('md5(row(%s)::text)', colsql)
      else (select string_agg(format('coalesce(%I::text, %L)', k, '<null>'), ' || ''|'' || ') from unnest(keys) k) end;
    execute format('insert into bq_rehearsal.rows select %L, %L, %s, md5(row(%s)::text) from %I.%I', r.nspname, r.relname, keysql, colsql, r.nspname, r.relname);
  end loop;
end
$bq_capture$;
select count(*) from bq_rehearsal.rows;
`;
const COMPARE = String.raw`
${SESSION}
create temp table bq_now(schema_name text, table_name text, row_key text, row_hash text);
do $bq_compare$
declare r record; colsql text; keysql text;
begin
  for r in select * from bq_rehearsal.tables loop
    if to_regclass(format('%I.%I', r.schema_name, r.table_name)) is null then
      insert into bq_now values (r.schema_name, r.table_name, '<table dropped>', null); continue;
    end if;
    colsql := (select string_agg(format('%I', c), ',') from unnest(r.columns) c);
    keysql := case when r.key_columns is null then format('md5(row(%s)::text)', colsql)
      else (select string_agg(format('coalesce(%I::text, %L)', k, '<null>'), ' || ''|'' || ') from unnest(r.key_columns) k) end;
    execute format('insert into bq_now select %L, %L, %s, md5(row(%s)::text) from %I.%I', r.schema_name, r.table_name, keysql, colsql, r.schema_name, r.table_name);
  end loop;
end
$bq_compare$;
select json_build_object('table', d.relation, 'kind', d.kind, 'rows', count(*))
from (
  select coalesce(b.schema_name, a.schema_name) || '.' || coalesce(b.table_name, a.table_name) as relation,
    case when b.row_key is null then 'inserted' when a.row_key is null then 'deleted' else 'changed' end as kind
  from bq_rehearsal.rows b
  full join bq_now a on a.schema_name = b.schema_name and a.table_name = b.table_name and a.row_key = b.row_key
  where a.row_key is null or b.row_key is null or a.row_hash is distinct from b.row_hash
) d
group by d.relation, d.kind order by d.relation, d.kind;
`;

export function preservationProblems(differences) {
  return differences.filter((item) => item.kind === "deleted" || !EXPECTED_CHANGES[item.table]?.kinds.includes(item.kind));
}

export async function main(argv = process.argv.slice(2)) {
  const options = parseArgs(argv);
  const target = resolveTarget(options);
  const { manifest, files } = verifyArtifacts(options.artifacts);
  const evidence = { target: { kind: target.kind, container: target.container, database: target.database }, release: { from: manifest.from, first: manifest.first_version, last: manifest.last_version, migrations: manifest.migrations, artifacts: manifest.artifacts }, started_at: new Date().toISOString() };
  const versions = [...manifest.batch_a, ...manifest.batch_b].map((item) => item.version).sort();
  const recorded = psql(target, `select count(*) from supabase_migrations.schema_migrations where version in (${versions.map((v) => `'${v}'`).join(",")});`).stdout.trim();
  if (recorded !== "0") throw new Error(`The target already records ${recorded} release version(s); rehearse on a copy taken before the release.`);
  evidence.captured_rows = Number(psql(target, CAPTURE).stdout.trim().split("\n").at(-1));
  const role = `set role ${options.applyAs};\n`;
  for (const name of ["batch-a.sql", "batch-b.sql"]) {
    if (!files[name]) continue;
    const started = Date.now();
    const run = psql(target, role + files[name], { allowError: true });
    evidence[name] = { exit: run.status, seconds: (Date.now() - started) / 1000 };
    if (run.status !== 0) {
      evidence[name].error = (run.stderr || run.stdout).trim().split("\n").filter((line) => /ERROR|DETAIL|CONTEXT/.test(line)).slice(0, 6);
      throw Object.assign(new Error(`${name} failed on the rehearsal copy: ${evidence[name].error.join(" | ")}`), { evidence });
    }
  }
  const differences = psql(target, COMPARE).stdout.trim().split("\n").filter(Boolean).map((line) => JSON.parse(line));
  evidence.pre_existing_row_changes = differences.map((item) => ({ ...item, expected: EXPECTED_CHANGES[item.table]?.why ?? null }));
  const problems = preservationProblems(differences);
  const readback = JSON.parse(psql(target, fs.readFileSync(path.join(ROOT, "scripts", "release-readback.sql"), "utf8")).stdout.trim());
  evidence.readback = readback;
  const readbackProblems = [];
  const missing = versions.filter((version) => !readback.redefense_versions.includes(version));
  if (missing.length) readbackProblems.push(`versions not recorded: ${missing.join(", ")}`);
  if (readback.public_tables_without_rls.length) readbackProblems.push(`public tables without RLS: ${readback.public_tables_without_rls.join(", ")}`);
  if (readback.practice_contracts !== 20 || readback.coc1_m2_contract_version !== "css-assembly-20261119-v3") readbackProblems.push("practice contracts");
  if (readback.curriculum_modules !== 16 || readback.performance_criteria !== 76) readbackProblems.push("curriculum modules / performance criteria");
  if (readback.min_supported_app_version !== "1.2.0") readbackProblems.push("min_supported_app_version");
  if (!readback.scenario_essay_enum) readbackProblems.push("scenario_essay enum value");
  // The rollback suites on the migrated copy. A restored container has no
  // Auth API, so the qa.* identities come from the SQL fixture file instead
  // of scripts/local-qa-fixtures.mjs (Fixer SQL, final fix wave).
  if (options.withSuites) {
    const fixture = path.join(ROOT, "supabase", "tests", "fixtures", "qa_fixture_users.sql");
    if (!fs.existsSync(fixture)) throw Object.assign(new Error(`${path.relative(ROOT, fixture)} is missing; it comes with the SQL fix branch`), { evidence });
    psql(target, fs.readFileSync(fixture, "utf8"));
    const suites = spawnSync(process.execPath, [path.join(ROOT, "scripts", "run-local-sql-tests.mjs"),
      ...(target.kind === "rehearsal" ? ["--container", target.container] : ["--db", target.database])], { cwd: ROOT, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
    const lines = (suites.stdout ?? "").trim().split("\n");
    evidence.suites = { exit: suites.status, summary: lines.at(-1), failed: lines.filter((line) => line.startsWith("FAIL") || line.startsWith("  ")) };
    if (suites.status !== 0) readbackProblems.push(`SQL suites: ${evidence.suites.summary}`);
  }
  evidence.finished_at = new Date().toISOString();
  evidence.passed = !problems.length && !readbackProblems.length;
  if (!evidence.passed) evidence.problems = [...problems.map((item) => `${item.table}: ${item.rows} ${item.kind} pre-existing row(s) not documented`), ...readbackProblems];
  return evidence;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const write = (evidence) => {
    const file = parseArgs(process.argv.slice(2)).evidence;
    if (file) { fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, `${JSON.stringify(evidence, null, 2)}\n`); }
  };
  main().then((evidence) => {
    write(evidence);
    console.log(JSON.stringify(evidence, null, 2));
    if (!evidence.passed) process.exit(1);
  }).catch((error) => {
    if (error.evidence) write({ ...error.evidence, passed: false, failure: error.message });
    console.error(error instanceof Error ? error.message : error);
    process.exit(1);
  });
}
