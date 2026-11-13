// Restores ONLY into the new memory-backed, network-disabled recovery container.
import { spawn, execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { createHash } from 'node:crypto';
import { ref, dir, docker, dpapi, encrypt, decrypt, verifyArchive, digestQuery } from './lib/recovery-archive.mjs';


const db = 'postgres'; // Original name, inside this strictly guarded new isolated container only.
const admin = 'supabase_admin';
const socket = '/bq-recovery';
const attempt = process.argv.find(a=>a.startsWith('--attempt='))?.split('=')[1] ?? '1';
if (!/^[1-9][0-9]?$/.test(attempt)) throw new Error('Invalid restore attempt number');
const container = `bytequest-recovery-rslm-20261113-release-${attempt}`;
const image = 'sha256:6942962433a569e87f228b4d4ab7e11db5deca64e43babb3a038443ad6c4f1bb';
const key = dpapi('unwrap', readFileSync(join(dir, 'archive-key.dpapi')));
const manifest = JSON.parse(readFileSync(join(dir, 'backup-manifest.json'), 'utf8'));
const logs = [];
const evidence = { ref, container, database: db, image, started_at: new Date().toISOString(), recovery_verified: false };
function inspect() { return JSON.parse(execFileSync(docker, ['inspect', container], { encoding: 'utf8' }))[0]; }
function guard() {
  const state = inspect();
  if (state.Name !== `/${container}` || state.Config.Labels?.['bytequest.purpose'] !== 'hosted-recovery-20261113'
      || state.Config.Labels?.['bytequest.source-ref'] !== ref || state.HostConfig.NetworkMode !== 'none'
      || !state.HostConfig.ReadonlyRootfs || Object.keys(state.HostConfig.PortBindings ?? {}).length !== 0
      || !state.HostConfig.Tmpfs?.[socket] || state.Config.User !== '100:101' || state.Image !== image) {
    throw new Error('Isolated recovery target guard failed');
  }
  return state;
}
async function captured(binary, args, input) {
  guard();
  const child = spawn(docker, ['exec', '-i', '-e', 'PGTZ=UTC', container, binary, ...args], { stdio: ['pipe','pipe','pipe'], windowsHide: true });
  const out = [], err = [];
  child.stdout.on('data', b => out.push(b)); child.stderr.on('data', b => err.push(b));
  const closed = new Promise((resolve, reject) => { child.on('error', reject); child.on('close', code => resolve(code)); });
  let pipeError;
  if (input) { try { await pipeline(typeof input === 'string' ? Readable.from([input]) : input, child.stdin); } catch(error) { pipeError=error; } }
  else child.stdin.end();
  const code = await closed;
  const stdout = Buffer.concat(out), stderr = Buffer.concat(err);
  logs.push({ binary, args, code, stdout: stdout.toString('utf8'), stderr: stderr.toString('utf8') });
  if (code !== 0) throw new Error(`Isolated ${binary} failed (exit ${code}); private diagnostics will be encrypted`);
  // --list intentionally reads only the archive TOC and may close stdin before all payload bytes.
  // Full archive GCM authentication was checked before this process started.
  if (pipeError && !(binary==='pg_restore'&&['EPIPE','EOF'].includes(pipeError.code))) throw pipeError;
  return stdout;
}
function sql(statement, database = db) { return captured('psql', ['-h', socket, '-U', admin, '-d', database, '-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1'], statement); }
async function decryptedJson(name) { const parts = []; for await (const part of decrypt(name, key)) parts.push(part); return JSON.parse(Buffer.concat(parts)); }
try {
  if (manifest.ref !== ref || manifest.recovery_verified) throw new Error('Expected untested backup manifest');
  for (const archive of manifest.archives) await verifyArchive(archive, key);
  let existing = execFileSync(docker, ['ps', '-a', '--filter', `name=^/${container}$`, '--format', '{{.Names}}'], { encoding: 'utf8' }).trim();
  if (existing) throw new Error('Recovery target exists; choose a new attempt number.');
  const init = "initdb -D /bq-recovery --username=supabase_admin --auth-local=trust --auth-host=scram-sha-256 > /tmp/init.log 2>&1 && exec postgres -D /bq-recovery -c listen_addresses= -c unix_socket_directories=/bq-recovery -c shared_preload_libraries=pg_stat_statements -c session_preload_libraries=supautils -c supautils.privileged_role=supabase_privileged_role -c supautils.superuser=supabase_admin -c supautils.privileged_extensions=pg_stat_statements,pg_trgm,pgcrypto,supabase_vault,uuid-ossp -c supautils.reserved_roles=supabase_admin,supabase_auth_admin,supabase_storage_admin,supabase_read_only_user,supabase_realtime_admin,supabase_replication_admin,supabase_etl_admin,dashboard_user,pgbouncer,service_role*,authenticator*,authenticated*,anon*,supabase_privileged_role -c wal_level=logical -c max_connections=30 -c logging_collector=off -c log_statement=none -c supautils.drop_trigger_grants='{\"postgres\":[\"auth.audit_log_entries\",\"auth.flow_state\",\"auth.identities\",\"auth.instances\",\"auth.mfa_amr_claims\",\"auth.mfa_challenges\",\"auth.mfa_factors\",\"auth.oauth_clients\",\"auth.one_time_tokens\",\"auth.refresh_tokens\",\"auth.saml_providers\",\"auth.saml_relay_states\",\"auth.sessions\",\"auth.sso_domains\",\"auth.sso_providers\",\"auth.users\",\"realtime.messages\",\"realtime.subscription\",\"storage.buckets\",\"storage.buckets_analytics\",\"storage.objects\",\"storage.prefixes\",\"storage.s3_multipart_uploads\",\"storage.s3_multipart_uploads_parts\"]}' -c supautils.policy_grants='{\"postgres\":[\"auth.audit_log_entries\",\"auth.flow_state\",\"auth.identities\",\"auth.instances\",\"auth.mfa_amr_claims\",\"auth.mfa_challenges\",\"auth.mfa_factors\",\"auth.oauth_clients\",\"auth.one_time_tokens\",\"auth.refresh_tokens\",\"auth.saml_providers\",\"auth.saml_relay_states\",\"auth.sessions\",\"auth.sso_domains\",\"auth.sso_providers\",\"auth.users\",\"realtime.messages\",\"realtime.subscription\",\"storage.buckets\",\"storage.buckets_analytics\",\"storage.objects\",\"storage.prefixes\",\"storage.s3_multipart_uploads\",\"storage.s3_multipart_uploads_parts\"]}'";
  if (existing) execFileSync(docker,['start',container],{stdio:'pipe'});
  else execFileSync(docker, ['run','-d','--name', container, '--label','bytequest.purpose=hosted-recovery-20261113',
    '--label',`bytequest.source-ref=${ref}`, '--network','none','--read-only','--user','100:101',
    '--cap-drop','ALL','--security-opt','no-new-privileges','--memory','1g','--memory-swap','1g','--pids-limit','100',
    '--tmpfs','/bq-recovery:rw,nosuid,nodev,uid=100,gid=101,mode=0700,size=768m',
    '--tmpfs','/tmp:rw,nosuid,nodev,uid=100,gid=101,mode=0700,size=32m',
    '--entrypoint','sh',image,'-c',init], { stdio: ['ignore','pipe','pipe'] });
  guard();
  let ready = false;
  for (let i = 0; i < 30; i++) {
    try { execFileSync(docker,['exec',container,'pg_isready','-h',socket,'-U',admin,'-d','postgres'],{stdio:'pipe'}); ready = true; break; } catch {}
    await new Promise(resolve => setTimeout(resolve,1000));
  }
  if (!ready) throw new Error('Isolated PostgreSQL did not become ready');
  console.log(JSON.stringify({ stage: 'secured_restore_target_ready', container, network: 'none', published_ports: 0, data: 'tmpfs', uid: 100 }));
  const roleParts=[]; for await (const part of decrypt('roles.sql.bqenc', key)) roleParts.push(part);
  const originalRolesSql=Buffer.concat(roleParts).toString('utf8');
  if ((originalRolesSql.match(/^CREATE ROLE supabase_admin;$/gm)??[]).length!==1) throw new Error('Expected original bootstrap role declaration');
  const rolesSql=originalRolesSql.replace(/^CREATE ROLE supabase_admin;$/m,'-- Bootstrap supabase_admin already created by initdb, matching the source cluster.');
  evidence.role_restore_procedure='Initialize the isolated cluster with original bootstrap superuser supabase_admin (OID 10); omit only its duplicate CREATE ROLE; replay all original role attributes and membership grantors';
  await captured('psql', ['-h', socket, '-U', admin, '-d', 'template1', '-X', '-q', '-v', 'ON_ERROR_STOP=1'], rolesSql);
  const archive = manifest.archives.find(a => a.filename.endsWith('.dump.bqenc'));
  const toc=(await captured('pg_restore',['--list'],decrypt(archive.filename,key))).toString('utf8').split(/\r?\n/);
  const events=toc.filter(line=>!line.startsWith(';')&&line.includes(' EVENT TRIGGER '));
  if (!events.some(line=>line.includes('ensure_rls'))) throw new Error('Expected original ensure_rls event trigger entry');
  await captured('tee',[socket+'/database-restore.list'],Readable.from([toc.filter(line=>!events.includes(line)).join('\n')+'\n']));
  await captured('tee',[socket+'/event-trigger-restore.list'],Readable.from([events.join('\n')+'\n']));
  // The default empty postgres DB exists only in this just-initialized private tmpfs cluster.
  // Restore --create recreates its original owner, database settings and database ACLs.
  await sql('DROP DATABASE postgres;\n','template1');
  evidence.database_restore_procedure='Load Supautils with source privileged/reserved roles; recreate original database using pg_restore --create; restore event triggers separately with --use-set-session-authorization so each is created by its original owner';
  evidence.event_trigger_toc_entries=events.length;
  await captured('pg_restore',['-h',socket,'-U',admin,'-d','template1','--create','--exit-on-error','--use-list',socket+'/database-restore.list'],decrypt(archive.filename,key));
  await captured('pg_restore',['-h',socket,'-U',admin,'-d',db,'--exit-on-error','--use-set-session-authorization','--use-list',socket+'/event-trigger-restore.list'],decrypt(archive.filename,key));
  const expected = await decryptedJson('snapshot-digests.json.bqenc');
  let restored = (await sql('BEGIN READ ONLY;\n'+digestQuery+'\nROLLBACK;\n')).toString('utf8').trim().split(/\r?\n/).filter(s=>s.startsWith('{')).map(s=>JSON.parse(s));
  const index = rows => new Map(rows.map(r=>[r.schema+'.'+r.relation,r]));
  const sourceMap = index(expected.relations), restoredMap = index(restored);
  const differences = [...new Set([...sourceMap.keys(),...restoredMap.keys()])].filter(k=>JSON.stringify(sourceMap.get(k))!==JSON.stringify(restoredMap.get(k)));
  if (differences.length) { evidence.differing_relations = differences; throw new Error('Restored table counts/content hashes differ'); }
  evidence.restored_relation_count = restored.length;
  evidence.restored_row_count = restored.reduce((total,r)=>total+Number(r.rows),0);
  evidence.all_table_counts_and_row_hashes_match = true;
  const catalog = await sql(readFileSync('scripts/hosted-mobile-readonly-evidence.sql','utf8'));
  evidence.catalog_archive = await encrypt(Readable.from([catalog]), `restored-catalog-attempt${attempt}.json.bqenc`,key);
  evidence.recovery_verified = true;
  evidence.restore_completed_at = new Date().toISOString();
  console.log(JSON.stringify({ stage:'restore_data_verified',ref, relations:restored.length, all_row_hashes_match:true }));
  if(process.argv.includes('--test-exact-approval-sql')) {
    const approvalSql=readFileSync('scripts/hosted-mobile-compatibility-20261111.sql');
    await sql(approvalSql.toString('utf8'));
    const applied=(await sql('BEGIN READ ONLY;\n'+digestQuery+'\nROLLBACK;\n')).toString('utf8').trim().split(/\r?\n/).filter(s=>s.startsWith('{')).map(s=>JSON.parse(s));
    const approvedMap=index(applied);
    const protectedDifferences=[...sourceMap.keys()].filter(k=>!['public.practice_mission_contracts','supabase_migrations.schema_migrations'].includes(k)&&JSON.stringify(sourceMap.get(k))!==JSON.stringify(approvedMap.get(k)));
    if(protectedDifferences.length)throw new Error('Exact approval SQL changed protected restored data');
    evidence.exact_approval_sql_sha256=createHash('sha256').update(approvalSql).digest('hex');
    evidence.exact_approval_sql_passed=true;
    evidence.approval_sql_protected_data_unchanged=true;
    restored=applied;
    console.log(JSON.stringify({stage:'exact_approval_sql_passed_on_restored_copy',production_applied:false,sha256:evidence.exact_approval_sql_sha256}));
  }

  const migrationFiles=[
  "20261112111620_quiz_publishing_and_single_attempt.sql",
  "20261112151434_resource_quiz_sources_and_request_safety.sql",
  "20261113024352_homework_and_quiz_deadlines.sql",
  "20261113031014_quiz_deadline_admission_timestamps.sql",
  "20261113062554_learner_activity_notifications.sql",
  "20261113072038_notification_quiz_assignment_links.sql",
  "20261113084656_direct_storage_uploads.sql"
];
  const bodies=migrationFiles.map(file=>readFileSync('supabase/migrations/'+file,'utf8').replace(/^begin;\s*$/m,'').replace(/^commit;\s*$/m,''));
  const capture=String.raw`
create temp table bq_preservation(schema_name text,table_name text,columns_sql text,row_hash text);
do $guard$ declare r record; cols text; h text; begin
 for r in select n.nspname,c.relname,c.oid from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='public' and c.relkind='r' loop
   select string_agg(quote_ident(attname),',' order by attnum) into cols from pg_attribute where attrelid=r.oid and attnum>0 and not attisdropped;
   execute format('select md5(coalesce(string_agg(md5(row_to_json(t)::text),'''' order by md5(row_to_json(t)::text)),'''')) from (select %s from %I.%I) t',cols,r.nspname,r.relname) into h;
   insert into bq_preservation values(r.nspname,r.relname,cols,h);
 end loop;
end $guard$;
`;
  const check=String.raw`
do $guard$ declare r record; h text; begin
 for r in select * from bq_preservation loop
   execute format('select md5(coalesce(string_agg(md5(row_to_json(t)::text),'''' order by md5(row_to_json(t)::text)),'''')) from (select %s from %I.%I) t',r.columns_sql,r.schema_name,r.table_name) into h;
   if h is distinct from r.row_hash then raise exception 'RELEASE_HISTORY_CHANGED: %.%',r.schema_name,r.table_name; end if;
 end loop;
 if exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and not c.relrowsecurity) then raise exception 'RLS_DISABLED'; end if;
end $guard$;
`;
  const tests=['quiz_single_attempt_rollback.sql','learner_quiz_lifecycle_rollback.sql','foundation_lifecycle_rollback.sql','resource_ai_workflow_rollback.sql','learner_enrollment_rollback.sql','homework_quiz_deadlines_rollback.sql','learner_notifications_rollback.sql','direct_storage_uploads_rollback.sql'].map(n=>readFileSync('supabase/tests/'+n,'utf8').replace(/^begin;\s*$/m,'').replace(/^rollback;\s*$/m,''));
  await sql('begin;\n'+capture+'\nset local role postgres;\n'+bodies.join('\n')+'\nreset role;\n'+check+'\n'+tests.map((test,i)=>'savepoint bq_test;\n'+(i===6?'':test+(i===5?'\n'+tests[6]:''))+'\nrollback to savepoint bq_test;\nrelease savepoint bq_test;').join('\n')+'\nrollback;\n');
  const after=await sql('BEGIN READ ONLY;\n'+digestQuery+'\nROLLBACK;\n');
  const matches=after.toString('utf8').trim().split(/\r?\n/).filter(s=>s.startsWith('{')).map(s=>JSON.parse(s));
  if(JSON.stringify(restored)!==JSON.stringify(matches))throw Error('Migration rehearsal rollback changed restored source');
  evidence.hosted_supautils_policy_and_trigger_grants_mirrored=true;
  evidence.release_migrations_rehearsal_passed=true;
  evidence.release_migrations=migrationFiles.map((file,i)=>({file,sha256:createHash('sha256').update(readFileSync('supabase/migrations/'+file)).digest('hex')}));
  evidence.release_regression_files=tests.length;
  console.log(JSON.stringify({stage:'release_migrations_rehearsal_passed',migrations:migrationFiles.length,rollback_test_files:tests.length,historical_public_data_preserved:true}));

} catch(error) {
  evidence.failure = error.message;
  console.error(error.message);
  process.exitCode = 1;
} finally {
  evidence.diagnostics_archive = await encrypt(Readable.from([JSON.stringify(logs)]),`restore-diagnostics-attempt${attempt}.json.bqenc`,key);
  evidence.finished_at = new Date().toISOString();
  writeFileSync(join(dir,`restore-verification-attempt${attempt}.json`),JSON.stringify(evidence,null,2),{flag:'wx'});
  // Stop only this verified, newly created target. Its tmpfs contains the plaintext restored copy.
  try { guard(); execFileSync(docker,['stop','-t','10',container],{stdio:'pipe'}); evidence.target_stopped=true;
    writeFileSync(join(dir,`restore-verification-attempt${attempt}.json`),JSON.stringify(evidence,null,2)); } catch {}
  key.fill(0);
}
