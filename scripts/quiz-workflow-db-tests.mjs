import fs from 'node:fs';
import { spawnSync } from 'node:child_process';

// Hard guard: this runner cannot target hosted or the primary local database.
const container = process.env.BQ_QUIZ_QA_CONTAINER;
const database = process.env.BQ_QUIZ_QA_DATABASE;
if (!/^supabase-ByteQuest_Backend_QA_[\w-]+-database-[\w-]+$/.test(container ?? '') || !/^bq_quiz_qa_[a-z0-9_]+$/.test(database ?? '')) {
  throw new Error('Explicit isolated quiz QA container and bq_quiz_qa_* database required.');
}
const migration = fs.readFileSync('supabase/migrations/20261112111620_quiz_publishing_and_single_attempt.sql', 'utf8');
const body = migration.replace(/^begin;\s*$/m, '').replace(/^commit;\s*$/m, '');
const resourceMigration = fs.readFileSync('supabase/migrations/20261112151434_resource_quiz_sources_and_request_safety.sql', 'utf8').replace(/^begin;\s*$/m, '').replace(/^commit;\s*$/m, '');
const fixtures = `
create temp table qa_staff as select gen_random_uuid() id,role from (values('instructor'),('instructor'),('admin')) s(role);
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
select id,'00000000-0000-0000-0000-000000000000'::uuid,'authenticated','authenticated',id||'@quiz-qa.invalid','',
'{"provider":"email","providers":["email"]}'::jsonb,'{"full_name":"Isolated quiz QA"}'::jsonb,now(),now() from qa_staff;
update public.profiles p set role=s.role::public.user_role,status='active' from qa_staff s where p.user_id=s.id;
`;
const tests = ['quiz_single_attempt_rollback.sql', 'learner_quiz_lifecycle_rollback.sql', 'foundation_lifecycle_rollback.sql', 'resource_ai_workflow_rollback.sql'];
for (const name of tests) {
  const test = fs.readFileSync(`supabase/tests/${name}`, 'utf8').replace(/^begin;\s*$/m, '').replace(/^rollback;\s*$/m, '');
  const result = spawnSync('docker', ['exec', '-i', container, 'psql', '-U', 'supabase_admin', '-d', database, '-v', 'ON_ERROR_STOP=1', '-q'], { input: `begin;\n${fixtures}\n${body}\n${resourceMigration}\n${test}\nrollback;`, encoding: 'utf8', maxBuffer: 5_000_000 });
  if (result.status !== 0) { process.stdout.write(result.stdout); process.stderr.write(result.stderr); process.exit(result.status ?? 1); }
  console.log(`PASS ${name} (migration and fixtures rolled back)`);
}
const legacy = fs.readFileSync('scripts/fixtures/quiz_legacy_attempts.sql', 'utf8');
const preservation = `
do $$ begin
  if (select attempt_id from private.quiz_attempt_claims where learner_id=(select learner_id from legacy_quiz_context) and quiz_id=(select quiz_id from legacy_quiz_context))<>(select completed_a from legacy_quiz_context) then raise exception 'LEGACY_CANONICAL_CLAIM_FAILED'; end if;
  if (select md5(string_agg(row_to_json(a)::text,'|' order by id)) from public.quiz_attempts a)<>(select attempts from legacy_hashes) then raise exception 'LEGACY_ATTEMPTS_CHANGED'; end if;
  if (select md5(string_agg(row_to_json(a)::text,'|' order by id)) from public.quiz_results a)<>(select results from legacy_hashes) then raise exception 'LEGACY_RESULTS_CHANGED'; end if;
  if (select md5(string_agg(row_to_json(a)::text,'|' order by id)) from public.quiz_assignments a)<>(select assignments from legacy_hashes) then raise exception 'LEGACY_ASSIGNMENTS_CHANGED'; end if;
end $$;
`;
const preserved = spawnSync('docker', ['exec', '-i', container, 'psql', '-U', 'supabase_admin', '-d', database, '-v', 'ON_ERROR_STOP=1', '-q'], { input: `begin;\n${fixtures}\n${legacy}\n${body}\n${preservation}\nrollback;`, encoding: 'utf8', maxBuffer: 1_000_000 });
if (preserved.status !== 0) { process.stdout.write(preserved.stdout); process.stderr.write(preserved.stderr); process.exit(preserved.status ?? 1); }
console.log('PASS legacy duplicates preserved byte-for-byte; submitted history claims the quiz (rolled back)');
