import fs from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {randomUUID} from 'node:crypto';
import assert from 'node:assert/strict';
import {createClient} from '@supabase/supabase-js';
assert.equal(process.env.NEXT_PUBLIC_SUPABASE_URL,'http://127.0.0.1:58921');
const url=process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
const options={auth:{persistSession:false,autoRefreshToken:false}};
const service=createClient(url,process.env.SUPABASE_SERVICE_ROLE_KEY,options);
const teacherAccount=JSON.parse(fs.readFileSync('.tmp/quiz-preview-accounts.json','utf8')).accounts.instructor;
const accounts=JSON.parse(fs.readFileSync('.tmp/activity-browser-accounts.json','utf8'));
const fixture=JSON.parse(fs.readFileSync('.tmp/notification-test-fixture.json','utf8'));
const run=randomUUID().slice(0,8),actor=accounts[1]; // Existing synthetic learner; owner accounts untouched.
async function ok(p){const r=await p;assert(!r.error,r.error?.message);return r.data;}
const teacher=createClient(url,key,options);const signed=await ok(teacher.auth.signInWithPassword({email:teacherAccount.email,password:teacherAccount.password}));
async function api(body,path='homework'){
 const r=await fetch(`http://127.0.0.1:3008/api/activities/${path}`,{method:'POST',headers:{Authorization:`Bearer ${signed.session.access_token}`,'Content-Type':'application/json'},body:JSON.stringify(body)});
 const data=await r.json();assert.equal(r.status,200,data.error);return data.record;
}
const cache=path.join(process.env.LOCALAPPDATA,'npm-cache','_npx');
const module=fs.readdirSync(cache).map(p=>path.join(cache,p,'node_modules','playwright','index.mjs')).find(p=>fs.existsSync(p));
const {chromium}=await import(pathToFileURL(module).href);
const browser=await chromium.launch({headless:true,args:['--enable-unsafe-swiftshader']});
const mobile=await browser.newPage({viewport:{width:375,height:812},reducedMotion:'reduce'});
mobile.setDefaultTimeout(40000);const errors=[];mobile.on('pageerror',e=>errors.push(e.message));
const backendOrigins=new Set();mobile.on('request',r=>{const u=new URL(r.url());if(/^\/(auth|rest|storage)\/v1/.test(u.pathname))backendOrigins.add(u.origin);});
const shots='.tmp/notification-browser';fs.mkdirSync(shots,{recursive:true});
async function semantics(){const p=mobile.locator('flt-semantics-placeholder');await p.waitFor({state:'attached',timeout:180000});await p.evaluate(e=>e.click());}
async function reveal(locator){
 await mobile.mouse.move(Math.min(200,mobile.viewportSize().width/2),500);
 for(let i=0;i<24;i++){
  const b=await locator.count()?await locator.boundingBox().catch(()=>null):null;
  if(b&&b.y>=65&&b.y+b.height<mobile.viewportSize().height-100)return;
  await mobile.mouse.wheel(0,b&&b.y<65?-350:350);await mobile.waitForTimeout(150);
 }
 await locator.waitFor();
}
const bell=()=>mobile.getByRole('button',{name:/Notifications/}).first();
const noticeCard=(title,heading)=>mobile.locator(`[aria-label*="${title}"]`).filter({has:mobile.getByRole('button',{name:'Open activity',exact:true})}).filter({hasText:heading??''}).first();
async function openNotice(title){
 const card=mobile.locator(`[aria-label*="${title}"]`).filter({has:mobile.getByRole('button',{name:'Open activity',exact:true})}).first();
 await reveal(card);await card.getByRole('button',{name:'Open activity',exact:true}).click();
}
async function closeDetails(name){const label=name==='Close assignment'?'Back':name;await reveal(mobile.getByRole('button',{name:label,exact:true}));await mobile.getByRole('button',{name:label,exact:true}).click();}
const pass=m=>console.log(`PASS ${m}`);
try{
 await mobile.goto('http://127.0.0.1:3009');await semantics();
 await mobile.getByRole('button',{name:'Skip',exact:true}).click();await mobile.getByRole('button',{name:'I already have an account',exact:true}).click();
 const learnerEmail=mobile.getByRole('textbox',{name:/email/i}),learnerPassword=mobile.getByRole('textbox',{name:/password/i});
 await learnerEmail.click();await learnerEmail.fill(actor.email);await mobile.waitForTimeout(250);
 await learnerPassword.click();await learnerPassword.fill(actor.password);await mobile.waitForTimeout(250);
 await mobile.getByRole('button',{name:'Log In',exact:true}).click();
 await reveal(bell());await bell().click();
 const markAll=mobile.getByRole('button',{name:'Mark all read',exact:true});await markAll.waitFor();
 if(await markAll.isEnabled())await markAll.click();
 // The same quiz was assigned to A and B. B's notice must resolve to the
 // existing canonical attempt even though the list returns only one quiz row.
 const crossClass=mobile.locator(`[aria-label*="Activities quiz ${fixture.run}"][aria-label*="Activities QA B ${fixture.run}"]`)
   .filter({has:mobile.getByRole('button',{name:'Open activity',exact:true})}).first();
 await reveal(crossClass);await crossClass.getByRole('button',{name:'Open activity',exact:true}).click();
 await mobile.getByRole('button',{name:'Close quiz briefing',exact:true}).waitFor();
 await closeDetails('Close quiz briefing');
 pass('second-class quiz notification resolves to the authorized canonical attempt without exposing version tables');
 await mobile.getByRole('button',{name:'Back',exact:true}).click();
 const quizzes=[];
 for(let i=0;i<2;i++){
  const q=await ok(teacher.rpc('create_instructor_quiz',{p_title:`Notification quiz ${run}-${i}`,p_topic:'Networking'}));
  const v=await ok(teacher.from('quiz_versions').select('id').eq('quiz_id',q.id).single());
  const item=await ok(teacher.rpc('upsert_quiz_item',{p_quiz_version_id:v.id,p_item_type:'true_false',p_prompt:'A router connects IP networks.',p_options:[],p_correct_answer:'True',p_order_index:1}));
  await ok(teacher.rpc('review_quiz_item',{p_item_id:item.id,p_decision:'approved'}));
  await ok(teacher.rpc('publish_and_assign_quiz',{p_quiz_version_id:v.id,p_class_ids:[fixture.classA]}));
  const a=await ok(teacher.from('quiz_assignments').select('id').eq('quiz_version_id',v.id).single());quizzes.push({...q,assignment:a.id});
 }
 const homework=[];
 for(let i=0;i<2;i++){
  const h=await api({action:'create',class_id:fixture.classA,title:`Notification homework ${run}-${i}`,instructions:'Inspect the network outside ByteQuest, then submit your report.',deadline_at:new Date(Date.now()+(i?86400000:-195300000)).toISOString()});
  await api({action:'publish',assignment_id:h.id});homework.push(h);
 }
 // No navigation/reload: active Home polling alone must update its bell.
 await mobile.locator('[aria-label*="Notifications, 4 unread"]').first().waitFor({timeout:40000});
 pass('active Home bell receives new quiz/homework events without Realtime or page reload');
 for(const width of [320,375,768,1440]){
  await mobile.setViewportSize({width,height:900});await reveal(bell());await mobile.screenshot({path:`${shots}/home-${width}.png`});
  assert(await mobile.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));
 }
 await mobile.setViewportSize({width:375,height:812});await reveal(bell());await bell().click();
 await openNotice(quizzes[0].title);await mobile.getByRole('button',{name:'Close quiz briefing',exact:true}).waitFor();
 assert.equal((await ok(service.from('quiz_attempts').select('id').eq('learner_id',actor.id).eq('quiz_assignment_id',quizzes[0].assignment))).length,0);
 await closeDetails('Close quiz briefing');
 await openNotice(homework[0].title);await mobile.getByRole('textbox',{name:/Written answer/i}).waitFor();
 const late=mobile.getByText('Deadline Passed — Late Submission Allowed',{exact:true}).or(mobile.locator('[aria-label*="Deadline Passed — Late Submission Allowed"]')).first();await late.waitFor();
 const answer='Notification test: inspected cables and recorded network findings.';
 const answerInput=mobile.getByRole('textbox',{name:/Written answer/i});
 await answerInput.click();await answerInput.fill(answer);await mobile.waitForTimeout(250);
 assert.equal(await answerInput.inputValue(),answer);
 await answerInput.press('Tab');await mobile.waitForTimeout(200);
 await reveal(mobile.getByRole('button',{name:'Review submission',exact:true}));await mobile.getByRole('button',{name:'Review submission',exact:true}).click();await mobile.getByRole('button',{name:'Submit Assignment',exact:true}).click();
 await mobile.getByText('Submitted for Grading',{exact:true}).or(mobile.locator('[aria-label*="Submitted for Grading"]')).first().waitFor();
 const sub=await ok(service.from('homework_submissions').select('*').eq('assignment_id',homework[0].id).eq('learner_id',actor.id).single());assert(sub.lateness_seconds>=195300);
 await closeDetails('Close assignment');
 await api({action:'grade',assignment_id:homework[0].id,submission_id:sub.id,feedback:'Reviewed through notification workflow.',score:null});
 await mobile.getByRole('button',{name:'Refresh notifications',exact:true}).click();
 await openNotice(homework[0].title);await mobile.getByText('Graded',{exact:true}).or(mobile.locator('[aria-label*="Graded"]')).first().waitFor();
 await closeDetails('Close assignment');
 const gradeNotice=await ok(service.from('notifications').select('*').eq('event_key',`homework.graded:${sub.id}`));assert.equal(gradeNotice.length,1);assert.equal(gradeNotice[0].user_id,actor.id);
 pass('quiz/homework links revalidate and open the correct current screen; late homework remains submitted and gradeable; grading alert is private');
 await ok(service.from('quiz_assignments').update({due_at:new Date(Date.now()-1000).toISOString()}).eq('id',quizzes[0].assignment));
 await api({assignment_id:quizzes[0].assignment,deadline_at:new Date(Date.now()+86400000).toISOString(),reopen:true},'quiz-deadline');
 await mobile.getByRole('button',{name:'Refresh notifications',exact:true}).click();
 await openNotice(quizzes[0].title);await mobile.getByRole('button',{name:'Not started — 1 attempt available',exact:true}).waitFor();
 await closeDetails('Close quiz briefing');
 const technical=(await ok(service.from('notifications').select('*').eq('user_id',actor.id).eq('event_key',`assignment.created:${fixture.technical}`))).at(0);assert(technical);
 const technicalTitle=(await ok(service.from('assignments').select('title').eq('id',fixture.technical).single())).title;
 await openNotice(technicalTitle);await mobile.getByRole('button',{name:'Close class details',exact:true}).waitFor();
 await mobile.getByRole('button',{name:'Open activity',exact:true}).waitFor();
 assert.equal((await ok(service.from('attempts').select('id').eq('assignment_id',fixture.technical).eq('learner_id',actor.id))).length,0);
 await closeDetails('Close class details');
 pass('reopened quiz notification shows current availability; technical notification reviews the exact assignment without creating an attempt');
 // The header row is virtualized after reading older notices. Return to the
 // top explicitly rather than searching downward for a row above the viewport.
 await mobile.mouse.move(180,350);await mobile.mouse.wheel(0,-30000);await mobile.waitForTimeout(500);
 await reveal(mobile.getByRole('button',{name:'Mark all read',exact:true}));
 await mobile.getByRole('button',{name:'Mark all read',exact:true}).click();
 await mobile.getByText('Unread (0)',{exact:true}).or(mobile.locator('[aria-label*="Unread (0)"]')).first().waitFor();
 await mobile.reload();await semantics();await reveal(bell());
 await mobile.locator('[aria-label*="Notifications, 0 unread"]').first().waitFor();
 await bell().click();
 // Revocation applies only to this synthetic learner, preserving all history.
 await ok(service.from('class_memberships').update({status:'deactivated',deactivated_at:new Date().toISOString(),deactivated_by:teacherAccount.id,deactivation_reason:'Notification destination revocation test'}).eq('learner_id',actor.id).eq('class_id',fixture.classA));
 await openNotice(homework[1].title);
 await mobile.getByText('This activity is no longer available to your account. Refresh your activities or contact your instructor.',{exact:true}).or(mobile.locator('[aria-label*="This activity is no longer available to your account"]')).first().waitFor();
 await mobile.screenshot({path:`${shots}/revoked-destination.png`});
 assert.deepEqual([...backendOrigins],['http://127.0.0.1:58921']);assert.deepEqual(errors,[]);
 pass('read status/badge persists after refresh; revoked destination denied; all Auth/REST/Storage requests use isolated QA');
}catch(error){console.error(`FAIL ${error.message.split('\n')[0]}`);console.error(error.stack?.split('\n').find(x=>x.includes('notification-browser-tests.mjs'))??'');await mobile.screenshot({path:`${shots}/failure.png`}).catch(()=>{});fs.writeFileSync(`${shots}/semantics.html`,await mobile.content());process.exitCode=1;}
finally{await browser.close();}
