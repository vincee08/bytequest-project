// Run through quiz-preview.mjs release-gates. Never accepts hosted endpoints.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {randomBytes,randomUUID,createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';
import {createClient} from '@supabase/supabase-js';
import {createServerClient} from '@supabase/ssr';
import {textPdf} from './fixtures/resource-pdf.mjs';

assert.equal(process.env.NEXT_PUBLIC_SUPABASE_URL,'http://127.0.0.1:58921','Dedicated QA backend required.');
const base='http://127.0.0.1:3008',url=process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
const opts={auth:{persistSession:false,autoRefreshToken:false}},service=createClient(url,process.env.SUPABASE_SERVICE_ROLE_KEY,opts);
const run=randomUUID().slice(0,8),results=[],created=[];
const pass=message=>{results.push({result:'PASS',message});console.log('PASS '+message);};
async function ok(p){const r=await p;assert(!r.error,r.error?.message);return r.data;}
async function login(a){const client=createClient(url,key,opts),data=await ok(client.auth.signInWithPassword({email:a.email,password:a.password}));return {client,id:data.user.id,token:data.session.access_token,...a};}
async function api(actor,path,body,status=200,extra={}){
  const r=await fetch(base+path,{method:body?'POST':'GET',headers:{...(actor?{Authorization:'Bearer '+actor.token}:{}),...(body?{'Content-Type':'application/json'}:{}),...extra},body:body?JSON.stringify(body):undefined});
  const data=await r.json();assert.equal(r.status,status,`Unexpected API status for ${path}: ${r.status} (${data.error??'no error'})`);return data;
}
async function prepare(actor,target,bytes,title='Network reference '+run,purpose='resource',overrides={}){
  const body={action:'prepare',purpose,target_id:target,filename:'reference.pdf',mime:'application/pdf',size:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex'),...(purpose==='resource'?{title}:{}),...overrides};
  return {body,...await api(actor,'/api/uploads',body)};
}
async function put(p,bytes){const r=await fetch(p.signed_url,{method:'PUT',headers:{'Content-Type':p.body.mime,'x-upsert':'false'},body:bytes});assert(r.ok,'Direct Storage PUT failed with '+r.status);}
const complete=(actor,p,status=201)=>api(actor,'/api/uploads',{action:'complete',upload_id:p.upload_id},status);
function sql(input){
  const container='supabase_db_BQQuizQA20261112';
  assert.equal(spawnSync('docker',['inspect','--format','{{(index (index .NetworkSettings.Ports "5432/tcp") 0).HostPort}}',container],{encoding:'utf8'}).stdout.trim(),'58922');
  const r=spawnSync('docker',['exec','-i',container,'psql','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-Atq'],{encoding:'utf8',input});
  assert.equal(r.status,0,'Dedicated QA fixture SQL failed.');return r.stdout.trim();
}
let browser,diagnosticPage;
try{
  for(let i=0;i<4;i++){
    const account={email:`release.${run}.${i}@bytequest.invalid`,password:randomBytes(32).toString('base64url')+'Aa1!'};
    const data=await ok(service.auth.admin.createUser({...account,email_confirm:true,user_metadata:{full_name:'Isolated Release QA '+run}}));
    created.push({...account,id:data.user.id});
    if(i<2)await ok(service.from('profiles').update({role:'instructor'}).eq('user_id',data.user.id));
  }
  const teacher=await login(created[0]),foreign=await login(created[1]),learner=await login(created[2]),outsider=await login(created[3]);
  const cls=await ok(teacher.client.rpc('create_class',{p_title:'Release gates '+run,p_class_code:'RG-'+run}));
  await ok(teacher.client.rpc('enroll_learner',{p_class_id:cls.id,p_learner_id:learner.id}));
  const small=textPdf(),large=Buffer.alloc(50*1024*1024,32);small.copy(large);
  await api(null,'/api/uploads',{action:'complete',upload_id:randomUUID()},401);
  const p=await prepare(teacher,cls.id,small);
  await api(foreign,'/api/uploads',p.body,403);await api(learner,'/api/uploads',p.body,403);
  await api(teacher,'/api/uploads',{...p.body,size:large.length+1},400);
  await api(teacher,'/api/uploads',{...p.body,mime:'text/html'},422);
  await api(teacher,'/api/uploads',p.body,403,{Origin:'https://untrusted.invalid'});
  await put(p,small);
  const saved=(await complete(teacher,p)).record;
  assert.equal((await complete(teacher,p,200)).record.id,saved.id);
  assert.equal((await api(teacher,'/api/uploads',p.body)).record.id,saved.id);
  const intent=await ok(service.from('file_upload_intents').select('*').eq('id',p.upload_id).single());
  assert.equal((await ok(service.from('learning_resources').select('id').eq('id',saved.id))).length,1);
  assert((await learner.client.from('file_upload_intents').select('*')).error,'Client journal access must be denied.');
  assert((await learner.client.rpc('manage_file_upload',{p_actor:teacher.id,p_action:'prepare',p_spec:{}})).error);
  const overwrite=await fetch(p.signed_url,{method:'PUT',headers:{'Content-Type':'application/pdf','x-upsert':'true'},body:Buffer.from('replacement')});
  assert(!overwrite.ok,'Signed token must forbid overwrite, even if client changes upsert header.');
  pass('direct upload authorization, origin rejection, scoped token, overwrite denial and idempotent metadata');
  const max=await prepare(teacher,cls.id,large,'50 MiB reference '+run);await put(max,large);const maxRecord=(await complete(teacher,max)).record;
  assert.equal(maxRecord.size_bytes,large.length);
  pass('50 MiB class resource uploaded directly to private Storage and verified without a Vercel request body');
  fs.writeFileSync('.tmp/release-20261113/direct-source-fixture.json',JSON.stringify({classId:cls.id,smallId:saved.id,largeId:maxRecord.id}));
  const extraction=spawnSync(process.execPath,['--conditions=react-server','--import','tsx','../scripts/direct-resource-source-qa.mts'],{cwd:'ByteQuest-Web-Dashboard',env:{...process.env,TSX_TSCONFIG_PATH:'tsconfig.json',BQ_QA_INSTRUCTOR_EMAIL:teacher.email,BQ_QA_INSTRUCTOR_PASSWORD:teacher.password},encoding:'utf8'});
  assert.equal(extraction.status,0,'Direct-upload PDF extraction regression failed.');
  pass('direct-upload text PDF parsing and oversized AI-source rejection before download or provider access');
  const wrong=await prepare(teacher,cls.id,small,'Hash mismatch '+run);await put(wrong,Buffer.from(small.map((b,i)=>i===100?b^1:b)));await complete(teacher,wrong,415);
  const bad=Buffer.from('not a PDF');const forged=await prepare(teacher,cls.id,bad,'Forged PDF '+run);await put(forged,bad);await complete(teacher,forged,415);
  const interrupted=await prepare(teacher,cls.id,small,'Interrupted '+run);await complete(teacher,interrupted,503);await put(interrupted,small);await complete(teacher,interrupted);
  pass('hash/format mismatch rejected and interrupted upload retries preserve a single record');
  const download=await ok(learner.client.storage.from('learning-resources').createSignedUrl(intent.object_path,60));
  assert((await fetch(download.signedUrl)).ok);
  assert((await outsider.client.storage.from('learning-resources').createSignedUrl(intent.object_path,60)).error);
  assert((await foreign.client.storage.from('learning-resources').createSignedUrl(intent.object_path,60)).error);
  assert.notEqual((await fetch(url+'/storage/v1/object/public/learning-resources/'+intent.object_path)).status,200);
  pass('private resource downloads allow enrolled learners and deny outsiders and foreign instructors');
  const hw=(await api(teacher,'/api/activities/homework',{action:'create',class_id:cls.id,title:'Direct homework '+run,instructions:'Write an inspection report.',deadline_at:null})).record;
  const ten=Buffer.alloc(10*1024*1024,32);small.copy(ten);
  const instruction=await prepare(teacher,hw.id,ten,'','homework');await put(instruction,ten);const instructionFile=(await complete(teacher,instruction)).record;
  await api(teacher,'/api/activities/homework',{action:'publish',assignment_id:hw.id});
  const answer=await prepare(learner,hw.id,ten,'','homework');await put(answer,ten);const answerFile=(await complete(learner,answer)).record;
  await api(outsider,'/api/uploads',answer.body,403);
  await api(learner,'/api/uploads',{...answer.body,size:ten.length+1},422);
  assert.equal(answerFile.size_bytes,ten.length);assert.equal(instructionFile.size_bytes,ten.length);
  await api(learner,`/api/activities/files?id=${answerFile.id}`);
  await api(teacher,`/api/activities/files?id=${instructionFile.id}`);
  await api(outsider,`/api/activities/files?id=${answerFile.id}`,null,404);
  const revoked=await prepare(learner,hw.id,small,'','homework');await put(revoked,small);
  await ok(service.from('class_memberships').update({status:'deactivated',deactivated_by:teacher.id,deactivated_at:new Date().toISOString(),deactivation_reason:'Isolated release scope test'}).eq('class_id',cls.id).eq('learner_id',learner.id));
  await complete(learner,revoked,403);
  await ok(teacher.client.rpc('enroll_learner',{p_class_id:cls.id,p_learner_id:learner.id}));
  const submission=(await api(learner,'/api/activities/homework',{action:'submit',assignment_id:hw.id,answer:'Isolated QA report.',file_ids:[answerFile.id]})).record;
  await api(teacher,`/api/activities/files?id=${answerFile.id}`);
  const graded=(await api(teacher,'/api/activities/homework',{action:'grade',assignment_id:hw.id,submission_id:submission.id,feedback:'Isolated QA review.',score:null})).record;
  assert.equal(graded.status,'graded');
  pass('10 MiB instructor instructions and learner homework uploads, private download and revoked-enrollment finalization denial');
  const abandoned=await prepare(teacher,cls.id,small,'Abandoned '+run);await put(abandoned,small);
  const old=await ok(service.from('file_upload_intents').select('*').eq('id',abandoned.upload_id).single());
  await ok(service.from('file_upload_intents').update({expires_at:new Date(Date.now()-1000).toISOString()}).eq('id',abandoned.upload_id));
  await api(null,'/api/internal/uploads/cleanup',null,401);
  await api(null,'/api/internal/uploads/cleanup',null,200,{Authorization:'Bearer '+process.env.CRON_SECRET});
  assert((await service.storage.from(old.bucket).download(old.object_path)).error);
  assert.equal((await ok(service.from('file_upload_intents').select('state').eq('id',abandoned.upload_id).single())).state,'cleaned');
  await api(teacher,'/api/uploads',abandoned.body);
  const fresh=await ok(service.from('file_upload_intents').select('object_path').eq('id',abandoned.upload_id).single());assert.notEqual(fresh.object_path,old.object_path);
  assert((await service.storage.from(intent.bucket).download(intent.object_path)).data);
  pass('authorized abandoned-upload cleanup, referenced-file preservation and distinct retry generation paths');
  const {chromium}=await import(pathToFileURL(process.env.BQ_PLAYWRIGHT_MODULE).href);browser=await chromium.launch({headless:true});
  const cookies=[];const ssr=createServerClient(url,key,{cookies:{getAll:()=>cookies,setAll:values=>{for(const v of values){const i=cookies.findIndex(c=>c.name===v.name);if(i<0)cookies.push(v);else cookies[i]=v;}}}});
  await ok(ssr.auth.signInWithPassword({email:teacher.email,password:teacher.password}));
  const context=await browser.newContext({viewport:{width:1440,height:1000}});
  context.setDefaultTimeout(120000);context.setDefaultNavigationTimeout(120000);
  await context.addCookies(cookies.map(c=>({name:c.name,value:c.value,url:base,sameSite:'Lax'})));
  const page=await context.newPage(),requests=[];page.on('request',r=>{if(r.url().startsWith(base+'/api/uploads'))requests.push(r.postDataBuffer()?.length??0);});
  diagnosticPage=page;
  await page.goto(base+'/classes/'+cls.id+'?tab=resources',{waitUntil:'domcontentloaded'});
  await page.waitForFunction(()=>{const input=document.querySelector('#resource-title');return input&&Object.keys(input).some(k=>k.startsWith('__reactProps')&&typeof input[k]?.onChange==='function');});
  await page.getByLabel('Resource title',{exact:true}).fill('Browser direct reference '+run);
  await page.getByLabel('File',{exact:true}).setInputFiles({name:'network.pdf',mimeType:'application/pdf',buffer:small});
  let sentWithoutAcknowledgement=false;
  await page.route('**/storage/v1/object/upload/sign/**',async route=>{
    if(route.request().method()==='PUT'&&!sentWithoutAcknowledgement){
      sentWithoutAcknowledgement=true;
      const delivered=await route.fetch();assert(delivered.ok());
      await route.abort('failed'); // Bytes arrived, but the browser lost the acknowledgement.
    }else await route.continue();
  });
  await page.getByRole('button',{name:'Upload resource',exact:true}).click();
  await page.getByRole('alert').filter({hasText:'upload connection was interrupted'}).waitFor({timeout:120000});
  const savedResponse=page.waitForResponse(async r=>r.url()===base+'/api/uploads'&&r.status()===201,{timeout:120000});
  await page.getByRole('button',{name:'Upload resource',exact:true}).click();
  try{await savedResponse;}catch{
    fs.writeFileSync('.tmp/release-20261113/upload-browser-private.txt',await page.locator('body').innerText());
    await page.screenshot({path:'.tmp/release-20261113/upload-browser-private.png',fullPage:true});
    throw Error('Browser upload failed; inspect private browser diagnostics.');
  }
  await page.getByRole('status').filter({hasText:'Resource saved.'}).waitFor();
  assert(requests.length>=2&&requests.every(n=>n<8192));await context.close();
  assert(sentWithoutAcknowledgement);
  pass('browser upload UI, lost acknowledgement retry, duplicate Storage response, progress/success state and metadata-only function requests');
  // Email remains in the dedicated local capture service, never external delivery.
  diagnosticPage=undefined;
  const recover=created[3];
  await api(null,'/api/auth/recovery',{action:'request',email:recover.email},200,{Origin:'http://127.0.0.1:3009'});
  let message;
  for(let i=0;i<30;i++){
    const inbox=await (await fetch('http://127.0.0.1:58924/api/v1/messages')).json();
    const entry=inbox.messages?.find(m=>m.To?.some(to=>to.Address===recover.email));
    if(entry){message=await (await fetch('http://127.0.0.1:58924/api/v1/message/'+entry.ID)).json();break;}
    await new Promise(r=>setTimeout(r,500));
  }
  assert(message,'Recovery message must arrive at isolated local Mailpit.');
  const link=message.HTML.match(/href="([^"]*#token_hash=[^"]+)"/)?.[1]?.replaceAll('&amp;','&');
  assert(link?.startsWith(base+'/auth/recover#'),'Recovery template must use a fragment token.');
  const hash=new URL(link).hash;
  const recoveryContext=await browser.newContext({viewport:{width:390,height:844}}),recoveryPage=await recoveryContext.newPage();
  recoveryContext.setDefaultTimeout(120000);recoveryContext.setDefaultNavigationTimeout(120000);
  await recoveryPage.goto(link,{waitUntil:'domcontentloaded'});await recoveryPage.getByRole('button',{name:'Continue securely'}).waitFor();
  assert.equal(new URL(recoveryPage.url()).hash,'');assert.equal(new URL(recoveryPage.url()).search,'');
  await recoveryPage.getByRole('button',{name:'Continue securely'}).click();await recoveryPage.getByLabel('New password',{exact:true}).waitFor();
  await recoveryPage.reload();await recoveryPage.getByLabel('New password',{exact:true}).waitFor();
  const weak=await recoveryContext.request.post(base+'/api/auth/recovery',{data:{action:'update',password:'short'}});assert.equal(weak.status(),400);
  const newPassword=randomBytes(32).toString('base64url')+'Aa1!';
  await recoveryPage.getByLabel('New password',{exact:true}).fill(newPassword);await recoveryPage.getByLabel('Confirm password',{exact:true}).fill('Different-password1!');await recoveryPage.getByRole('button',{name:'Update password',exact:true}).click();
  await recoveryPage.getByRole('alert').filter({hasText:'does not match'}).waitFor();
  await recoveryPage.getByLabel('Confirm password',{exact:true}).fill(newPassword);await recoveryPage.getByRole('button',{name:'Update password',exact:true}).click();
  await recoveryPage.getByText('Your password was updated.',{exact:false}).waitFor();
  const publicClient=createClient(url,key,opts);
  assert((await publicClient.auth.signInWithPassword({email:recover.email,password:recover.password})).error);
  await ok(publicClient.auth.signInWithPassword({email:recover.email,password:newPassword}));await publicClient.auth.signOut();
  const tokenHash=new URLSearchParams(hash.slice(1)).get('token_hash');
  assert.equal((await recoveryContext.request.post(base+'/api/auth/recovery',{data:{action:'verify',token_hash:tokenHash}})).status(),400);
  assert.equal((await recoveryContext.request.post(base+'/api/auth/recovery',{data:{action:'update',password:randomBytes(30).toString('base64url')}})).status(),401);
  assert.equal((await recoveryContext.request.get(base+'/api/auth/recovery')).status(),200);
  await recoveryContext.close();
  const unauth=await browser.newContext();assert.equal((await unauth.request.post(base+'/api/auth/recovery',{data:{action:'verify',token_hash:'invalid-link-hash-with-no-real-token'}})).status(),400);await unauth.close();
  pass('mobile reset request, captured email, responsive recovery session/reload, password update, old password denial and one-time/invalid link denial');
  // Expire ONLY this run's dedicated synthetic account recovery token.
  const expired=await ok(service.auth.admin.generateLink({type:'recovery',email:recover.email}));
  sql(`update auth.users set recovery_sent_at=now()-interval '2 hours' where id='${recover.id}';`);
  await api(null,'/api/auth/recovery',{action:'verify',token_hash:expired.properties.hashed_token},400);
  await api(null,'/api/auth/recovery',{action:'request',email:recover.email},403,{Origin:'https://untrusted.invalid'});
  pass('expired recovery links and cross-origin reset requests denied');
}catch(error){
  fs.mkdirSync('.tmp/release-20261113',{recursive:true});
  if(diagnosticPage&&!diagnosticPage.isClosed())fs.writeFileSync('.tmp/release-20261113/upload-browser-private.txt',new URL(diagnosticPage.url()).pathname+'\n'+await diagnosticPage.locator('body').innerText().catch(()=>''));
  fs.writeFileSync('.tmp/release-20261113/release-gates-private-error.log',String(error?.stack??error).replace(/(token_hash|access_token|refresh_token|token|code)=([^&\s"'<>]+)/g,'$1=[REDACTED]'));
  console.error('FAIL isolated release gates; diagnostics saved privately in .tmp/release-20261113/release-gates-private-error.log');process.exitCode=1;
}finally{
  await browser?.close();
  for(const account of created){
    await service.from('file_upload_intents').update({expires_at:new Date(Date.now()-1000).toISOString()}).eq('actor_id',account.id).neq('state','complete');
    await service.auth.admin.updateUserById(account.id,{ban_duration:'876000h'});
  }
  await fetch(base+'/api/internal/uploads/cleanup',{headers:{Authorization:'Bearer '+process.env.CRON_SECRET}}).catch(()=>{});
  fs.writeFileSync('.tmp/release-20261113/release-gates-results.json',JSON.stringify({run,results,passed:!process.exitCode,production_modified:false},null,2));
}
