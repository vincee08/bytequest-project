// Creates a fresh ENCRYPTED, READ-ONLY logical backup of the ByteQuest hosted
// database (project rslmteqipxqfifwftugk only) in the recovery format that
// scripts/rehearse-production-release.mjs restores:
//   archive-key.dpapi            AES-256 key, Windows DPAPI CurrentUser
//   database-full-readonly.dump.bqenc   pg_dump custom format, whole database
//   roles.sql.bqenc              pg_dumpall --roles-only --no-role-passwords
//   snapshot-digests.json.bqenc  per-relation row counts + content hashes
//   backup-manifest.json         SHA-256 of every archive, recovery_verified:false
//
// Safety:
// - Never writes to the hosted database: a temporary login role is requested
//   with read_only:true from the official Management API (TTL 300 s), and every
//   session runs SET ROLE supabase_read_only_user inside READ ONLY transactions.
// - Dump, roles and digests come from ONE exported snapshot.
// - Plaintext is streamed from the client container straight into AES-256-GCM;
//   no plaintext dump, password or token is written to disk or printed.
// - TLS verify-full against the official Supabase Root 2021 CA (--ca=<file>).
// - Refuses any project other than rslmteqipxqfifwftugk and any directory
//   outside %LOCALAPPDATA%\ByteQuest\Recovery (enforced by recovery-archive.mjs).
//
// Usage (PowerShell or Git Bash, from the repository root):
//   node scripts/create-production-backup.mjs --confirm-read-only-backup \
//     "--backup-dir=%LOCALAPPDATA%\ByteQuest\Recovery\rslmteqipxqfifwftugk-<date>-redefense" \
//     --ca=<path to prod-ca-2021.crt>
import { execFileSync, spawn } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, writeFileSync, realpathSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { randomBytes, createHash } from 'node:crypto';
import { Readable, PassThrough } from 'node:stream';
import { ref, dir, docker, dpapi, encrypt, verifyArchive, digestQuery } from './lib/recovery-archive.mjs';

const image = 'sha256:6942962433a569e87f228b4d4ab7e11db5deca64e43babb3a038443ad6c4f1bb'; // supabase/postgres 17.6.1.167 (same as the restore target)
const ps = 'C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe';
const arg = (name) => process.argv.find((a) => a.startsWith(`--${name}=`))?.slice(name.length + 3);

if (!process.argv.includes('--confirm-read-only-backup')) throw new Error('Pass --confirm-read-only-backup to create a read-only backup of the hosted ByteQuest database.');
const linked = readFileSync('supabase/.temp/project-ref', 'utf8').trim();
if (linked !== ref) throw new Error(`Linked project ${linked} is not ByteQuest ${ref}; refusing.`);
if (!arg('ca') || !existsSync(resolve(arg('ca')))) throw new Error('Pass --ca=<Supabase Root 2021 CA PEM file>.');
const caFile = realpathSync.native(resolve(arg('ca')));
if (!readFileSync(caFile, 'utf8').includes('BEGIN CERTIFICATE')) throw new Error('The --ca file is not a PEM certificate.');
const pooler = new URL(readFileSync('supabase/.temp/pooler-url', 'utf8').trim());
if (!/\.pooler\.supabase\.com$/.test(pooler.hostname) || pooler.port !== '5432' || pooler.username !== `postgres.${ref}`) throw new Error('Unexpected pooler URL for ByteQuest; refusing.');
if (existsSync(dir)) throw new Error(`Backup directory already exists: ${dir}`);

/** Reads the Supabase CLI access token from Windows Credential Manager (never printed). */
function cliAccessToken() {
  const script = `
$ErrorActionPreference='Stop'
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class BqCred {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct CREDENTIAL {
    public int Flags; public int Type; public string TargetName; public string Comment;
    public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten; public int CredentialBlobSize;
    public IntPtr CredentialBlob; public int Persist; public int AttributeCount; public IntPtr Attributes;
    public string TargetAlias; public string UserName; }
  [DllImport("advapi32.dll", EntryPoint="CredReadW", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern bool CredRead(string target, int type, int flags, out IntPtr cred);
  [DllImport("advapi32.dll")] public static extern void CredFree(IntPtr cred);
  public static string Read(string target) {
    IntPtr p; if (!CredRead(target, 1, 0, out p)) return null;
    try { var c = (CREDENTIAL)Marshal.PtrToStructure(p, typeof(CREDENTIAL));
      var b = new byte[c.CredentialBlobSize]; Marshal.Copy(c.CredentialBlob, b, 0, b.Length);
      return Convert.ToBase64String(b); } finally { CredFree(p); } }
}
'@
$v=[BqCred]::Read('Supabase CLI:supabase'); if (-not $v) { throw 'no Supabase CLI credential' }; [Console]::Out.Write($v)`;
  // -EncodedCommand keeps the multi-line script intact (stdin command mode does not parse here-strings reliably).
  const encoded = Buffer.from(script, 'utf16le').toString('base64');
  const out = execFileSync(ps, ['-NoProfile', '-NonInteractive', '-EncodedCommand', encoded], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
  if (!/^[A-Za-z0-9+/=]+$/.test(out)) throw new Error('Could not read the Supabase CLI credential.');
  const blob = Buffer.from(out, 'base64');
  let text = blob.toString('utf8');
  if (/\u0000/.test(text)) text = blob.toString('utf16le');
  if (text.startsWith('go-keyring-base64:')) text = Buffer.from(text.slice('go-keyring-base64:'.length), 'base64').toString('utf8');
  text = text.trim();
  if (!/^sbp_[A-Za-z0-9_]{20,}$/.test(text)) throw new Error('The Supabase CLI credential is not a personal access token; run supabase login.');
  return text;
}

async function readOnlyLoginRole(token) {
  const response = await fetch(`https://api.supabase.com/v1/projects/${ref}/cli/login-role`, {
    method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ read_only: true }),
  });
  if (!response.ok) throw new Error(`Login-role request failed: HTTP ${response.status}`);
  const body = await response.json();
  if (!body.role || !body.password || body.role !== 'cli_login_supabase_read_only_user') throw new Error(`Unexpected login role ${body.role ?? '(none)'}; refusing.`);
  return body;
}

function run(args, input) {
  return execFileSync(docker, args, { input, encoding: 'utf8', stdio: [input ? 'pipe' : 'ignore', 'pipe', 'pipe'] }).trim();
}

/** Streams a client command's stdout (inside the container) into an encrypted archive. */
function execStream(container, env, command) {
  const child = spawn(docker, ['exec', '-i', ...env.flatMap((e) => ['-e', e]), container, 'sh', '-c', command], { stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true });
  const err = [];
  child.stderr.on('data', (b) => err.push(b));
  const done = new Promise((res, rej) => { child.on('error', rej); child.on('close', (code) => code === 0 ? res() : rej(new Error(`${command.split(' ')[0]} failed (exit ${code}): ${Buffer.concat(err).toString('utf8').replace(/password[^\s]*/gi, '***').slice(0, 400)}`))); });
  return { stream: child.stdout, done };
}

async function collect(stream) { const parts = []; for await (const p of stream) parts.push(p); return Buffer.concat(parts); }

const container = `bytequest-backup-client-${Date.now()}`;
const evidence = { ref, created_at: new Date().toISOString(), container, image, pooler_host: pooler.hostname, tls: 'verify-full (Supabase Root 2021 CA)' };
let key;
try {
  mkdirSync(dirname(dir), { recursive: true });
  mkdirSync(dir, { recursive: false });
  // Owner-only directory: no inherited ACEs; only this Windows user and SYSTEM.
  execFileSync('icacls', [dir, '/inheritance:r', '/grant:r', `${process.env.USERNAME}:(OI)(CI)F`, 'SYSTEM:(OI)(CI)F'], { stdio: 'pipe' });
  key = randomBytes(32);
  writeFileSync(join(dir, 'archive-key.dpapi'), dpapi('wrap', key), { flag: 'wx' });
  if (!dpapi('unwrap', readFileSync(join(dir, 'archive-key.dpapi'))).equals(key)) throw new Error('DPAPI key round-trip failed');

  const token = cliAccessToken();
  const login = await readOnlyLoginRole(token);
  evidence.login_role = { role: login.role, read_only: true, ttl_seconds: login.ttl_seconds };
  const conn = `host=${pooler.hostname} port=5432 dbname=postgres user=${login.role}.${ref} sslmode=verify-full sslrootcert=/bq-ca/root.crt application_name=bytequest-readonly-backup`;
  const env = [`PGPASSWORD=${login.password}`, `BQ_CONN=${conn}`];

  // Client toolbox container: read-only root, tmpfs /tmp, CA mounted read-only, outbound network only.
  run(['run', '-d', '--rm', '--name', container, '--read-only', '--tmpfs', '/tmp:rw,size=16m', '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges',
    '-v', `${caFile}:/bq-ca/root.crt:ro`, '--entrypoint', 'sh', image, '-c', 'sleep 900']);

  // 1. Hold one READ ONLY snapshot open and export it.
  const holder = spawn(docker, ['exec', '-i', ...env.flatMap((e) => ['-e', e]), container, 'sh', '-c',
    'psql "$BQ_CONN" -X -q -A -t -v ON_ERROR_STOP=1'], { stdio: ['pipe', 'pipe', 'pipe'], windowsHide: true });
  const holderOut = []; holder.stdout.on('data', (b) => holderOut.push(b));
  const holderErr = []; holder.stderr.on('data', (b) => holderErr.push(b));
  holder.stdin.write('SET ROLE supabase_read_only_user;\nBEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;\nSELECT pg_export_snapshot();\n');
  let snapshot = '';
  for (let i = 0; i < 60 && !snapshot; i++) {
    await new Promise((r) => setTimeout(r, 500));
    snapshot = Buffer.concat(holderOut).toString('utf8').split(/\r?\n/).map((s) => s.trim()).find((s) => /^[0-9A-F]+-[0-9A-F]+-[0-9]+$/i.test(s)) ?? '';
    if (holder.exitCode !== null) break;
  }
  if (!snapshot) throw new Error(`Could not export a read-only snapshot: ${Buffer.concat(holderErr).toString('utf8').slice(0, 300)}`);
  evidence.snapshot = snapshot;

  // 2. Whole-database custom-format dump in that snapshot.
  const dump = execStream(container, env, `pg_dump "$BQ_CONN" --role=supabase_read_only_user --snapshot=${snapshot} --format=custom --compress=6`);
  const dumpArchive = await encrypt(dump.stream, 'database-full-readonly.dump.bqenc', key);
  await dump.done;

  // 3. Per-relation counts + content hashes, same snapshot.
  const digestSql = `SET ROLE supabase_read_only_user;\nBEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;\nSET TRANSACTION SNAPSHOT '${snapshot}';\n${digestQuery}\nROLLBACK;\n`;
  const digestProc = spawn(docker, ['exec', '-i', ...env.flatMap((e) => ['-e', e]), container, 'sh', '-c', 'psql "$BQ_CONN" -X -q -A -t -v ON_ERROR_STOP=1'], { stdio: ['pipe', 'pipe', 'pipe'], windowsHide: true });
  const digestErr = []; digestProc.stderr.on('data', (b) => digestErr.push(b));
  digestProc.stdin.end(digestSql);
  const digestOut = await collect(digestProc.stdout);
  const digestCode = await new Promise((r) => digestProc.on('close', r));
  if (digestCode !== 0) throw new Error(`Digest query failed: ${Buffer.concat(digestErr).toString('utf8').slice(0, 300)}`);
  const relations = digestOut.toString('utf8').split(/\r?\n/).filter((s) => s.startsWith('{')).map((s) => JSON.parse(s));
  if (relations.length < 50) throw new Error(`Only ${relations.length} relations digested; refusing an incomplete snapshot.`);
  const digestArchive = await encrypt(Readable.from([JSON.stringify({ ref, snapshot, relations })]), 'snapshot-digests.json.bqenc', key);

  // 4. Roles and memberships without passwords.
  const roles = execStream(container, env, 'pg_dumpall --dbname="$BQ_CONN" --roles-only --no-role-passwords');
  const rolesSql = await collect(roles.stream);
  await roles.done;
  if ((rolesSql.toString('utf8').match(/^CREATE ROLE supabase_admin;$/gm) ?? []).length !== 1) throw new Error('Roles dump lacks the supabase_admin bootstrap role');
  const rolesArchive = await encrypt(Readable.from([rolesSql]), 'roles.sql.bqenc', key);
  rolesSql.fill(0);

  // 5. Release the snapshot holder.
  holder.stdin.end('ROLLBACK;\n');
  await new Promise((r) => holder.on('close', r));

  const archives = [dumpArchive, rolesArchive, digestArchive];
  for (const archive of archives) await verifyArchive(archive, key); // SHA-256 + full AES-GCM authentication
  const index = new Map(relations.map((r) => [`${r.schema}.${r.relation}`, r]));
  const count = (name) => Number(index.get(name)?.rows ?? -1);
  evidence.relations = relations.length;
  evidence.rows = relations.reduce((total, r) => total + Number(r.rows), 0);
  evidence.key_counts = Object.fromEntries(['public.profiles', 'public.classes', 'public.attempts', 'public.practice_mission_actions', 'public.practice_mission_completions',
    'public.quiz_attempts', 'public.quiz_results', 'public.homework_submissions', 'public.user_achievements', 'public.audit_events', 'auth.users',
    'supabase_migrations.schema_migrations'].map((n) => [n, count(n)]));
  const manifest = { ref, recovery_verified: false, created_at: evidence.created_at, snapshot, format: 'BQBK0001 AES-256-GCM, DPAPI CurrentUser key',
    source: { pooler_host: pooler.hostname, login_role: login.role, read_only: true }, archives,
    tool_sha256: createHash('sha256').update(readFileSync(new URL(import.meta.url))).digest('hex') };
  writeFileSync(join(dir, 'backup-manifest.json'), JSON.stringify(manifest, null, 2), { flag: 'wx' });
  writeFileSync(join(dir, 'backup-evidence.json'), JSON.stringify(evidence, null, 2), { flag: 'wx' });
  console.log(JSON.stringify({ stage: 'backup_created_and_verified', dir, relations: evidence.relations, rows: evidence.rows, archives: archives.map((a) => ({ file: a.filename, bytes: a.encrypted_bytes, sha256: a.sha256 })), key_counts: evidence.key_counts }, null, 1));
} catch (error) {
  console.error(`BACKUP FAILED: ${error.message}`);
  process.exitCode = 1;
} finally {
  try { execFileSync(docker, ['rm', '-f', container], { stdio: 'pipe' }); } catch {}
  key?.fill(0);
}
