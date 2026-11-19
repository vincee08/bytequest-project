// Creates (or recreates) an isolated copy of the local Supabase database inside
// the same container, so parallel workstreams can apply and test migrations
// without affecting each other. Usage: node scripts/clone-local-db.mjs bq_a1
// The copy includes the auth/storage schemas and all applied migrations; the
// cluster-wide roles (authenticated, service_role, ...) are shared.
import { execFileSync } from 'node:child_process';

const CONTAINER = 'supabase_db_ByteQuest';
const name = process.argv[2];
if (!name || !/^bq_[a-z0-9_]{1,40}$/.test(name)) {
  console.error('Usage: node scripts/clone-local-db.mjs bq_<name>  (lowercase letters, digits, underscores)');
  process.exit(2);
}

function sh(command) {
  return execFileSync('docker', ['exec', CONTAINER, 'bash', '-lc', command], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
}

sh(`psql -U postgres -d postgres -X -q -c "select pg_terminate_backend(pid) from pg_stat_activity where datname='${name}';" >/dev/null`);
sh(`dropdb -U postgres --if-exists ${name}`);
sh(`createdb -U postgres ${name}`);
// Full logical copy (schema + data) preserves grants, policies and seed rows.
sh(`pg_dump -U postgres -d postgres --no-owner | psql -U postgres -d ${name} -X -q -v ON_ERROR_STOP=0 >/tmp/${name}.restore.log 2>&1 || true`);
const check = sh(`psql -U postgres -d ${name} -X -t -A -c "select count(*) from public.curriculum_modules;"`).trim();
console.log(`Database ${name} ready (curriculum_modules=${check}).`);
