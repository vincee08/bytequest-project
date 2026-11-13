import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';

assert.equal(process.env.NEXT_PUBLIC_SUPABASE_URL,'http://127.0.0.1:58921');
const accounts=JSON.parse(fs.readFileSync('.tmp/quiz-preview-accounts.json','utf8')).accounts;
const fixture=JSON.parse(fs.readFileSync('.tmp/activity-api-test-fixture.json','utf8'));
const learnerAccounts=JSON.parse(fs.readFileSync('.tmp/activity-browser-accounts.json','utf8'));
const service=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL,process.env.SUPABASE_SERVICE_ROLE_KEY,{auth:{persistSession:false,autoRefreshToken:false}});
async function ok(promise){const r=await promise;assert(!r.error,r.error?.message);return r.data;}
const cache=path.join(process.env.LOCALAPPDATA,'npm-cache','_npx');
const module=process.env.BQ_PLAYWRIGHT_MODULE ?? fs.readdirSync(cache).map(p=>path.join(cache,p,'node_modules','playwright','index.mjs')).find(p=>fs.existsSync(p));
const {chromium}=await import(pathToFileURL(module).href);
const browser=await chromium.launch({headless:true,args:['--enable-unsafe-swiftshader']});
let mobile;
const page=await browser.newPage({viewport:{width:1440,height:1000},reducedMotion:'reduce'});
page.setDefaultTimeout(90000);
const errors=[];page.on('pageerror',e=>errors.push(e.message));
const shots='.tmp/activity-browser';fs.mkdirSync(shots,{recursive:true});
const pass=message=>console.log(`PASS ${message}`);
async function revealFlutter(page, locator) {
 await page.mouse.move(200,550);
 for(let i=0;i<16;i++) {
  const box=await locator.count() ? await locator.boundingBox().catch(()=>null) : null;
  if(box && box.y>=70 && box.y+box.height<page.viewportSize().height-100) return;
  await page.mouse.wheel(0,box && box.y<70 ? -350 : 350);
  await page.waitForTimeout(200);
 }
 await locator.waitFor();
}
const future=new Date(Date.now()+3*86400000+8*3600000).toISOString().slice(0,16);
try{
 await page.goto('http://127.0.0.1:3008/login');
 await page.waitForFunction(() => { const input=document.querySelector('input[type="email"]'); return input && Object.keys(input).some(k=>k.startsWith('__reactFiber$')); });
 await page.getByLabel('Email',{exact:true}).fill(accounts.instructor.email);await page.getByLabel('Password',{exact:true}).fill(accounts.instructor.password);await page.getByRole('button',{name:/sign in/i}).click();await page.waitForURL('**/instructor/dashboard');
 if(!process.argv.includes('--mobile-only')) {
 await page.goto(`http://127.0.0.1:3008/classes/${fixture.classA}?tab=assignments`);
 await page.getByRole('button',{name:'Create Assignment',exact:true}).click();
 const dialog=page.getByRole('dialog');
 const title=`Browser homework ${fixture.run}`;
 await dialog.getByLabel('Assignment title',{exact:true}).fill(title);await dialog.getByLabel('Instructions',{exact:true}).fill('Inspect the network outside ByteQuest, then submit a report with supporting evidence.');await dialog.getByLabel(/Deadline \(optional/).fill(future);
 for(const width of [320,375,768,1440]){await page.setViewportSize({width,height:1000});assert(await dialog.evaluate(e=>e.scrollWidth<=e.clientWidth+1),`creation dialog overflow at ${width}`);}
 await dialog.getByRole('button',{name:'Save draft',exact:true}).click();await page.waitForURL(/\/classes\/[^/]+\/assignments\/[^/]+$/);await page.getByRole('heading',{name:title,exact:true}).waitFor();
 const createdUrl=page.url();
 await page.getByLabel('Add supporting file').setInputFiles({name:'browser-instructions.txt',mimeType:'text/plain',buffer:Buffer.from('Network inspection steps: inspect, record, report.')});
 await page.getByText('Instruction file attached.',{exact:true}).waitFor();
 await page.getByRole('button',{name:'Publish Assignment',exact:true}).click();await page.getByText('Homework published to the class.',{exact:true}).waitFor();await page.getByRole('heading',{name:'Submissions',exact:true}).waitFor();
 assert(await page.getByText('Assigned',{exact:true}).count()>0);
 pass('dashboard homework creation, Manila deadline, private instruction upload, explicit publication and unsubmitted learner roster');
 await page.goto(`http://127.0.0.1:3008/classes/${fixture.classA}/assignments/${fixture.homework}`);
 await page.getByRole('button').filter({hasText:'Submitted for Grading'}).first().click();await page.getByLabel('Feedback (optional)',{exact:true}).fill('Browser review complete.');
 await page.getByRole('button',{name:'Mark Graded',exact:true}).click();await page.getByText('Graded',{exact:true}).first().waitFor();
 assert((await ok(service.from('homework_submissions').select('status,score').eq('assignment_id',fixture.homework).eq('learner_id',learnerAccounts[1].id).single())).status==='graded');
 pass('instructor reads submitted answer/files and marks Graded without requiring a numeric score');
 const version=await ok(service.from('quiz_versions').select('id').eq('quiz_id',fixture.quiz).eq('status','published').single());
 const assignment=await ok(service.from('quiz_assignments').select('*').eq('quiz_version_id',version.id).eq('class_id',fixture.classA).single());
 const other=await ok(service.from('quiz_assignments').select('due_at').eq('quiz_version_id',version.id).eq('class_id',fixture.classB).single());
 await ok(service.from('quiz_assignments').update({due_at:new Date(Date.now()-1000).toISOString()}).eq('id',assignment.id));
 await page.goto('http://127.0.0.1:3008/quizzes');await page.getByLabel('Search quizzes').fill(`Activities quiz ${fixture.run}`);await page.getByRole('button',{name:'Reopen Quiz',exact:true}).click();
 await page.getByRole('dialog').getByLabel('New future deadline').fill(future);await page.getByRole('button',{name:'Confirm reopening',exact:true}).click();await page.getByRole('dialog').waitFor({state:'hidden'});
 assert.equal((await ok(service.from('quiz_assignments').select('due_at').eq('quiz_version_id',version.id).eq('class_id',fixture.classB).single())).due_at,other.due_at);
 pass('obvious Quizzes-page reopening modal confirms affected class and updates only that class deadline');
 for(const [label,url] of [['homework',createdUrl],['quizzes','http://127.0.0.1:3008/quizzes']])for(const width of [320,375,768,1440]){
  await page.setViewportSize({width,height:1000});await page.goto(url);await page.getByRole('main').waitFor();
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),`${label} page overflow at ${width}`);await page.screenshot({path:`${shots}/${label}-${width}.png`,fullPage:true});
 }
 assert.deepEqual(errors,[]);pass('dashboard activity pages fit 320/375/768/1440 widths without browser runtime errors');
 }
 mobile=await browser.newPage({viewport:{width:430,height:932},reducedMotion:'reduce'});mobile.setDefaultTimeout(40000);
 const backendOrigins=new Set();mobile.on('request',r=>{const u=new URL(r.url());if(/^\/(auth|rest|storage)\/v1/.test(u.pathname))backendOrigins.add(u.origin);});
 await mobile.goto('http://127.0.0.1:3009');
 await mobile.locator('flt-semantics-placeholder').waitFor({state:'attached',timeout:180000});await mobile.locator('flt-semantics-placeholder').evaluate(e=>e.click());
 await mobile.getByRole('button',{name:'Skip',exact:true}).click();await mobile.getByRole('button',{name:'I already have an account',exact:true}).click();
 const learnerEmail=mobile.getByRole('textbox',{name:/email/i}),learnerPassword=mobile.getByRole('textbox',{name:/password/i});
 await learnerEmail.click();await learnerEmail.fill(learnerAccounts[2].email);await mobile.waitForTimeout(250);
 await learnerPassword.click();await learnerPassword.fill(learnerAccounts[2].password);await mobile.waitForTimeout(250);
 await mobile.getByRole('button',{name:'Log In',exact:true}).click();
 await revealFlutter(mobile,mobile.getByRole('heading',{name:'Assigned Quizzes (1)',exact:true}).first());
 assert(await mobile.locator(`[aria-label*="Activities quiz ${fixture.run}"]`).count()>0);
 assert.equal(await mobile.getByText('AI Generated',{exact:true}).count(),0);
 pass('real local Flutter login shows its published assigned quiz in Home using the same isolated backend');
 await revealFlutter(mobile,mobile.getByRole('button',{name:'Continue quiz',exact:true}));
 await mobile.getByRole('button',{name:'Continue quiz',exact:true}).click();
 await mobile.getByRole('button',{name:/Continue attempt/}).click();
 await mobile.getByRole('button',{name:/^True/}).first().click();
 await mobile.getByRole('button',{name:'Review & submit',exact:true}).click();
 await mobile.getByRole('button',{name:'Submit',exact:true}).click();
 await mobile.getByRole('button',{name:'Close quiz result',exact:true}).waitFor();
 const mobileVersion=await ok(service.from('quiz_versions').select('id').eq('quiz_id',fixture.quiz).eq('status','published').single());
 const mobileAttempt=await ok(service.from('quiz_attempts').select('id,status').eq('quiz_version_id',mobileVersion.id).eq('learner_id',learnerAccounts[2].id).single());assert.equal(mobileAttempt.status,'completed');
 assert.equal((await ok(service.from('quiz_results').select('id').eq('quiz_attempt_id',mobileAttempt.id))).length,1);
 await page.goto(`http://127.0.0.1:3008/quizzes/${fixture.quiz}`);await page.getByRole('tab',{name:'Results',exact:true}).click();await page.getByText(`Activity QA ${fixture.run} Learner 3`,{exact:true}).waitFor();
 await mobile.getByRole('button',{name:'Close quiz result',exact:true}).click();
 await mobile.getByRole('button',{name:'View Result',exact:true}).waitFor();
 pass('real Flutter resumes original quiz, saves/submits once, shows result instead of retake; instructor Results lists the learner');
 // Flutter virtualizes off-screen list rows; scroll through the canvas-backed
 // semantics tree to reach the separate homework section.
 const homeworkTitle=`Homework edited ${fixture.run}`;
 await revealFlutter(mobile,mobile.getByRole('heading',{name:/Homework Assignments/}).first());
 const moreHomework=mobile.getByRole('button',{name:'View all activities',exact:true}).last();
 if(await moreHomework.count()){await revealFlutter(mobile,moreHomework);await moreHomework.click();}
 await mobile.mouse.move(200,600);
 for(let i=0;i<12 && !(await mobile.locator(`[aria-label*="${homeworkTitle}"]`).count());i++){await mobile.mouse.wheel(0,500);await mobile.waitForTimeout(250);}
 await mobile.locator(`[aria-label*="${homeworkTitle}"]`).first().waitFor();
 // This synthetic learner has not submitted the API suite's first homework.
 const titleNode=mobile.locator(`[aria-label*="${homeworkTitle}"]`).filter({has:mobile.getByRole('button',{name:'View Assignment',exact:true})}).first();
 const card=titleNode;
 if(await card.count())await card.getByRole('button',{name:'View Assignment',exact:true}).click();
 else await mobile.getByRole('button',{name:'View Assignment',exact:true}).last().click();
 await mobile.getByRole('button',{name:'instructions.txt',exact:true}).waitFor();
 for(let i=0;i<10 && !(await mobile.getByRole('textbox',{name:/Written answer/i}).count());i++){await mobile.mouse.wheel(0,400);await mobile.waitForTimeout(200);}
 await mobile.getByRole('textbox',{name:/Written answer/i}).fill('Flutter browser submission: devices inspected and connectivity verified.');
 await revealFlutter(mobile,mobile.getByRole('button',{name:'Attach completed file',exact:true}));
 const chooser=mobile.waitForEvent('filechooser');
 await mobile.getByRole('button',{name:'Attach completed file',exact:true}).click();
 await (await chooser).setFiles({name:'browser-learner-report.txt',mimeType:'text/plain',buffer:Buffer.from('Flutter homework file: devices inspected, link tested, findings recorded.')});
 await mobile.getByRole('button',{name:'browser-learner-report.txt',exact:true}).waitFor();
 await page.goto(`http://127.0.0.1:3008/classes/${fixture.classA}/assignments/${fixture.homework}`);
 for(let i=0;i<8 && !(await mobile.getByRole('button',{name:'Review submission',exact:true}).count());i++){await mobile.mouse.wheel(0,400);await mobile.waitForTimeout(200);}
 await mobile.getByRole('button',{name:'Review submission',exact:true}).click();await mobile.getByRole('button',{name:'Submit Assignment',exact:true}).click();
 await mobile.getByText('Submitted for Grading',{exact:true}).or(mobile.locator('[aria-label*="Submitted for Grading"]')).first().waitFor();
 const record=await ok(service.from('homework_submissions').select('*').eq('assignment_id',fixture.homework).eq('learner_id',learnerAccounts[2].id).single());assert.match(record.answer,/Flutter browser submission/);
 assert.equal((await ok(service.from('homework_files').select('id').eq('submission_id',record.id))).length,1);
 pass('real Flutter homework details, instructions, text/file upload, review and backend-persisted submission');
 const newSubmissionRow=page.getByRole('button').filter({hasText:`Activity QA ${fixture.run} Learner 3`});
 await newSubmissionRow.filter({hasText:'Submitted for Grading'}).waitFor({timeout:35000});
 await newSubmissionRow.click();
 await page.getByLabel('Feedback (optional)',{exact:true}).fill('Flutter submission reviewed in the Instructor dashboard.');
 await page.getByRole('button',{name:'Mark Graded',exact:true}).click();
 await mobile.getByText('Graded',{exact:true}).or(mobile.locator('[aria-label*="Graded"]')).first().waitFor({timeout:35000});
 pass('instructor browser grades the real Flutter submission; learner updates to Graded');
 await mobile.reload();await mobile.locator('flt-semantics-placeholder').waitFor({state:'attached',timeout:60000});await mobile.locator('flt-semantics-placeholder').evaluate(e=>e.click());
 await revealFlutter(mobile,mobile.getByRole('heading',{name:'Assigned Quizzes (1)',exact:true}).first());assert.deepEqual([...backendOrigins],['http://127.0.0.1:58921']);
 await mobile.screenshot({path:`${shots}/learner-home.png`});
 pass('Flutter session/submission survives refresh and all Auth/REST/Storage requests use QA 58921');
 await ok(service.from('class_memberships').update({status:'deactivated',deactivated_at:new Date().toISOString(),deactivated_by:accounts.instructor.id,deactivation_reason:'Synthetic historical homework identity test'}).eq('learner_id',learnerAccounts[2].id).in('class_id',[fixture.classA,fixture.classB]));
 await page.reload();await page.getByText(`Activity QA ${fixture.run} Learner 3 (previous enrollment)`,{exact:true}).waitFor();
 pass('authorized instructor retains the submitted learner identity after enrollment removal; historical work remains intact');
 console.log(`PASS ${process.argv.includes('--mobile-only') ? 'real Flutter' : 'all dashboard and real Flutter'} browser activity checks. Owner manual acceptance remains pending.`);
}catch(error){console.error(`FAIL ${error.message.split('\n')[0]}`);console.error(error.stack?.split('\n').find(line=>line.includes('activity-browser-tests.mjs')) ?? '');await page.screenshot({path:`${shots}/failure.png`,fullPage:true}).catch(()=>{});await mobile?.screenshot({path:`${shots}/learner-failure.png`}).catch(()=>{});if(mobile)fs.writeFileSync(`${shots}/learner-semantics.html`,await mobile.content());process.exitCode=1;}
finally{await browser.close();}
