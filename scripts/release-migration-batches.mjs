// Builds the two SQL artifacts of a targeted hosted release (re-defense
// rollout plan, steps 3-4; final review SQL-A C1 / SQL-B I1):
//
//   Batch A  every migration that adds enum values (ALTER TYPE ... ADD VALUE,
//            detected from the SQL, never from file names), committed first.
//            A new enum value cannot be used in the transaction that adds it
//            (SQLSTATE 55P04), and later files use it. Batch A must contain
//            only IF NOT EXISTS enum additions, so it is idempotent and
//            harmless if it stays applied after a Batch B failure.
//   Batch B  every other migration, in timestamp order, in ONE transaction:
//            each file's own top-level BEGIN;/COMMIT; is removed (checked
//            mechanically: nothing else in the file changes), its version is
//            recorded in supabase_migrations.schema_migrations inside the same
//            transaction, and lock_timeout / statement_timeout are reset to
//            the release defaults before each file (a file's own SET LOCAL
//            then governs only that file). Any error rolls the whole batch back.
//
// The rehearsal (scripts/rehearse-release-batches.mjs) applies exactly these
// files to an isolated restored copy; production receives the same files,
// byte for byte (SHA-256 in the manifest). This script only reads the
// repository and writes the artifacts; it never connects to a database.
//
// Usage:
//   node scripts/release-migration-batches.mjs [--from 20261119100000] [--out .tmp/release-redefense]
//     [--lock-timeout 5s] [--statement-timeout 120s] [--check]
import fs from "node:fs";
import path from "node:path";
import { createHash } from "node:crypto";
import { fileURLToPath, pathToFileURL } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const MIGRATIONS = path.join(ROOT, "supabase", "migrations");
export const DEFAULTS = { from: "20261119100000", out: path.join(ROOT, ".tmp", "release-redefense"), lockTimeout: "5s", statementTimeout: "120s" };

/**
 * Top-level statements of a SQL script with their exact source spans.
 * Understands quotes, dollar quotes, line and nested block comments, so a
 * semicolon or BEGIN inside a function body is never a statement boundary.
 */
export function splitTopLevel(sql) {
  const statements = [];
  let start = 0;
  let index = 0;
  const push = (end) => {
    const text = sql.slice(start, end);
    if (stripComments(text).trim()) statements.push({ start, end, text });
    start = end;
  };
  while (index < sql.length) {
    const char = sql[index];
    const next = sql[index + 1];
    if (char === "-" && next === "-") { const eol = sql.indexOf("\n", index); index = eol < 0 ? sql.length : eol + 1; continue; }
    if (char === "/" && next === "*") {
      let depth = 1; index += 2;
      while (index < sql.length && depth) {
        if (sql[index] === "/" && sql[index + 1] === "*") { depth += 1; index += 2; } else if (sql[index] === "*" && sql[index + 1] === "/") { depth -= 1; index += 2; } else index += 1;
      }
      continue;
    }
    if (char === "'" || char === '"') {
      const escaped = char === "'" && /[eE]/.test(sql[index - 1] ?? "") && !/[A-Za-z0-9_]/.test(sql[index - 2] ?? "");
      index += 1;
      while (index < sql.length) {
        if (escaped && sql[index] === "\\") { index += 2; continue; }
        if (sql[index] === char) { if (sql[index + 1] === char) { index += 2; continue; } index += 1; break; }
        index += 1;
      }
      continue;
    }
    if (char === "$") {
      const tag = sql.slice(index).match(/^\$([A-Za-z_][A-Za-z0-9_]*)?\$/);
      if (tag && !/[A-Za-z0-9_]/.test(sql[index - 1] ?? "")) {
        const close = sql.indexOf(tag[0], index + tag[0].length);
        if (close < 0) throw new Error(`Unterminated dollar quote ${tag[0]}`);
        index = close + tag[0].length;
        continue;
      }
    }
    if (char === ";") { push(index + 1); index += 1; continue; }
    index += 1;
  }
  if (stripComments(sql.slice(start)).trim()) statements.push({ start, end: sql.length, text: sql.slice(start), unterminated: true });
  return statements;
}

/** Statement text without comments, whitespace-normalised, lower case (classification only). */
export function stripComments(text) {
  return text.replace(/--[^\n]*/g, " ").replace(/\/\*[\s\S]*?\*\//g, " ");
}
const normal = (statement) => stripComments(statement.text).replace(/\s+/g, " ").trim().toLowerCase();

export function classify(statement) {
  const sql = normal(statement);
  if (/^(begin|start transaction)( (work|transaction))?( isolation level [a-z ]+)?;?$/.test(sql)) return "begin";
  if (/^(commit|end)( (work|transaction))?;?$/.test(sql)) return "commit";
  if (/^(rollback|abort|savepoint|release|prepare transaction|commit prepared|rollback prepared)\b/.test(sql)) return "transaction_control";
  if (/^alter type [^;]+ add value\b/.test(sql)) return "enum_add_value";
  if (/\bconcurrently\b/.test(sql) && /^(create|drop|reindex|refresh)\b/.test(sql)) return "no_transaction";
  if (/^(vacuum|create database|drop database|alter system|create tablespace|drop tablespace)\b/.test(sql)) return "no_transaction";
  return "statement";
}

/** One migration file: version, name, stripped body and its batch. */
export function inspectMigration(file, sql) {
  const match = file.match(/^(\d{14})_([a-z0-9_]+)\.sql$/);
  if (!match) throw new Error(`${file}: not a <version>_<name>.sql migration`);
  const statements = splitTopLevel(sql);
  const kinds = statements.map(classify);
  const problems = [];
  if (statements.some((statement) => statement.unterminated)) problems.push("ends with an unterminated statement");
  if (kinds[0] !== "begin" || kinds.filter((kind) => kind === "begin").length !== 1) problems.push("must start with its only top-level BEGIN;");
  if (kinds.at(-1) !== "commit" || kinds.filter((kind) => kind === "commit").length !== 1) problems.push("must end with its only top-level COMMIT;");
  if (kinds.includes("transaction_control")) problems.push("contains other transaction control (ROLLBACK, SAVEPOINT, ...)");
  if (kinds.includes("no_transaction")) problems.push("contains a statement that cannot run in a transaction (CONCURRENTLY, VACUUM, ...)");
  const enumAdds = statements.filter((_, index) => kinds[index] === "enum_add_value");
  const batch = enumAdds.length ? "A" : "B";
  if (batch === "A") {
    const others = kinds.filter((kind) => !["begin", "commit", "enum_add_value"].includes(kind) && kind !== "statement");
    const plain = statements.filter((statement, index) => kinds[index] === "statement" && !/^set (local )?(lock_timeout|statement_timeout)\b/.test(normal(statement)));
    if (others.length || plain.length) problems.push("adds enum values and also does other work; split the enum additions into their own migration");
    if (enumAdds.some((statement) => !/ add value if not exists /.test(normal(statement)))) problems.push("adds an enum value without IF NOT EXISTS (Batch A must be idempotent)");
  }
  if (problems.length) throw new Error(`${file}: ${problems.join("; ")}`);
  const first = statements[0];
  const last = statements.at(-1);
  // Remove exactly the BEGIN; and COMMIT; spans; everything else is kept byte for byte.
  const body = sql.slice(0, first.start) + sql.slice(first.end, last.start) + sql.slice(last.end);
  const check = splitTopLevel(body).map((statement) => statement.text.trim());
  const expected = statements.slice(1, -1).map((statement) => statement.text.trim());
  if (JSON.stringify(check) !== JSON.stringify(expected)) throw new Error(`${file}: stripping BEGIN/COMMIT changed other statements`);
  return { file, version: match[1], name: match[2], batch, body, sha256: sha256(sql), statements: statements.length - 2 };
}

const sha256 = (text) => createHash("sha256").update(text).digest("hex");
const literal = (text) => `'${text.replaceAll("'", "''")}'`;
const versionList = (items) => items.map((item) => literal(item.version)).join(", ");
// The version row names the exact source (LF-normalised SHA-256) instead of
// repeating the body, which keeps the request sent to the Management API small.
const record = (item, conflict) => `insert into supabase_migrations.schema_migrations(version, name, statements)\n  values (${literal(item.version)}, ${literal(item.name)}, array[${literal(`-- applied by ByteQuest release batch ${item.batch}: ${item.file} sha256 ${item.sha256}`)}])${conflict ? "\n  on conflict (version) do nothing" : ""};`;
const timeouts = (options) => `set local lock_timeout = ${literal(options.lockTimeout)};\nset local statement_timeout = ${literal(options.statementTimeout)};`;

export function renderBatchA(items, options) {
  if (!items.length) return null;
  return [
    `-- ByteQuest release Batch A (${items.length} enum migration${items.length === 1 ? "" : "s"}). Generated by scripts/release-migration-batches.mjs; do not edit.`,
    "-- Idempotent: every statement is ADD VALUE IF NOT EXISTS and the version rows use ON CONFLICT DO NOTHING.",
    "begin;",
    timeouts(options),
    ...items.flatMap((item) => [`-- >>> ${item.file} (sha256 ${item.sha256})`, item.body.trim(), record(item, true)]),
    "commit;",
    "",
  ].join("\n");
}

export function renderBatchB(items, batchA, options) {
  const guard = [
    "do $bq_release_guard$",
    "begin",
    ...(batchA.length ? [`  if (select count(*) from supabase_migrations.schema_migrations where version in (${versionList(batchA)})) <> ${batchA.length} then`,
      "    raise exception 'RELEASE_BATCH_A_NOT_APPLIED: apply Batch A first';", "  end if;"] : []),
    `  if exists (select 1 from supabase_migrations.schema_migrations where version in (${versionList(items)})) then`,
    "    raise exception 'RELEASE_BATCH_B_ALREADY_APPLIED: a Batch B version is already recorded';",
    "  end if;",
    "end",
    "$bq_release_guard$;",
  ];
  const verify = [
    "do $bq_release_verify$",
    "begin",
    `  if (select count(*) from supabase_migrations.schema_migrations where version in (${versionList([...batchA, ...items])})) <> ${batchA.length + items.length} then`,
    "    raise exception 'RELEASE_VERSIONS_NOT_RECORDED';",
    "  end if;",
    "end",
    "$bq_release_verify$;",
  ];
  return [
    `-- ByteQuest release Batch B (${items.length} migrations in one transaction). Generated by scripts/release-migration-batches.mjs; do not edit.`,
    "-- Any error rolls every file back; Batch A stays applied and harmless.",
    "begin;",
    timeouts(options),
    ...guard,
    ...items.flatMap((item) => [`-- >>> ${item.file} (sha256 ${item.sha256})`, timeouts(options), item.body.trim(), record(item, false)]),
    ...verify,
    "commit;",
    "",
  ].join("\n");
}

export function buildRelease({ from = DEFAULTS.from, lockTimeout = DEFAULTS.lockTimeout, statementTimeout = DEFAULTS.statementTimeout, files } = {}) {
  if (!/^\d{14}$/.test(from)) throw new Error("--from must be a 14-digit migration version");
  for (const value of [lockTimeout, statementTimeout]) if (!/^\d+(ms|s|min)$/.test(value)) throw new Error(`Invalid timeout ${value}`);
  const options = { lockTimeout, statementTimeout };
  // LF-normalised, so a Windows (CRLF) checkout produces the same artifacts
  // and digests as the Git blobs.
  const sources = files ?? fs.readdirSync(MIGRATIONS).filter((file) => file.endsWith(".sql")).sort()
    .map((file) => ({ file, sql: fs.readFileSync(path.join(MIGRATIONS, file), "utf8").replace(/\r\n/g, "\n") }));
  const items = sources.filter(({ file }) => file.slice(0, 14) >= from).map(({ file, sql }) => inspectMigration(file, sql));
  if (!items.length) throw new Error(`No migration at or after ${from}`);
  const versions = new Set();
  for (const item of items) { if (versions.has(item.version)) throw new Error(`Duplicate version ${item.version}`); versions.add(item.version); }
  const batchA = items.filter((item) => item.batch === "A");
  const batchB = items.filter((item) => item.batch === "B");
  const a = renderBatchA(batchA, options);
  const b = renderBatchB(batchB, batchA, options);
  return {
    from, options, batchA, batchB, sql: { a, b },
    manifest: {
      generated_by: "scripts/release-migration-batches.mjs",
      from, lock_timeout: lockTimeout, statement_timeout: statementTimeout,
      first_version: items[0].version, last_version: items.at(-1).version, migrations: items.length,
      batch_a: batchA.map(({ file, version, sha256: digest }) => ({ file, version, sha256: digest })),
      batch_b: batchB.map(({ file, version, sha256: digest }) => ({ file, version, sha256: digest })),
      artifacts: { "batch-a.sql": a ? sha256(a) : null, "batch-b.sql": sha256(b) },
    },
  };
}

export function writeRelease(release, out) {
  fs.mkdirSync(out, { recursive: true });
  for (const name of ["batch-a.sql", "batch-b.sql"]) fs.rmSync(path.join(out, name), { force: true });
  if (release.sql.a) fs.writeFileSync(path.join(out, "batch-a.sql"), release.sql.a);
  fs.writeFileSync(path.join(out, "batch-b.sql"), release.sql.b);
  fs.writeFileSync(path.join(out, "manifest.json"), `${JSON.stringify(release.manifest, null, 2)}\n`);
}

function parseArgs(argv) {
  const options = { ...DEFAULTS, check: false };
  for (let index = 0; index < argv.length; index++) {
    const arg = argv[index];
    const value = () => { const next = argv[++index]; if (!next) throw new Error(`${arg} needs a value`); return next; };
    if (arg === "--from") options.from = value();
    else if (arg === "--out") options.out = path.resolve(value());
    else if (arg === "--lock-timeout") options.lockTimeout = value();
    else if (arg === "--statement-timeout") options.statementTimeout = value();
    else if (arg === "--check") options.check = true;
    else throw new Error(`Unknown argument ${arg}`);
  }
  return options;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const options = parseArgs(process.argv.slice(2));
    const release = buildRelease(options);
    if (!options.check) writeRelease(release, options.out);
    console.log(JSON.stringify({ status: options.check ? "CHECKED" : "WRITTEN", out: options.check ? null : options.out, ...release.manifest }, null, 2));
  } catch (error) {
    console.error(error instanceof Error ? error.message : error);
    process.exit(1);
  }
}
