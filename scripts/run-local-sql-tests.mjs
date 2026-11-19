// Runs rollback-only SQL suites against the repository's local Supabase
// database container. Usage:
//   node scripts/run-local-sql-tests.mjs            # every suite
//   node scripts/run-local-sql-tests.mjs a.sql b.sql # selected suites
// pgTAP suites report "not ok" lines; plain suites fail by raising. Every
// suite must end in ROLLBACK, so the local database is left unchanged.
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

const CONTAINER = 'supabase_db_ByteQuest';
const TEST_DIR = path.join('supabase', 'tests');
// learner_notifications_rollback.sql is appended inside the homework suite's
// transaction and reuses its temporary fixtures.
const APPENDED = { 'learner_notifications_rollback.sql': 'homework_quiz_deadlines_rollback.sql' };

const args = process.argv.slice(2);
const dbIndex = args.indexOf('--db');
const database = dbIndex >= 0 ? args.splice(dbIndex, 2)[1] : 'postgres';
if (!/^[a-z_][a-z0-9_]{0,62}$/.test(database)) throw new Error(`Invalid database name: ${database}`);
const requested = args.map((file) => path.basename(file));
const all = fs.readdirSync(TEST_DIR).filter((file) => file.endsWith('.sql')).sort();
const suites = (requested.length ? requested : all).filter((file) => !APPENDED[file]);

function body(file) {
  let sql = fs.readFileSync(path.join(TEST_DIR, file), 'utf8');
  const appended = Object.entries(APPENDED).find(([, host]) => host === file)?.[0];
  if (appended && (requested.length === 0 || requested.includes(appended))) {
    const extra = fs.readFileSync(path.join(TEST_DIR, appended), 'utf8');
    const marker = sql.lastIndexOf('rollback;');
    sql = marker >= 0 ? `${sql.slice(0, marker)}\n${extra}\n${sql.slice(marker)}` : `${sql}\n${extra}`;
  }
  return `create extension if not exists pgtap with schema extensions;\nset search_path to public, extensions;\n${sql}`;
}

let failures = 0;
for (const file of suites) {
  const run = spawnSync(
    'docker',
    ['exec', '-i', CONTAINER, 'psql', '-U', 'postgres', '-d', database, '-X', '-q', '-t', '-A', '-v', 'ON_ERROR_STOP=1'],
    { input: body(file), encoding: 'utf8' },
  );
  const output = `${run.stdout ?? ''}${run.stderr ?? ''}`;
  const passed = (output.match(/^ok \d+/gm) ?? []).length;
  const notOk = output.match(/^not ok.*$/gm) ?? [];
  const error = output.match(/^(?:psql:.*)?ERROR:.*$/m)?.[0];
  const ok = run.status === 0 && notOk.length === 0 && !error;
  if (!ok) failures += 1;
  console.log(`${ok ? 'PASS' : 'FAIL'} ${file}${passed ? ` (${passed} assertions)` : ''}`);
  for (const line of notOk) console.log(`  ${line}`);
  if (error) console.log(`  ${error.slice(0, 300)}`);
}
console.log(`${suites.length - failures}/${suites.length} suites passed`);
process.exit(failures ? 1 : 0);
