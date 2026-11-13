import fs from 'node:fs';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';

const container = 'supabase_db_BQQuizQA20261112';
const migrationFiles = ['20261113024352_homework_and_quiz_deadlines.sql','20261113031014_quiz_deadline_admission_timestamps.sql'];
function sql(input) {
  const result = spawnSync('docker', ['exec','-i',container,'psql','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-Atq'], { input, encoding: 'utf8', maxBuffer: 2000000 });
  if (result.status !== 0) { console.error(result.stderr); throw new Error('Isolated QA SQL failed. Transaction was rolled back.'); }
  return result.stdout.trim();
}
const ports = spawnSync('docker', ['inspect','--format','{{(index (index .NetworkSettings.Ports "5432/tcp") 0).HostPort}}',container], { encoding: 'utf8' });
assert.equal(ports.stdout.trim(), '58922', 'Dedicated QA database port required.');
const migrations = migrationFiles.map(file => {
  const version=file.split('_')[0]; const migration=fs.readFileSync(`supabase/migrations/${file}`,'utf8');
  return {version,migration,exists:sql(`select count(*) from supabase_migrations.schema_migrations where version='${version}';`)==='1',body:migration.replace(/^begin;\s*$/m,'').replace(/^commit;\s*$/m,'')};
});
const protectedTables = ['profiles','classes','class_memberships','assignments','quiz_assignments','quizzes','quiz_versions','quiz_items','quiz_attempts','quiz_answers','quiz_results','learning_resources'];
const hash = table => `select md5(coalesce(string_agg(row_to_json(t)::text,'|' order by id),'')) from public.${table} t`;
const before = protectedTables.map(t=>`create temp table before_${t} as ${hash(t)};`).join('\n');
const after = `do $$ begin ${protectedTables.map(t=>`if (${hash(t)})<>(select * from before_${t}) then raise exception 'HISTORY_CHANGED_${t}'; end if;`).join('\n')} end $$;`;
if (process.argv.includes('--apply')) {
  for(const {version,migration,exists,body} of migrations) {
  if (exists) console.log(`PASS migration ${version} already applied to dedicated QA.`);
  else {
    sql(`begin;\n${before}\n${body}\n${after}\ninsert into supabase_migrations.schema_migrations(version,name,statements) values('${version}','homework_and_quiz_deadlines',array[$migration$${migration}$migration$]);\ncommit;`);
    console.log(`PASS migration ${version} applied only to QA 58922; all protected row hashes unchanged.`);
  }
  }
} else {
  const testFile = 'supabase/tests/homework_quiz_deadlines_rollback.sql';
  const tests = fs.existsSync(testFile) ? fs.readFileSync(testFile,'utf8').replace(/^begin;\s*$/m,'').replace(/^rollback;\s*$/m,'') : '';
  assert(tests, 'Controlled-clock lifecycle tests required.');
  sql(`begin;\n${before}\n${migrations.filter(m=>!m.exists).map(m=>m.body).join('\n')}\n${after}\n${tests}\nrollback;`);
  console.log('PASS migration/history and activity lifecycle tests (rolled back).');
  if (migrations.every(m=>m.exists)) for (const name of ['quiz_single_attempt_rollback.sql','learner_quiz_lifecycle_rollback.sql','foundation_lifecycle_rollback.sql','resource_ai_workflow_rollback.sql','learner_enrollment_rollback.sql']) {
    const path = `supabase/tests/${name}`;
    if (!fs.existsSync(path)) continue;
    sql(fs.readFileSync(path,'utf8'));
    console.log(`PASS ${name} (rolled back).`);
  }
}
