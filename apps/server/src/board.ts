import type { FastifyInstance } from 'fastify';
import type { WebSocket } from 'ws';
import pg from 'pg';
import { createHash,randomUUID } from 'node:crypto';
import { z } from 'zod';
import { pool } from './db.js';
import { identity, type Identity } from './auth.js';

type Element = Record<string, any> & {id:string};
const id=z.string().min(1).max(100).regex(/^[a-zA-Z0-9_-]+$/);
const safeRecord=z.record(z.string(),z.json()).refine(v=>Object.keys(v).every(k=>!['__proto__','constructor','prototype'].includes(k)));
const operation=z.object({id,patch:safeRecord,expected:safeRecord.optional()}).strict();
const update=z.object({type:z.literal('update'),requestId:z.uuid(),operations:z.array(operation).min(1).max(1000),files:z.array(z.object({id,mimeType:z.enum(['image/png','image/jpeg','image/gif','image/webp','image/svg+xml']),dataURL:z.string().max(12*1024*1024),created:z.number().finite(),lastRetrieved:z.number().finite().optional(),version:z.number().finite().optional()}).strict()).max(16).default([])}).strict();
const pointer=z.object({type:z.literal('pointer'),pointer:z.object({x:z.number().finite(),y:z.number().finite()}),button:z.enum(['up','down'])}).strict();
const read=z.object({type:z.literal('read'),revision:z.number().int().min(0)}).strict();
const schema=z.union([update,pointer,read]);
const shapes=new Set(['rectangle','ellipse','diamond','line','arrow','freedraw','text','image','frame','magicframe']);
const fields=new Set(['type','x','y','width','height','angle','strokeColor','backgroundColor','fillStyle','strokeWidth','strokeStyle','roughness','opacity','groupIds','frameId','index','roundness','seed','isDeleted','boundElements','link','locked','customData','points','pressures','simulatePressure','lastCommittedPoint','startBinding','endBinding','startArrowhead','endArrowhead','elbowed','fixedSegments','startIsSpecial','endIsSpecial','fontSize','fontFamily','text','originalText','textAlign','verticalAlign','containerId','autoResize','lineHeight','fileId','status','scale','crop']);
const same=(a:any,b:any):boolean=>{
 if(a===b)return true;
 if(a===null||b===null||typeof a!=='object'||typeof b!=='object')return false;
 if(Array.isArray(a)!==Array.isArray(b))return false;
 const keys=Object.keys(a);return keys.length===Object.keys(b).length&&keys.every(key=>Object.hasOwn(b,key)&&same(a[key],b[key]));
};
const fail=(message:string)=>{throw Object.assign(new Error(message),{statusCode:400});};
// Swift's JSONSerialization and PostgreSQL JSONB may reorder object keys on retry.
const canonicalJSON=(value:any):string=>Array.isArray(value)?'['+value.map(canonicalJSON).join(',')+']':value!==null&&typeof value==='object'?'{'+Object.keys(value).sort().map(key=>JSON.stringify(key)+':'+canonicalJSON(value[key])).join(',')+'}':JSON.stringify(value);
export function mergeBoardElement(current:Element|undefined,op:z.infer<typeof operation>):Element {
 const result:Element={...(current??{}),id:op.id};
 for(const [key,value] of Object.entries(op.patch)) {
  if(!fields.has(key))fail('Unsupported element field: '+key);
  // Conditional undo/redo never overwrites a field changed by somebody else.
  if(op.expected && Object.hasOwn(op.expected,key) && !same(current?.[key],op.expected[key]))continue;
  result[key]=value;
 }
 if(!shapes.has(result.type))fail('Unsupported element type');
 for(const key of ['x','y','width','height','angle','strokeWidth','opacity','roughness','seed'])if(typeof result[key]!=='number'||!Number.isFinite(result[key]))fail('Invalid geometry');
 if(Math.abs(result.x)>1e7||Math.abs(result.y)>1e7||result.width<0||result.height<0||result.width>1e7||result.height>1e7)fail('Geometry exceeds board bounds');
 if(typeof result.isDeleted!=='boolean'||!Array.isArray(result.groupIds)||typeof result.strokeColor!=='string'||typeof result.backgroundColor!=='string')fail('Invalid element');
 if(result.groupIds.length>100||!result.groupIds.every((v:any)=>typeof v==='string'&&v.length<=100))fail('Invalid group IDs');
 if(result.index!==undefined&&result.index!==null&&(typeof result.index!=='string'||result.index.length>100||!/^[A-Za-z0-9]+$/.test(result.index)))fail('Invalid layer index');
 for(const key of ['strokeColor','backgroundColor','fillStyle','strokeStyle'])if(typeof result[key]!=='string'||result[key].length>100)fail('Invalid style');
 if(result.link!=null&&(typeof result.link!=='string'||result.link.length>2000))fail('Invalid link');
 if(result.opacity<0||result.opacity>100||result.strokeWidth<0||result.strokeWidth>1000||result.roughness<0||result.roughness>10)fail('Invalid style range');
 if(JSON.stringify(result).length>1024*1024)fail('Element too large');
 if(result.type==='text' && (typeof result.text!=='string'||result.text.length>100000||typeof result.fontSize!=='number'||result.fontSize<=0))fail('Invalid text');
 if(['line','arrow','freedraw'].includes(result.type) && (!Array.isArray(result.points)||result.points.length>50000||!result.points.every((p:any)=>Array.isArray(p)&&p.length===2&&p.every((n:any)=>typeof n==='number'&&Number.isFinite(n)))))fail('Invalid points');
 if(result.type==='image' && (typeof result.fileId!=='string'||!Array.isArray(result.scale)))fail('Invalid image');
 result.version=(current?.version??0)+1;result.versionNonce=0;result.updated=Date.now();
 return result;
}
function validFile(file:z.infer<typeof update>['files'][number]) {
 const prefix=`data:${file.mimeType};base64,`;
 if(!file.dataURL.startsWith(prefix))fail('Invalid image encoding');
 const encoded=file.dataURL.slice(prefix.length);
 if(!/^[A-Za-z0-9+/]*={0,2}$/.test(encoded))fail('Invalid image encoding');
 const bytes=Buffer.from(encoded,'base64');
 if(bytes.length>8*1024*1024||bytes.length<12)fail('Image must be between 12 bytes and 8 MiB');
 if(file.mimeType==='image/svg+xml') {
  const svg=bytes.toString('utf8');
  if(!/<svg[\s>]/i.test(svg)||/<!DOCTYPE|<!ENTITY|<script[\s>]|<foreignObject[\s>]|\son\w+\s*=|@import/i.test(svg))fail('Unsupported SVG content');
  return;
 }
 const magic=file.mimeType==='image/png'?bytes.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10])):file.mimeType==='image/jpeg'?bytes[0]===255&&bytes[1]===216: file.mimeType==='image/gif'?bytes.subarray(0,3).toString()==='GIF':bytes.subarray(0,4).toString()==='RIFF'&&bytes.subarray(8,12).toString()==='WEBP';
 if(!magic)fail('Image type does not match content');
}

export async function applyBoard(user:Identity,body:z.infer<typeof update>) {
 const fingerprint=createHash('sha256').update(canonicalJSON(body)).digest('hex');
 const c=await pool.connect();
 try {
  await c.query('BEGIN');await c.query('SELECT pg_advisory_xact_lock(hashtext($1))',['board:'+user.space_id]);
  const prior=(await c.query('SELECT fingerprint,response FROM board_requests WHERE uid=$1 AND request_id=$2',[user.uid,body.requestId])).rows[0];
  if(prior){if(prior.fingerprint!==fingerprint)fail('Request ID reused with different update');await c.query('COMMIT');return prior.response;}
  await c.query('INSERT INTO board_heads(space_id) VALUES($1) ON CONFLICT DO NOTHING',[user.space_id]);
  const head=(await c.query('SELECT revision,latest_by_user FROM board_heads WHERE space_id=$1 FOR UPDATE',[user.space_id])).rows[0];
  const revision=Number(head.revision)+1;
  for(const file of body.files) {
   validFile(file);
   const old=(await c.query('SELECT data FROM board_files WHERE space_id=$1 AND id=$2',[user.space_id,file.id])).rows[0];
   if(old && (old.data.dataURL!==file.dataURL||old.data.mimeType!==file.mimeType))fail('Image ID cannot be replaced');
   if(!old)await c.query('INSERT INTO board_files VALUES($1,$2,$3)',[user.space_id,file.id,file]);
  }
  const merged=new Map<string,Element>();
  for(const op of body.operations) {
   const current=merged.get(op.id)??(await c.query('SELECT element FROM board_elements WHERE space_id=$1 AND id=$2',[user.space_id,op.id])).rows[0]?.element;
   const ownership=(await c.query('SELECT field_authors FROM board_elements WHERE space_id=$1 AND id=$2',[user.space_id,op.id])).rows[0]?.field_authors??{};
   const effective={...op,patch:{...op.patch}};
   if(op.expected){
    for(const key of Object.keys(effective.patch))if(ownership[key]&&ownership[key]!==user.uid)delete effective.patch[key];
    if(effective.patch.isDeleted===true && Object.values(ownership).some(author=>author!==user.uid))delete effective.patch.isDeleted;
   }
   const next=mergeBoardElement(current,effective);
   if(current && Object.keys(op.patch).every(k=>same(current[k],next[k])))continue;
   if(next.type==='image'&&!next.isDeleted&& !(await c.query('SELECT 1 FROM board_files WHERE space_id=$1 AND id=$2',[user.space_id,next.fileId])).rowCount)fail('Image file missing');
   merged.set(op.id,next);
   const authors={...ownership};for(const key of Object.keys(effective.patch))if(!same(current?.[key],next[key]))authors[key]=user.uid;
   await c.query('INSERT INTO board_elements(space_id,id,element,revision,field_authors) VALUES($1,$2,$3,$4,$5) ON CONFLICT(space_id,id) DO UPDATE SET element=$3,revision=$4,field_authors=$5',[user.space_id,op.id,next,revision,authors]);
  }
  const size=(await c.query("SELECT count(*)::int AS n,COALESCE(sum(octet_length(element::text)),0)::bigint AS bytes FROM board_elements WHERE space_id=$1",[user.space_id])).rows[0];
  const fileSize=(await c.query('SELECT COALESCE(sum(octet_length(data::text)),0)::bigint AS bytes FROM board_files WHERE space_id=$1',[user.space_id])).rows[0];
  if(size.n>20000||Number(size.bytes)>24*1024*1024||Number(fileSize.bytes)>32*1024*1024)fail('Board capacity exceeded');
  const latest={...head.latest_by_user};
  if(merged.size){latest[user.uid]={revision,ids:[...merged.keys()],updated:Date.now()};await c.query('UPDATE board_heads SET revision=$2,latest_by_user=$3 WHERE space_id=$1',[user.space_id,revision,latest]);}
  const response={type:'ack',requestId:body.requestId,revision:merged.size?revision:Number(head.revision),elements:[...merged.values()],files:body.files,latest,author:user.uid};
  await c.query('INSERT INTO board_requests(uid,request_id,space_id,fingerprint,response) VALUES($1,$2,$3,$4,$5)',[user.uid,body.requestId,user.space_id,fingerprint,{type:'ack',requestId:body.requestId,revision:response.revision,elements:[],files:[],author:user.uid}]);
  await c.query('COMMIT');return response;
 }catch(e){await c.query('ROLLBACK');throw e;}finally{c.release();}
}
async function snapshot(user:Identity,since=-1) {
 const c=await pool.connect();
 try {
  await c.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
  const head=(await c.query('SELECT * FROM board_heads WHERE space_id=$1',[user.space_id])).rows[0];
  const elements=(await c.query('SELECT element FROM board_elements WHERE space_id=$1 AND revision>$2 ORDER BY id',[user.space_id,since])).rows.map(r=>r.element);
  const files=(since<0?await c.query('SELECT data FROM board_files WHERE space_id=$1',[user.space_id]):await c.query('SELECT data FROM board_files WHERE space_id=$1 AND id=ANY($2::text[])',[user.space_id,elements.filter(e=>e.type==='image'&&!e.isDeleted).map(e=>e.fileId)])).rows.map(r=>r.data);
  const seen=(await c.query('SELECT revision FROM board_reads WHERE space_id=$1 AND uid=$2',[user.space_id,user.uid])).rows[0];
  await c.query('COMMIT');return {type:since<0?'snapshot':'update',revision:Number(head?.revision??0),elements,files,latest:head?.latest_by_user??{},seen:Number(seen?.revision??0),uid:user.uid};
 }catch(e){await c.query('ROLLBACK');throw e;}finally{c.release();}
}
type Peer={socket:WebSocket;user:Identity;revision:number;pending:boolean;closed:boolean;wanted:number};
export async function registerBoard(app:FastifyInstance) {
 const peers=new Set<Peer>();let listener:pg.Client|undefined,retry:NodeJS.Timeout|undefined,stopped=false;
 const instance=randomUUID();
 const ephemeral=(user:Identity,message:any)=>{
  for(const peer of peers)if(peer.user.space_id===user.space_id)send(peer,message);
  if(!stopped)void listener?.query("SELECT pg_notify('mmemo_board_presence',$1)",[JSON.stringify({source:instance,space:user.space_id,message})]).catch(()=>{});
 };
 const send=(peer:Peer,data:any)=>{if(peer.socket.readyState!==1)return;if(peer.socket.bufferedAmount>64*1024*1024){peer.socket.close(1013,'Slow client');return;}peer.socket.send(JSON.stringify(data));};
 async function refresh(peer:Peer) {
  if(peer.pending||peer.closed)return;peer.pending=true;
  try{do{const data=await snapshot(peer.user,peer.revision);if(data.revision>peer.revision){peer.revision=data.revision;send(peer,data);}}while(!peer.closed&&peer.revision<peer.wanted);}
  catch{peer.socket.close(1011,'Snapshot unavailable');}finally{peer.pending=false;}
 }
 async function listen() {
  if(stopped)return;
  const client=new pg.Client({connectionString:process.env.DATABASE_URL,application_name:'mmemo-board-listener',connectionTimeoutMillis:5000});listener=client;let failed=false;
  const recover=()=>{if(failed)return;failed=true;for(const p of peers)p.socket.close(1012,'Reconnect');void client.end().catch(()=>{});if(!stopped)retry=setTimeout(()=>void listen(),1000);};
  client.on('error',recover);client.on('end',recover);
  client.on('notification',event=>{try{const data=JSON.parse(event.payload!);if(event.channel==='mmemo_board_presence'){if(data.source!==instance)for(const p of peers)if(p.user.space_id===data.space)send(p,data.message);return;}for(const p of peers)if(p.user.space_id===data.space&&Number(data.revision)>p.revision){p.wanted=Math.max(p.wanted,Number(data.revision));void refresh(p);}}catch{}});
  try{await client.connect();await client.query('LISTEN mmemo_board');await client.query('LISTEN mmemo_board_presence');}catch{recover();}
 }
 app.get('/v1/board', {preHandler:async(req,reply)=>{if(!await identity(req.headers.authorization))return reply.code(401).send({error:'Authentication required'});}},async req=>snapshot((await identity(req.headers.authorization))!));
 app.get('/v1/board/socket',{websocket:true,preValidation:async(req,reply)=>{
  const user=await identity(req.headers.authorization);if(!user)return reply.code(401).send({error:'Authentication required'});
  if(peers.size>=20)return reply.code(429).send({error:'Too many board connections'});
  (req as any).boardIdentity=user;
 }},(socket,req)=>{
  const peer:Peer={socket,user:(req as any).boardIdentity,revision:-1,pending:false,closed:false,wanted:0};peers.add(peer);
  const session=instance+':'+req.id;
  let chain=Promise.resolve(),messages=0,reset=Date.now(),alive=true;
  const expiry=setTimeout(()=>socket.close(4001,'Session expired'),Math.max(1,peer.user.expires_at.getTime()-Date.now()));
  const heartbeat=setInterval(()=>{if(!alive){socket.terminate();return;}alive=false;socket.ping();},15000);
  socket.on('pong',()=>{alive=true;});
  socket.on('message',raw=>{
   if(Date.now()-reset>1000){reset=Date.now();messages=0;}
   if(++messages>60){socket.close(1008,'Too many messages');return;}
   let body:z.infer<typeof schema>;
   try{body=schema.parse(JSON.parse(raw.toString()));}catch{send(peer,{type:'error',message:'Invalid board message',retryable:false});return;}
   if(body.type==='pointer') {ephemeral(peer.user,{...body,uid:peer.user.uid,session});return;}
   chain=chain.then(async()=>{
    if(body.type==='read'){
     await pool.query('INSERT INTO board_reads(space_id,uid,revision) SELECT space_id,$2,LEAST(revision,$3) FROM board_heads WHERE space_id=$1 ON CONFLICT(space_id,uid) DO UPDATE SET revision=GREATEST(board_reads.revision,EXCLUDED.revision)',[peer.user.space_id,peer.user.uid,body.revision]);return;
    }
    try{
     const result=await applyBoard(peer.user,body);
     // A different connection/instance can commit an intervening revision. Fill
     // any gap before advancing this peer, including in its own acknowledgement.
     if(result.revision>peer.revision+1){const delta=await snapshot(peer.user,peer.revision);peer.revision=Math.max(peer.revision,delta.revision);send(peer,{...delta,type:'ack',requestId:body.requestId,author:peer.user.uid});}
     else {send(peer,result);peer.revision=Math.max(peer.revision,result.revision);}
     for(const other of peers)if(other.user.space_id===peer.user.space_id&&result.revision>other.revision){
      if(result.revision===other.revision+1){other.revision=result.revision;send(other,{...result,type:'update'});}
      else {other.wanted=Math.max(other.wanted,result.revision);void refresh(other);}
     }
    }catch(e){send(peer,{type:'error',requestId:body.requestId,message:(e as Error).message,retryable:(e as any).statusCode!==400});}
   }).catch(()=>socket.close(1011,'Storage unavailable'));
  });
  socket.on('close',()=>{peer.closed=true;peers.delete(peer);clearTimeout(expiry);clearInterval(heartbeat);ephemeral(peer.user,{type:'leave',uid:peer.user.uid,session});});
  socket.on('error',()=>{});void refresh(peer);
 });
 app.addHook('preClose',async()=>{stopped=true;clearTimeout(retry);for(const p of peers)p.socket.terminate();await listener?.end().catch(()=>{});});
 await listen();
}
