// Runs rollback-only SQL suites against the repository's local Supabase
// database container, or against an isolated rehearsal container. Usage:
//   node scripts/run-local-sql-tests.mjs                    # every suite, local main database
//   node scripts/run-local-sql-tests.mjs a.sql b.sql        # selected suites
//   node scripts/run-local-sql-tests.mjs --db bq_clone      # a local clone database
//   node scripts/run-local-sql-tests.mjs --container bytequest-recovery-<release>-<n>
//                                        # a restored-production rehearsal container
//                                        # (network none, read-only root, no ports)
// pgTAP suites report "not ok" lines; plain suites fail by raising. A pgTAP
// suite also fails when it ran fewer assertions than it planned. Every suite
// must end in ROLLBACK, so the target database is left unchanged.
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync, spawnSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

const LOCAL_CONTAINER = 'supabase_db_ByteQuest';
const TEST_DIR = path.join('supabase', 'tests');
// learner_notifications_rollback.sql is appended inside the homework suite's
// transaction and reuses its temporary fixtures.
const APPENDED = { 'learner_notifications_rollback.sql': 'homework_quiz_deadlines_rollback.sql' };

/** The psql target: the local stack, or a guarded isolated rehearsal container. */
export function resolveTarget({ container, database }, inspect = (name) => JSON.parse(execFileSync('docker', ['inspect', name], { encoding: 'utf8' }))[0]) {
  if (!/^[a-z_][a-z0-9_]{0,62}$/.test(database)) throw new Error(`Invalid database name: ${database}`);
  if (!container || container === LOCAL_CONTAINER) return { container: LOCAL_CONTAINER, psql: ['-U', 'postgres', '-d', database] };
  const state = inspect(container);
  const labels = state?.Config?.Labels ?? {};
  if (!state || state.Name !== `/${container}` || !container.startsWith('bytequest-recovery-')
      || !String(labels['bytequest.purpose'] ?? '').startsWith('hosted-recovery-')
      || state.HostConfig?.NetworkMode !== 'none' || !state.HostConfig?.ReadonlyRootfs
      || Object.keys(state.HostConfig?.PortBindings ?? {}).length !== 0) {
    throw new Error('Refusing the container: only the local stack or an isolated bytequest-recovery-* rehearsal container (network none, read-only root, no ports) is a valid target');
  }
  return { container, psql: ['-h', '/bq-recovery', '-U', 'supabase_admin', '-d', database] };
}

/** Pass/fail of one suite's psql output (exported for tests). */
export function suiteOutcome(output, status) {
  const passed = (output.match(/^ok \d+/gm) ?? []).length;
  const notOk = output.match(/^not ok.*$/gm) ?? [];
  const error = output.match(/^(?:psql:.*)?ERROR:.*$/m)?.[0];
  const planned = Number(output.match(/^1\.\.(\d+)$/m)?.[1] ?? NaN);
  // A data-dependent assertion that matched no rows must not pass silently.
  const planMismatch = /# Looks like you planned/.test(output) || (Number.isFinite(planned) && planned !== passed + notOk.length);
  return { ok: status === 0 && notOk.length === 0 && !error && !planMismatch, passed, notOk, error, planned, planMismatch };
}

function body(file, requested) {
  let sql = fs.readFileSync(path.join(TEST_DIR, file), 'utf8');
  const appended = Object.entries(APPENDED).find(([, host]) => host === file)?.[0];
  if (appended && (requested.length === 0 || requested.includes(appended))) {
    const extra = fs.readFileSync(path.join(TEST_DIR, appended), 'utf8');
    const marker = sql.lastIndexOf('rollback;');
    sql = marker >= 0 ? `${sql.slice(0, marker)}\n${extra}\n${sql.slice(marker)}` : `${sql}\n${extra}`;
  }
  return `create extension if not exists pgtap with schema extensions;\nset search_path to public, extensions;\n${sql}`;
}

function main() {
  const args = process.argv.slice(2);
  const take = (flag, fallback) => { const index = args.indexOf(flag); return index >= 0 ? args.splice(index, 2)[1] : fallback; };
  const database = take('--db', 'postgres');
  const container = take('--container', null);
  const target = resolveTarget({ container, database });
  const requested = args.map((file) => path.basename(file));
  const all = fs.readdirSync(TEST_DIR).filter((file) => file.endsWith('.sql')).sort();
  const suites = (requested.length ? requested : all).filter((file) => !APPENDED[file]);
  let failures = 0;
  for (const file of suites) {
    const run = spawnSync('docker', ['exec', '-i', target.container, 'psql', ...target.psql, '-X', '-q', '-t', '-A', '-v', 'ON_ERROR_STOP=1'],
      { input: body(file, requested), encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
    const outcome = suiteOutcome(`${run.stdout ?? ''}${run.stderr ?? ''}`, run.status);
    if (!outcome.ok) failures += 1;
    console.log(`${outcome.ok ? 'PASS' : 'FAIL'} ${file}${outcome.passed ? ` (${outcome.passed} assertions)` : ''}`);
    for (const line of outcome.notOk) console.log(`  ${line}`);
    if (outcome.planMismatch) console.log(`  planned ${outcome.planned} assertions, ran ${outcome.passed + outcome.notOk.length}`);
    if (outcome.error) console.log(`  ${outcome.error.slice(0, 300)}`);
  }
  console.log(`${suites.length - failures}/${suites.length} suites passed`);
  process.exit(failures ? 1 : 0);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main();
