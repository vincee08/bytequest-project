import {readdirSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const cwd=fileURLToPath(new URL('../ByteQuest-Web-Dashboard/',import.meta.url));
const server=new Set(['openrouter-quiz-provider.test.ts','resource-content.test.ts','resource-quiz-provider.test.ts','secure-upload-recovery.test.ts','practice-quiz.test.ts','quiz-grounding.test.ts','roster-parse.test.ts']);
const all=readdirSync(new URL('../ByteQuest-Web-Dashboard/tests/',import.meta.url)).filter(f=>/\.test\.(ts|tsx)$/.test(f));
for(const isServer of [false,true]){
  const files=all.filter(f=>server.has(f)===isServer).map(f=>'tests/'+f);
  const r=spawnSync(process.execPath,[...(isServer?['--conditions=react-server']:[]),'--import','tsx','--test',...files],{cwd,env:process.env,stdio:'inherit'});
  if(r.status!==0)process.exit(r.status??1);
}
