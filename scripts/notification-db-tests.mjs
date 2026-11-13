import fs from 'node:fs';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
const container='supabase_db_BQQuizQA20261112';
assert.equal(spawnSync('docker',['inspect','--format','{{(index (index .NetworkSettings.Ports "5432/tcp") 0).HostPort}}',container],{encoding:'utf8'}).stdout.trim(),'58922');
function sql(input) {
  const r=spawnSync('docker',['exec','-i',container,'psql','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-Atq'],{input,encoding:'utf8',maxBuffer:3e6});
  if(r.status!==0) { console.error(r.stderr); throw Error('Isolated notification SQL failed'); }
  return r.stdout.trim();
}
const migrations=['20261113062554_learner_activity_notifications.sql','20261113072038_notification_quiz_assignment_links.sql'].map(file=>{
  const version=file.split('_')[0],migration=fs.readFileSync(`supabase/migrations/${file}`,'utf8');
  return {version,migration,body:migration.replace(/^begin;\s*$/m,'').replace(/^commit;\s*$/m,''),exists:sql(`select count(*) from supabase_migrations.schema_migrations where version='${version}'`)==='1'};
});
const pending=migrations.filter(m=>!m.exists).map(m=>m.body).join('\n');
const tables=['profiles','classes','class_memberships','assignments','attempts','quiz_assignments','quizzes','quiz_versions','quiz_items','quiz_attempts','quiz_answers','quiz_results','homework_assignments','homework_submissions','homework_files','audit_events','notifications'];
const hash=t=>`select md5(coalesce(string_agg(${t==='notifications'?"(to_jsonb(t)-'event_key')::text":"row_to_json(t)::text"},'|' order by id),'')) from public.${t} t`;
const before=tables.map(t=>`create temp table before_${t} as ${hash(t)};`).join('\n');
const after=`do $$ begin ${tables.map(t=>`if (${hash(t)})<>(select * from before_${t}) then raise exception 'HISTORY_CHANGED_${t}'; end if;`).join('\n')} end $$;`;
if(process.argv.includes('--apply')) {
  for(const {version,migration,body,exists} of migrations) {
  if(exists) console.log(`PASS notification migration ${version} already applied only to isolated QA`);
  else {
    sql(`begin; ${before} ${body} ${after} insert into supabase_migrations.schema_migrations(version,name,statements) values('${version}','learner_activity_notifications',array[$migration$${migration}$migration$]); commit;`);
    console.log('PASS notification migration applied only to QA 58922; protected history unchanged');
  }
  }
} else {
  const lifecycle=fs.readFileSync('supabase/tests/homework_quiz_deadlines_rollback.sql','utf8').replace(/^begin;\s*$/m,'').replace(/^rollback;\s*$/m,'');
  const notifications=fs.readFileSync('supabase/tests/learner_notifications_rollback.sql','utf8');
  sql(`begin; ${before} ${pending} ${after} ${lifecycle} ${notifications} rollback;`);
  console.log('PASS five notification events, scope, duplicate delivery, authoritative read time, mark-all, revoked destinations and existing homework/quiz lifecycle (rollback)');
  const foundation=fs.readFileSync('supabase/tests/foundation_lifecycle_rollback.sql','utf8').replace(/^begin;\s*$/m,'').replace(/^rollback;\s*$/m,'');
  sql(`begin; ${pending} ${foundation}
    do $$ begin if not exists(select 1 from public.notifications n join bytequest_test_context t on n.user_id=t.learner_id and n.metadata->>'activity_id'=t.assignment_id::text and n.metadata->>'activity_type'='technical') then raise exception 'TECHNICAL_NOTIFICATION_MISSING'; end if; end $$;
    rollback;`);
  console.log('PASS real technical assessment assignment event plus existing instructor review/release lifecycle (rollback)');
}
