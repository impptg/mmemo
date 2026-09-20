import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
const base=process.env.TEST_BASE_URL??'http://127.0.0.1:8787';
const config=JSON.parse(await readFile(new URL('../../../.secrets/bootstrap.json',import.meta.url),'utf8').catch(()=>readFile(new URL('../../../../.secrets/bootstrap.json',import.meta.url),'utf8')));
async function request(path,token,body,key=randomUUID()){
 const response=await fetch(base+path,{method:body===undefined?'GET':'POST',headers:{'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{}),'Idempotency-Key':key},body:body===undefined?undefined:JSON.stringify(body)});
 return {status:response.status,data:await response.json()};
}
async function login(name){const r=await request('/auth/login',null,{username:name,password:config.passwords[name]});assert.equal(r.status,200);return r.data;}
async function stream(token){
 const controller=new AbortController();const response=await fetch(base+'/v1/events',{headers:{Authorization:'Bearer '+token},signal:controller.signal});assert.equal(response.status,200);
 const events=[];let pending='';
 const run=(async()=>{try{for await(const data of response.body){pending+=Buffer.from(data).toString();let n;while((n=pending.indexOf('\n\n'))>=0){const msg=pending.slice(0,n);pending=pending.slice(n+2);if(msg.includes('data:'))events.push(JSON.parse(msg.split('data:')[1].trim()));}}}catch(e){if(e.name!=='AbortError')throw e;}})();
 return {events,close:async()=>{controller.abort();await run;}};
}
async function until(fn,ms=3000){const end=Date.now()+ms;while(Date.now()<end){if(await fn())return;await new Promise(r=>setTimeout(r,30));}assert.fail('Timed out');}
test('authenticated transactional CRUD, SSE, idempotency, durable hearts and idle reads',{timeout:30000},async()=>{
 const a=await login('user_pptg'),b=await login('user_mm');
 const id='qa-'+randomUUID(),id2='qa-'+randomUUID();let s;
 const apply=(token,changes,key)=>request('/v1/todos/apply',token,{changes},key);
 try{
  assert.equal((await request('/v1/todos')).status,401);
  assert.equal((await request('/auth/login',null,{username:'user_mm',password:'bad'})).status,401);
  assert.equal((await request('/v1/events')).status,401);
  s=await stream(b.access_token);await until(()=>s.events.some(e=>e.kind==='resync'));
  const key=randomUUID(),change={action:'create',id,patch:{title:'QA realtime',due:'',done:false,participants:[a.sub,b.sub]}};
  const started=Date.now();assert.equal((await apply(a.access_token,[change],key)).status,200);
  await until(()=>s.events.some(e=>e.kind==='todos'));console.log('SSE notification latency ms:',Date.now()-started);
  assert.equal((await apply(a.access_token,[change],key)).status,200);
  assert.equal((await apply(a.access_token,[{...change,id:id2}],key)).status,409);
  let rows=(await request('/v1/todos',b.access_token)).data;assert.equal(rows.filter(t=>t.id===id).length,1);assert.equal(rows.find(t=>t.id===id).created_by,a.sub);
  assert.equal((await apply(b.access_token,[{action:'update',id,patch:{created_by:b.sub}}])).status,400);
  assert.equal((await apply(b.access_token,[{action:'update',id,patch:{participants:['outsider']}}])).status,400);
  assert.equal((await apply(b.access_token,[{action:'update',id,patch:{due:'2026-02-30T10:00'}}])).status,400);
  assert.equal((await apply(a.access_token,[{action:'update',id,patch:{title:'must rollback'}},{action:'update',id:id2,patch:{done:true}}])).status,404);
  rows=(await request('/v1/todos',b.access_token)).data;assert.equal(rows.find(t=>t.id===id).title,'QA realtime');
  const results=await Promise.all([apply(a.access_token,[{action:'update',id,patch:{title:'concurrent title'}}]),apply(b.access_token,[{action:'update',id,patch:{done:true}}])]);results.forEach(r=>assert.equal(r.status,200));
  rows=(await request('/v1/todos',a.access_token)).data;assert.equal(rows.find(t=>t.id===id).title,'concurrent title');assert.equal(rows.find(t=>t.id===id).done,true);
  await apply(a.access_token,[{action:'update',id,patch:{title:'first'}}]);await apply(b.access_token,[{action:'update',id,patch:{title:'last'}}]);assert.equal((await request('/v1/todos',a.access_token)).data.find(t=>t.id===id).title,'last');
  await s.close();s=null;
  const heartKey=randomUUID();await request('/v1/hearts/send',a.access_token,{},heartKey);await request('/v1/hearts/send',a.access_token,{},heartKey);
  const hearts=(await request('/v1/hearts',b.access_token)).data;assert.ok(hearts.length>=1);
  assert.equal((await request('/v1/hearts/ack',a.access_token,{ids:hearts.map(h=>h.id)})).status,200);
  assert.deepEqual((await request('/v1/hearts',b.access_token)).data,hearts);
  s=await stream(b.access_token);await until(()=>s.events.some(e=>e.kind==='resync'));
  await request('/v1/hearts/ack',b.access_token,{ids:hearts.map(h=>h.id)});assert.equal((await request('/v1/hearts',b.access_token)).data.length,0);
  const refreshed=await request('/auth/refresh',null,{refresh_token:b.refresh_token});assert.equal(refreshed.status,200);assert.equal((await request('/v1/todos',refreshed.data.access_token)).status,200);
  const metrics=async()=>{const r=await fetch(base+'/internal/metrics',{headers:{'x-mmemo-admin':process.env.ADMIN_TOKEN??'local-test-admin'}});return r.json();};
  if(base.startsWith('http://127.0.0.1')){const before=await metrics();await new Promise(r=>setTimeout(r,16000));const after=await metrics();assert.equal(before.todoReads,after.todoReads);assert.equal(before.heartReads,after.heartReads);console.log('Idle 16s: zero business reads; SSE remained connected');}
 }finally{if(s)await s.close();await apply(a.access_token,[{action:'delete',id}]);}
});
