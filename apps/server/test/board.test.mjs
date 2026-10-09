import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {WebSocket} from 'ws';
const base=process.env.TEST_BASE_URL??'http://127.0.0.1:8787';
const config=JSON.parse(await readFile(process.env.BOOTSTRAP_CONFIG??new URL('../../../.secrets/bootstrap.json',import.meta.url),'utf8'));
async function login(name){const r=await fetch(base+'/auth/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({username:name,password:config.passwords[name]})});assert.equal(r.status,200);return r.json();}
async function connect(token,server=base){
 const ws=new WebSocket(server.replace(/^http/,'ws')+'/v1/board/socket',{headers:{Authorization:'Bearer '+token},maxPayload:80*1024*1024});const messages=[];
 ws.on('message',data=>messages.push(JSON.parse(data.toString())));
 await new Promise((resolve,reject)=>{ws.once('open',resolve);ws.once('error',reject);});
 const wait=async fn=>{const end=Date.now()+6000;while(Date.now()<end){const value=messages.find(fn);if(value)return value;await new Promise(r=>setTimeout(r,20));}assert.fail('Board message timeout');};
 await wait(m=>m.type==='snapshot');return {ws,messages,wait,send:message=>ws.send(JSON.stringify(message))};
}
const rectangle=id=>({id,type:'rectangle',x:10,y:20,width:100,height:80,angle:0,strokeColor:'#111111',backgroundColor:'transparent',fillStyle:'solid',strokeWidth:2,strokeStyle:'solid',roughness:1,opacity:100,seed:1,groupIds:[],isDeleted:false});
const op=e=>({id:e.id,patch:Object.fromEntries(Object.entries(e).filter(([k])=>k!=='id'))});
const update=(operations,files=[])=>({type:'update',requestId:randomUUID(),operations,files});
test('board realtime, durable files, field merging, conditional undo, idempotency and validation',{timeout:30000},async()=>{
 const a=await login('user_pptg'),b=await login('user_mm');const A=await connect(a.access_token),B=await connect(b.access_token,process.env.TEST_PEER_BASE_URL??base);const id='server-'+randomUUID();
 try{
  assert.equal((await fetch(base+'/v1/board')).status,401);
  const first=update([op(rectangle(id))]);A.send(first);const saved=await A.wait(m=>m.type==='ack'&&m.requestId===first.requestId);assert.ok(saved.revision>0);
  await B.wait(m=>(m.elements??[]).some(e=>e.id===id));
  // Native persistence/JSONB can reorder keys without changing a request.
  const reorder=value=>Array.isArray(value)?value.map(reorder):value&&typeof value==='object'?Object.fromEntries(Object.entries(value).reverse().map(([k,v])=>[k,reorder(v)])):value;
  const acknowledgements=()=>A.messages.filter(m=>m.type==='ack'&&m.requestId===first.requestId).length;
  const count=acknowledgements();A.send(reorder(first));
  for(let n=0;n<100&&acknowledgements()===count;n++)await new Promise(r=>setTimeout(r,20));
  assert.equal(acknowledgements(),count+1);
  A.send({...first,operations:[{id,patch:{x:200}}]});await A.wait(m=>m.type==='error'&&m.requestId===first.requestId);
  A.send(first);await new Promise(r=>setTimeout(r,100));const snapshot=await (await fetch(base+'/v1/board',{headers:{Authorization:'Bearer '+b.access_token}})).json();assert.equal(snapshot.elements.filter(e=>e.id===id).length,1);
  const x=update([{id,patch:{x:70}}]),color=update([{id,patch:{backgroundColor:'#ff0000'}}]);A.send(x);B.send(color);await A.wait(m=>m.type==='ack'&&m.requestId===x.requestId);await B.wait(m=>m.type==='ack'&&m.requestId===color.requestId);
  let s=await (await fetch(base+'/v1/board',{headers:{Authorization:'Bearer '+a.access_token}})).json();let e=s.elements.find(e=>e.id===id);assert.equal(e.x,70);assert.equal(e.backgroundColor,'#ff0000');
  const peer=update([{id,patch:{x:99}}]);B.send(peer);await B.wait(m=>m.type==='ack'&&m.requestId===peer.requestId);
  const undo=update([{id,patch:{x:10},expected:{x:70}}]);A.send(undo);await A.wait(m=>m.type==='ack'&&m.requestId===undo.requestId);
  s=await (await fetch(base+'/v1/board',{headers:{Authorization:'Bearer '+a.access_token}})).json();assert.equal(s.elements.find(e=>e.id===id).x,99);
  const returned=update([{id,patch:{x:70}}]);B.send(returned);await B.wait(m=>m.type==='ack'&&m.requestId===returned.requestId);
  const guarded=update([{id,patch:{x:10,isDeleted:true},expected:{x:70,isDeleted:false}}]);A.send(guarded);await A.wait(m=>m.type==='ack'&&m.requestId===guarded.requestId);
  s=await (await fetch(base+'/v1/board',{headers:{Authorization:'Bearer '+a.access_token}})).json();assert.equal(s.elements.find(e=>e.id===id).x,70);assert.equal(s.elements.find(e=>e.id===id).isDeleted,false);
  A.send({type:'pointer',pointer:{x:222,y:333},button:'down'});await B.wait(m=>m.type==='pointer'&&m.pointer.x===222);
  assert.equal((await (await fetch(base+'/v1/board',{headers:{Authorization:'Bearer '+a.access_token}})).json()).revision,s.revision);
  const file={id:'png-'+randomUUID(),mimeType:'image/png',created:Date.now(),lastRetrieved:Date.now(),version:1,dataURL:'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg=='};
  const image={...rectangle('image-'+randomUUID()),type:'image',fileId:file.id,scale:[1,1],status:'saved'};const uploaded=update([op(image)],[file]);A.send(uploaded);await A.wait(m=>m.type==='ack'&&m.requestId===uploaded.requestId);
  s=await (await fetch(base+'/v1/board',{headers:{Authorization:'Bearer '+b.access_token}})).json();assert.equal(s.files.find(f=>f.id===file.id).dataURL,file.dataURL);
  const invalid=update([{id,patch:{x:Infinity}}]);A.send(invalid);await A.wait(m=>m.type==='error');
  const badFile=update([op({...image,id:'bad-'+randomUUID()})],[{...file,id:'bad',dataURL:'data:image/png;base64,AAAAAAAAAAAAAAAA'}]);A.send(badFile);await A.wait(m=>m.type==='error'&&m.requestId===badFile.requestId);
  const deleted=update([{id,patch:{isDeleted:true}}]);A.send(deleted);await A.wait(m=>m.type==='ack'&&m.requestId===deleted.requestId);
  const stale=update([{id,patch:{x:123}}]);B.send(stale);await B.wait(m=>m.type==='ack'&&m.requestId===stale.requestId);
  s=await (await fetch(base+'/v1/board',{headers:{Authorization:'Bearer '+a.access_token}})).json();assert.equal(s.elements.find(e=>e.id===id).isDeleted,true);
  const batch=Array.from({length:20},()=>update([op(rectangle('parallel-'+randomUUID()))]));
  batch.forEach((request,index)=>(index%2?B:A).send(request));
  await Promise.all(batch.map((request,index)=>(index%2?B:A).wait(m=>m.type==='ack'&&m.requestId===request.requestId)));
  const scene=peer=>{let revision=-1,map=new Map();for(const message of peer.messages){if(!['snapshot','update','ack'].includes(message.type)||message.revision<revision)continue;revision=message.revision;if(message.type==='snapshot')map=new Map();for(const e of message.elements??[])map.set(e.id,e);}return map;};
  for(const peer of [A,B])await peer.wait(()=>batch.every(request=>scene(peer).has(request.operations[0].id)));
  console.log('Board: realtime, saved PNG, concurrent fields, protected undo, idempotency, ephemeral cursor and tombstone passed');
 }finally{A.ws.close();B.ws.close();}
});

test('board and image access stay inside the authenticated space', {skip:!process.env.DATABASE_URL||!base.startsWith('http://127.0.0.1')}, async()=>{
 const {pool}=await import('../dist/db.js');const {issueSession}=await import('../dist/auth.js');
 const uid='board-outsider-'+randomUUID(),space=uid;
 let outsider,member;
 try {
  await pool.query('INSERT INTO members(uid,username,password_hash,space_id) VALUES($1,$1,$2,$1)',[uid,'no-password-login']);
  const token=(await issueSession(uid)).access_token;
  outsider=await connect(token);member=await connect((await login('user_pptg')).access_token);
  const empty=await (await fetch(base+'/v1/board',{headers:{Authorization:'Bearer '+token}})).json();
  assert.deepEqual(empty.elements,[]);assert.deepEqual(empty.files,[]);
  const own=update([op(rectangle('isolated-'+randomUUID()))]);outsider.send(own);await outsider.wait(m=>m.type==='ack'&&m.requestId===own.requestId);
  member.send({type:'pointer',pointer:{x:987654,y:12345},button:'up'});
  outsider.send({...update([op(rectangle('forged'))]),space_id:'mmemo'});await outsider.wait(m=>m.type==='error');
  const foreign=await (await fetch(base+'/v1/board',{headers:{Authorization:'Bearer '+(await login('user_pptg')).access_token}})).json();
  const missing=update([op({...rectangle('foreign-image'),type:'image',fileId:foreign.files[0]?.id??'missing',scale:[1,1]})]);
  outsider.send(missing);await outsider.wait(m=>m.type==='error'&&m.requestId===missing.requestId);
  await new Promise(r=>setTimeout(r,100));assert.ok(!outsider.messages.some(m=>m.type==='pointer'&&m.pointer.x===987654));
  assert.ok(!foreign.elements.some(e=>e.id===own.operations[0].id));
 } finally {
  outsider?.ws.close();member?.ws.close();
  for(const table of ['board_requests','board_reads','board_files','board_elements','board_heads'])await pool.query(`DELETE FROM ${table} WHERE space_id=$1`,[space]);
  await pool.query('DELETE FROM sessions WHERE uid=$1',[uid]);await pool.query('DELETE FROM members WHERE uid=$1',[uid]);await pool.end();
 }
});
