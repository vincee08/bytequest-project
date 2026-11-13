import assert from 'node:assert/strict';
import fs from 'node:fs';
import {createClient} from '@supabase/supabase-js';
import {authorizeResourceSource,downloadResourceSource} from '../ByteQuest-Web-Dashboard/src/lib/ai/resource-source';
import {extractResourcePdf} from '../ByteQuest-Web-Dashboard/src/lib/resources/pdf';
assert.equal(process.env.NEXT_PUBLIC_SUPABASE_URL,'http://127.0.0.1:58921');
const uploaded=JSON.parse(fs.readFileSync('../.tmp/release-20261113/direct-source-fixture.json','utf8'));
const client=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!,process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,{auth:{persistSession:false,autoRefreshToken:false}});
const auth=await client.auth.signInWithPassword({email:process.env.BQ_QA_INSTRUCTOR_EMAIL!,password:process.env.BQ_QA_INSTRUCTOR_PASSWORD!});assert(!auth.error);
try{
  const resource=await authorizeResourceSource(client,auth.data.user!.id,uploaded.classId,uploaded.smallId);
  const parsed=await extractResourcePdf(await downloadResourceSource(client,resource));assert.match(parsed.text,/router connects different IP networks/);
  await assert.rejects(authorizeResourceSource(client,auth.data.user!.id,uploaded.classId,uploaded.largeId),/RESOURCE_SOURCE_UNAVAILABLE/);
  console.log('PASS direct-upload PDF parsing and 50 MiB AI-source rejection before download/provider access');
}finally{await client.auth.signOut({scope:'local'});}
