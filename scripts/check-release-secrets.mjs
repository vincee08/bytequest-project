// Prints only counts/status. Secret values are read in memory and never emitted.
import fs from 'node:fs';
import path from 'node:path';
import {parseEnv} from 'node:util';
import {execFileSync} from 'node:child_process';
const base=process.argv[2]??'bytequest-project/vince-branch';
execFileSync('git',['rev-parse','--verify',base],{stdio:'pipe'});
const patch=execFileSync('git',['diff','--binary',base],{encoding:'utf8',maxBuffer:30000000});
const staged=execFileSync('git',['diff','--cached','--binary'],{encoding:'utf8',maxBuffer:30000000});
const paths=execFileSync('git',['diff','--cached','--name-only'],{encoding:'utf8'}).trim().split(/\r?\n/).filter(Boolean);
if(paths.some(p=>/(^|\/)(\.env(?:\..*)?|key\.properties|\.tmp|build|\.dart_tool)(\/|$)|\.(apk|aab|ipa|jks|keystore|p12)$/i.test(p)))throw Error('A prohibited private/build path is staged.');
const secrets=[];
for(const file of ['ByteQuest-Web-Dashboard/.env.local','ByteQuest-Mobile-App/.env','.tmp/quiz-ai.env']){
  if(!fs.existsSync(file))continue;
  const env=parseEnv(fs.readFileSync(file,'utf8'));
  for(const [name,value] of Object.entries(env))if(/KEY|PASSWORD|SECRET|TOKEN/.test(name)&&value.length>12)secrets.push(value);
}
const signing='ByteQuest-Mobile-App/android/key.properties';
if(fs.existsSync(signing))for(const line of fs.readFileSync(signing,'utf8').split(/\r?\n/)){const m=line.match(/^(?:storePassword|keyPassword)=(.+)$/);if(m)secrets.push(m[1]);}
const qa='.tmp/quiz-preview-accounts.json';
if(fs.existsSync(qa)){const fixture=JSON.parse(fs.readFileSync(qa,'utf8'));for(const a of Object.values(fixture.accounts??{}))if(a.password?.length>12)secrets.push(a.password);}
if(secrets.some(s=>patch.includes(s)||staged.includes(s)))throw Error('A configured credential appears in the release diff; inspect privately before committing.');
const privateStore=path.join(process.env.LOCALAPPDATA??'', 'ByteQuest','Signing','production-20261113','bytequest-production.p12');
if(paths.some(p=>p===privateStore))throw Error('Signing material is staged.');
console.log(JSON.stringify({result:'PASS',staged_paths:paths.length,configured_credentials_checked:new Set(secrets).size,credential_matches:0,prohibited_staged_paths:0}));
