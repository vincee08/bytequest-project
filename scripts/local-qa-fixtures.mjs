// Creates (idempotently) the synthetic local QA identities that the rollback
// SQL suites and the slice tests expect on a fresh local Supabase stack:
// one admin, two instructors and three learners. Refuses any target other
// than the repository's local stack. Credentials are written only to the
// gitignored .tmp/local-qa-accounts.json file.
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { createClient } from '@supabase/supabase-js';

const LOCAL_API = 'http://127.0.0.1:57321';
const DB_CONTAINER = 'supabase_db_ByteQuest';
const ACCOUNT_FILE = path.join('.tmp', 'local-qa-accounts.json');

function localStatus() {
  const windows = process.platform === 'win32';
  const raw = execFileSync(windows ? 'supabase.cmd' : 'supabase', ['status', '-o', 'json'], {
    encoding: 'utf8',
    shell: windows,
  });
  const start = raw.indexOf('{');
  const status = JSON.parse(raw.slice(start, raw.lastIndexOf('}') + 1));
  if (status.API_URL !== LOCAL_API) {
    throw new Error(`Refusing non-local Supabase target: ${status.API_URL}`);
  }
  return status;
}

function sql(statement) {
  return execFileSync(
    'docker',
    ['exec', '-i', DB_CONTAINER, 'psql', '-U', 'postgres', '-d', 'postgres', '-X', '-t', '-A', '-v', 'ON_ERROR_STOP=1'],
    { input: statement, encoding: 'utf8' },
  ).trim();
}

const accounts = [
  { key: 'admin', email: 'qa.admin@bytequest.local', name: 'QA Admin', role: 'admin' },
  { key: 'instructor', email: 'qa.instructor@bytequest.local', name: 'QA Instructor', role: 'instructor' },
  { key: 'instructor2', email: 'qa.instructor2@bytequest.local', name: 'QA Second Instructor', role: 'instructor' },
  { key: 'learner1', email: 'qa.learner1@bytequest.local', name: 'QA Learner One', role: 'learner' },
  { key: 'learner2', email: 'qa.learner2@bytequest.local', name: 'QA Learner Two', role: 'learner' },
  { key: 'learner3', email: 'qa.learner3@bytequest.local', name: 'QA Learner Three', role: 'learner' },
];

const status = localStatus();
const service = createClient(status.API_URL, status.SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const existing = fs.existsSync(ACCOUNT_FILE) ? JSON.parse(fs.readFileSync(ACCOUNT_FILE, 'utf8')) : { accounts: {} };
const listed = await service.auth.admin.listUsers({ page: 1, perPage: 1000 });
if (listed.error) throw listed.error;

const result = { api: status.API_URL, accounts: {} };
for (const account of accounts) {
  let user = listed.data.users.find((candidate) => candidate.email === account.email);
  let password = existing.accounts?.[account.key]?.password;
  if (!user) {
    password = `Qa-${randomBytes(9).toString('base64url')}-1a`;
    const created = await service.auth.admin.createUser({
      email: account.email,
      password,
      email_confirm: true,
      user_metadata: { full_name: account.name },
    });
    if (created.error) throw created.error;
    user = created.data.user;
  } else if (!password) {
    password = `Qa-${randomBytes(9).toString('base64url')}-1a`;
    const updated = await service.auth.admin.updateUserById(user.id, { password });
    if (updated.error) throw updated.error;
  }
  sql(`update public.profiles set role='${account.role}'::public.user_role, status='active', full_name='${account.name}' where user_id='${user.id}';`);
  result.accounts[account.key] = { id: user.id, email: account.email, password, role: account.role };
}

fs.mkdirSync('.tmp', { recursive: true });
fs.writeFileSync(ACCOUNT_FILE, `${JSON.stringify(result, null, 2)}\n`);
for (const [key, account] of Object.entries(result.accounts)) {
  console.log(`${key.padEnd(12)} ${account.role.padEnd(10)} ${account.id} ${account.email}`);
}
console.log(`Credentials written to ${ACCOUNT_FILE} (gitignored).`);
