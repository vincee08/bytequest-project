import fs from 'node:fs';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
const container='supabase_db_BQQuizQA20261112';
assert.equal(spawnSync('docker',['inspect','--format','{{(index (index .NetworkSettings.Ports "5432/tcp") 0).HostPort}}',container],{encoding:'utf8'}).stdout.trim(),'58922');
function sql(input){const r=spawnSync('docker',['exec','-i',container,'psql','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-Atq'],{input,encoding:'utf8',maxBuffer:3000000});if(r.status!==0){fs.mkdirSync('.tmp/release-20261113',{recursive:true});fs.writeFileSync('.tmp/release-20261113/upload-db-error.log',r.stderr);throw Error('Upload DB regression failed; private diagnostics saved.');}return r.stdout.trim();}
const file='20261113084656_direct_storage_uploads.sql',version=file.split('_')[0],migration=fs.readFileSync('supabase/migrations/'+file,'utf8');
const exists=sql(`select count(*) from supabase_migrations.schema_migrations where version='${version}'`)==='1';
const body=migration.replace(/^begin;\s*$/m,'').replace(/^commit;\s*$/m,'');
const tests=fs.readFileSync('supabase/tests/direct_storage_uploads_rollback.sql','utf8').replace(/^begin;\s*$/m,'').replace(/^rollback;\s*$/m,'');
sql('begin;\n'+(exists?'':body)+'\n'+tests+'\nrollback;');
console.log('PASS upload authorization, size limits, immutable retries, leases, metadata idempotency, revoked access and cleanup (rollback).');
if(process.argv.includes('--apply')&&!exists){sql('begin;\n'+body+`\ninsert into supabase_migrations.schema_migrations(version,name,statements) values('${version}','direct_storage_uploads',array[$migration$${migration}$migration$]);\ncommit;`);console.log('PASS targeted upload migration applied only to dedicated QA 58922.');}
