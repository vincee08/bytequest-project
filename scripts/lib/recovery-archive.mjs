// Existing encrypted backup format. Never writes plaintext dumps to disk.
// This module performs no network operation or production database connection.
import { execFileSync } from 'node:child_process';
import { createReadStream, createWriteStream, statSync, openSync, readSync, closeSync } from 'node:fs';
import { join, resolve, relative, isAbsolute } from 'node:path';
import { randomBytes, createCipheriv, createDecipheriv, createHash } from 'node:crypto';
import { Writable } from 'node:stream';
import { pipeline } from 'node:stream/promises';

export const ref = 'rslmteqipxqfifwftugk';
const recoveryRoot = resolve(process.env.LOCALAPPDATA, 'ByteQuest', 'Recovery');
const requestedDirectory = process.argv.find(a => a.startsWith('--backup-dir='))?.slice('--backup-dir='.length);
export const dir = resolve(requestedDirectory ?? join(recoveryRoot, `${ref}-20261113`));
const withinRoot = relative(recoveryRoot, dir);
if (!withinRoot || withinRoot.startsWith('..') || isAbsolute(withinRoot)) throw Error('Use a project backup subdirectory inside the private ByteQuest Recovery directory.');
export const docker = 'C:/Program Files/Docker/Docker/resources/bin/docker.exe';
const ps = 'C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe';
const header = Buffer.from('BQBK0001');
export function dpapi(mode, input) {
  return Buffer.from(execFileSync(ps, ['-NoProfile', '-File', 'scripts/recovery-dpapi.ps1', '-Mode', mode], {
    input: input.toString('base64') + '\n', encoding: 'utf8',
  }).trim(), 'base64');
}
export async function encrypt(input, filename, key) {
  const path = join(dir, filename), iv = randomBytes(12);
  const output = createWriteStream(path, { flags: 'wx' });
  output.write(header); output.write(iv);
  const cipher = createCipheriv('aes-256-gcm', key, iv);
  await pipeline(input, cipher, output, { end: false });
  await new Promise((resolve, reject) => output.end(cipher.getAuthTag(), e => e ? reject(e) : resolve()));
  return { filename, encrypted_bytes: statSync(path).size, sha256: await sha256(path) };
}
export async function sha256(path) {
  const hash = createHash('sha256');
  for await (const chunk of createReadStream(path)) hash.update(chunk);
  return hash.digest('hex');
}
export function decrypt(filename, key) {
  const path = join(dir, filename), size = statSync(path).size;
  if (size < 36) throw new Error('Encrypted archive too short');
  const fd = openSync(path, 'r'), prefix = Buffer.alloc(20), tag = Buffer.alloc(16);
  try { readSync(fd, prefix, 0, 20, 0); readSync(fd, tag, 0, 16, size - 16); } finally { closeSync(fd); }
  if (!prefix.subarray(0, 8).equals(header)) throw new Error('Archive format mismatch');
  const decipher = createDecipheriv('aes-256-gcm', key, prefix.subarray(8));
  decipher.setAuthTag(tag);
  const source = createReadStream(path, { start: 20, end: size - 17 });
  source.on('error', e => decipher.destroy(e));
  return source.pipe(decipher);
}
export async function verifyArchive(entry, key) {
  if (await sha256(join(dir, entry.filename)) !== entry.sha256) throw new Error('Encrypted archive SHA mismatch');
  await pipeline(decrypt(entry.filename, key), new Writable({ write(chunk, encoding, done) { done(); } }));
}
const digestQuery = String.raw`
SELECT format($q$SELECT jsonb_build_object('schema',%L,'relation',%L,'rows',count(*),'rows_md5',md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' ORDER BY md5(to_jsonb(t)::text)),''))) FROM %I.%I t;$q$,n.nspname,c.relname,n.nspname,c.relname)
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname NOT IN ('pg_catalog','information_schema') AND n.nspname NOT LIKE 'pg_toast%'
  AND n.nspname NOT LIKE 'pg_temp%' AND c.relkind IN ('r','p') AND NOT c.relispartition
ORDER BY n.nspname,c.relname
\gexec
`;
export { digestQuery };
