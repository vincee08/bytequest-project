import { test } from 'node:test';
import assert from 'node:assert/strict';
import { practiceBank, selectPracticeQuestions } from '../src/lib/practice/question-bank';
import { generatePracticeQuestions } from '../src/lib/practice/free-quiz';
import { practiceQuizView } from '../src/lib/practice/quiz-view';
import type { PracticeAttempt } from '../src/lib/practice/database';
import type { Json } from '../src/types/database.generated';

test('every COC bank yields five distinct valid MCQs with teaching explanations',()=>{
  for(const coc of Object.keys(practiceBank)) for(let run=0;run<12;run++) {
    const items=selectPracticeQuestions(coc); assert.equal(items.length,5);assert.equal(new Set(items.map(q=>q.id)).size,5);
    for(const q of items) {assert.equal(new Set(q.choices).size,4);assert.ok(q.choices[q.answer]);assert.ok(q.explanation.length>20);assert.ok(q.page>=1&&q.page<=7);}
  }
});
test('answer keys and explanations remain secret until submission',()=>{
  const a={id:'attempt',coc_code:'coc1',status:'active',source:'bank',answers:{},questions:selectPracticeQuestions('coc1') as unknown as Json,passing_percent:80,score:null,passed:null} as PracticeAttempt;
  assert.ok(practiceQuizView(a).questions.every(q=>!('answer' in q)&&!('explanation' in q)));
  assert.ok(practiceQuizView({...a,status:'submitted',score:4,passed:true}).questions.every(q=>'answer' in q&&'explanation' in q));
});
test('missing credentials, paid models, quota failures and malformed AI output use the bank',async()=>{
  const originalFetch=global.fetch;const key=process.env.OPENROUTER_API_KEY;const model=process.env.PRACTICE_OPENROUTER_MODEL;
  const bank=selectPracticeQuestions('coc1');let calls=0;
  try {
    delete process.env.OPENROUTER_API_KEY; assert.equal((await generatePracticeQuestions(bank,'coc1')).source,'bank');
    process.env.OPENROUTER_API_KEY='test';process.env.PRACTICE_OPENROUTER_MODEL='paid/model';
    global.fetch=async()=>{calls++;return new Response('',{status:429});};
    assert.equal((await generatePracticeQuestions(bank,'coc1')).source,'bank');assert.equal(calls,0);
    process.env.PRACTICE_OPENROUTER_MODEL='openrouter/free';assert.equal((await generatePracticeQuestions(bank,'coc1')).source,'bank');
    global.fetch=async()=>Response.json({choices:[{message:{content:'{"questions":[]}'}}]});
    assert.equal((await generatePracticeQuestions(bank,'coc1')).source,'bank');
  } finally {global.fetch=originalFetch;if(key===undefined)delete process.env.OPENROUTER_API_KEY;else process.env.OPENROUTER_API_KEY=key;if(model===undefined)delete process.env.PRACTICE_OPENROUTER_MODEL;else process.env.PRACTICE_OPENROUTER_MODEL=model;}
});
test('AI variants preserve trusted choices, keys, explanations and zero-price routing',async()=>{
  const originalFetch=global.fetch;const key=process.env.OPENROUTER_API_KEY;const model=process.env.PRACTICE_OPENROUTER_MODEL;
  const bank=selectPracticeQuestions('coc3');
  try {
    process.env.OPENROUTER_API_KEY='test';process.env.PRACTICE_OPENROUTER_MODEL='openrouter/free';
    global.fetch=async(_url,init)=>{
      const body=JSON.parse(init!.body as string);assert.equal(body.provider.max_price.prompt,0);assert.equal(body.provider.max_price.completion,0);
      return Response.json({choices:[{message:{content:JSON.stringify({questions:bank.map(q=>({id:q.id,question:'During the work order: '+q.question}))})}}]});
    };
    const result=await generatePracticeQuestions(bank,'coc3');assert.equal(result.source,'ai');
    for(let i=0;i<5;i++){assert.deepEqual(result.questions[i].choices,bank[i].choices);assert.equal(result.questions[i].answer,bank[i].answer);assert.equal(result.questions[i].explanation,bank[i].explanation);}
  } finally {global.fetch=originalFetch;if(key===undefined)delete process.env.OPENROUTER_API_KEY;else process.env.OPENROUTER_API_KEY=key;if(model===undefined)delete process.env.PRACTICE_OPENROUTER_MODEL;else process.env.PRACTICE_OPENROUTER_MODEL=model;}
});
test('AI cannot change work-order quantities or repeat question stems',async()=>{
  const originalFetch=global.fetch;const key=process.env.OPENROUTER_API_KEY;const model=process.env.PRACTICE_OPENROUTER_MODEL;
  const bank=practiceBank.coc3.slice(0,5);
  try {
    process.env.OPENROUTER_API_KEY='test';process.env.PRACTICE_OPENROUTER_MODEL='openrouter/free';
    global.fetch=async()=>Response.json({choices:[{message:{content:JSON.stringify({questions:bank.map(q=>({id:q.id,question:q.question.replace('445','80')}))})}}]});
    assert.equal((await generatePracticeQuestions(bank,'coc3')).source,'bank');
    global.fetch=async()=>Response.json({choices:[{message:{content:JSON.stringify({questions:bank.map(q=>({id:q.id,question:'Which server procedure follows the work order?'}))})}}]});
    assert.equal((await generatePracticeQuestions(bank,'coc3')).source,'bank');
  } finally {global.fetch=originalFetch;if(key===undefined)delete process.env.OPENROUTER_API_KEY;else process.env.OPENROUTER_API_KEY=key;if(model===undefined)delete process.env.PRACTICE_OPENROUTER_MODEL;else process.env.PRACTICE_OPENROUTER_MODEL=model;}
});
