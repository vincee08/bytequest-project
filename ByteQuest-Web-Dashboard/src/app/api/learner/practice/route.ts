import { randomUUID } from 'node:crypto';
import { NextResponse } from 'next/server';
import { z } from 'zod';
import type { Json } from '@/types/database.generated';
import { practiceServerClient } from '@/lib/practice/database';
import { selectPracticeQuestions } from '@/lib/practice/question-bank';
import { generatePracticeQuestions } from '@/lib/practice/free-quiz';
import { practiceQuizView } from '@/lib/practice/quiz-view';

export const runtime='nodejs';
export const maxDuration=60;
const coc=z.enum(['coc1','coc2','coc3','coc4']);
const answers=z.record(z.string().max(80),z.number().int().min(0).max(3)).refine(a=>Object.keys(a).length<=5);
const requestSchema=z.discriminatedUnion('action',[
  z.object({action:z.literal('verify'),mission:z.string().regex(/^coc[1-4]_m[1-5]$/)}).strict(),
  z.object({action:z.literal('begin'),coc}).strict(),
  z.object({action:z.literal('save'),id:z.string().uuid(),answers}).strict(),
  z.object({action:z.literal('submit'),id:z.string().uuid(),answers}).strict(),
]);
function reply(body:unknown,status=200) { return NextResponse.json(body,{status,headers:{'Cache-Control':'no-store'}}); }
async function actor(request:Request) {
  const token=request.headers.get('authorization')?.match(/^Bearer (\S+)$/)?.[1];
  if (!token) return null;
  const client=practiceServerClient();
  const {data,error}=await client.auth.getUser(token);
  if (error || !data.user) return null;
  const {data:profile,error:profileError}=await client.from('profiles').select('role,status').eq('user_id',data.user.id).maybeSingle();
  return !profileError && profile?.role==='learner' && profile.status==='active' ? {client,id:data.user.id}:null;
}
export async function GET(request:Request) {
  try {
    const user=await actor(request); if (!user) return reply({error:'Active Learner access is required.'},401);
    const id=new URL(request.url).searchParams.get('attempt');
    if (!id || !z.string().uuid().safeParse(id).success) return reply({error:'Choose a valid quiz attempt.'},400);
    const {data,error}=await user.client.from('practice_quiz_attempts').select('*').eq('id',id).eq('learner_id',user.id).maybeSingle();
    if(error) return reply({error:'Quiz temporarily unavailable.'},503);
    return data ? reply(practiceQuizView(data)) : reply({error:'Quiz not found.'},404);
  } catch { return reply({error:'Practice service temporarily unavailable.'},503); }
}
export async function POST(request:Request) {
  try {
    const user=await actor(request); if (!user) return reply({error:'Active Learner access is required.'},401);
    if(Number(request.headers.get('content-length')??0)>8192) return reply({error:'Request too large.'},413);
    const raw=await request.text(); if(raw.length>8192) return reply({error:'Request too large.'},413);
    let body:unknown;
    try { body=JSON.parse(raw); } catch { return reply({error:'Invalid practice request.'},400); }
    const parsed=requestSchema.safeParse(body); if(!parsed.success) return reply({error:'Invalid practice request.'},400);
    const input=parsed.data;
    if(input.action==='verify') {
      const {error}=await user.client.rpc('practice_verify_mission',{p_learner:user.id,p_mission:input.mission});
      return error ? reply({error:'Complete and verify each work phase before submitting practice evidence.'},error.code==='42501'?403:422) : reply({verified:true});
    }
    if(input.action==='begin') {
      const id=randomUUID();
      const bank=selectPracticeQuestions(input.coc);
      const {data,error}=await user.client.rpc('practice_begin_quiz',{p_learner:user.id,p_coc:input.coc,p_id:id,p_questions:bank as unknown as Json});
      if(error || !data) return reply({error:error?.code==='54000' ? 'Daily practice quiz limit reached. Resume an existing quiz or return tomorrow.' : 'Complete all five missions and the earlier COCs before taking this quiz.'},error?.code==='54000'?429:403);
      if(data.id===id) {
        const generated=await generatePracticeQuestions(bank,input.coc);
        const {data:ready,error:saveError}=await user.client.from('practice_quiz_attempts')
          .update({questions:generated.questions as unknown as Json,source:generated.source,status:'active'})
          .eq('id',id).eq('status','generating').select('*').maybeSingle();
        if(saveError) return reply({error:'The quiz could not be saved. Retry to resume.'},503);
        if(ready) return reply(practiceQuizView(ready));
        const {data:recovered,error:recoverError}=await user.client.from('practice_quiz_attempts').select('*').eq('id',id).eq('learner_id',user.id).single();
        if(recoverError) return reply({error:'Retry to resume your saved quiz.'},503);
        return reply(practiceQuizView(recovered));
      }
      return reply(practiceQuizView(data),data.status==='generating'?202:200);
    }
    if(input.action==='submit') {
      const {data,error}=await user.client.rpc('practice_submit_quiz',{p_learner:user.id,p_attempt:input.id,p_answers:input.answers});
      return error || !data ? reply({error:'Answer all five questions and retry submission.'},422) : reply(practiceQuizView(data));
    }
    const {data:owned,error:readError}=await user.client.from('practice_quiz_attempts').select('*').eq('id',input.id).eq('learner_id',user.id).maybeSingle();
    if(readError || !owned || owned.status!=='active') return reply({error:'An active owned quiz is required.'},403);
    const ids=new Set((owned.questions as unknown as Array<{id:string}>).map(q=>q.id));
    if(Object.keys(input.answers).some(id=>!ids.has(id))) return reply({error:'Invalid question identifier.'},400);
    const {data:saved,error:saveError}=await user.client.from('practice_quiz_attempts').update({answers:input.answers})
      .eq('id',input.id).eq('learner_id',user.id).eq('status','active').select('*').maybeSingle();
    return saveError || !saved ? reply({error:'Answers could not be saved. Retry.'},409) : reply(practiceQuizView(saved));
  } catch { return reply({error:'Practice service temporarily unavailable.'},503); }
}
