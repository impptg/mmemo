import Fastify from 'fastify';
import rateLimit from '@fastify/rate-limit';
import { createHash } from 'node:crypto';
import { changesSchema,loginSchema,refreshSchema,ackSchema } from '@mmemo/contracts';
import { pool } from './db.js';
import { identity,issueSession,passwordMatches,passwordHash,hash,type Identity } from './auth.js';
import { Realtime } from './realtime.js';
import type { PoolClient } from 'pg';
const error=(statusCode:number,message:string)=>Object.assign(new Error(message),{statusCode});
export async function buildApp() {
 const app=Fastify({logger:{level:process.env.LOG_LEVEL??'info',redact:['req.headers.authorization','req.headers.cookie']},bodyLimit:65536,trustProxy:'127.0.0.1'});
 const realtime=new Realtime();
 const metrics={todoReads:0,heartReads:0,mutations:0};
 await app.register(rateLimit,{max:240,timeWindow:'1 minute'});
 const dummy=await passwordHash('nonexistent-account');
 app.setErrorHandler((e,request,reply)=>{
  const err=e as Error & {statusCode?:number;name?:string;code?:string};
  const status=err.name==='ZodError'?400:err.statusCode??(err.code?.startsWith('23')?409:500);
  if(status>=500)request.log.error({message:err.message},'request failed');
  reply.code(status).send({error:status>=500?'Service temporarily unavailable':err.message});
 });
 app.get('/health',async(_,reply)=>{
  try {await pool.query('SELECT 1');if(!realtime.ready)throw Error();return {ok:true};}
  catch {return reply.code(503).send({ok:false});}
 });
 app.post('/auth/login',{config:{rateLimit:{max:10,timeWindow:'1 minute'}}},async req=>{
  const data=loginSchema.parse(req.body);
  const {rows}=await pool.query('SELECT uid,password_hash FROM members WHERE username=$1',[data.username]);
  const valid=await passwordMatches(data.password,rows[0]?.password_hash??dummy);
  if(!valid||!rows[0])throw error(401,'Invalid credentials');
  return issueSession(rows[0].uid);
 });
 app.post('/auth/refresh',async req=>{
  const data=refreshSchema.parse(req.body);
  // Refresh credentials stay valid until expiry, so a lost reply can be retried safely.
  const {rows}=await pool.query('SELECT uid FROM sessions WHERE refresh_hash=$1 AND refresh_expires_at>now()',[hash(data.refresh_token)]);
  if(!rows[0])throw error(401,'Session expired');
  const token=await issueSession(rows[0].uid);
  return token;
 });
 await app.register(async api=>{
  api.decorateRequest('identity',null);
  api.addHook('preHandler',async req=>{
   const user=await identity(req.headers.authorization);if(!user)throw error(401,'Authentication required');
   (req as typeof req & {identity:Identity}).identity=user;
  });
  const who=(req:unknown)=>(req as {identity:Identity}).identity;
  api.get('/todos',async req=>{metrics.todoReads++;return (await pool.query('SELECT id,title,due,done,created_by,participants FROM todos WHERE space_id=$1 ORDER BY created_at,id',[who(req).space_id])).rows;});
  async function mutation(user:Identity,key:unknown,path:string,body:unknown,operation:(c:PoolClient)=>Promise<void>) {
   if(typeof key!=='string'||!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(key))throw error(400,'Idempotency-Key UUID required');
   const fingerprint=createHash('sha256').update(path+JSON.stringify(body)).digest('hex');
   const c=await pool.connect();
   try {
    await c.query('BEGIN');
    // Serialize this tiny shared space to preserve transaction and capacity invariants.
    await c.query('SELECT pg_advisory_xact_lock(hashtext($1))',[user.space_id]);
    const prior=(await c.query('SELECT fingerprint FROM mutations WHERE uid=$1 AND request_id=$2',[user.uid,key])).rows[0];
    if(prior){if(prior.fingerprint!==fingerprint)throw error(409,'Idempotency key reused with different body');}
    else {
     await operation(c);
     await c.query('INSERT INTO mutations(uid,request_id,fingerprint) VALUES($1,$2,$3)',[user.uid,key,fingerprint]);metrics.mutations++;
    }
    await c.query('COMMIT');return {ok:true};
   }catch(e){await c.query('ROLLBACK');throw e;}finally{c.release();}
  }
  api.post('/todos/apply',async req=>{
   const body=changesSchema.parse(req.body),user=who(req);
   return mutation(user,req.headers['idempotency-key'],'todos',body,async c=>{
    for(const change of body.changes){
     const p=change.patch??{};
     if(change.action==='create'){
      if(!p.title||p.due===undefined||p.done===undefined)throw error(400,'Missing create fields');
      const participants=p.participants??[user.uid];
      const valid=await c.query('SELECT uid FROM members WHERE space_id=$1 AND uid=ANY($2::text[])',[user.space_id,participants]);
      if(valid.rowCount!==participants.length)throw error(403,'Invalid participants');
      await c.query('INSERT INTO todos(id,space_id,title,due,done,created_by,participants) VALUES($1,$2,$3,$4,$5,$6,$7)',[change.id,user.space_id,p.title,p.due,p.done,user.uid,participants]);
     }else{
      if(p.participants){const valid=await c.query('SELECT uid FROM members WHERE space_id=$1 AND uid=ANY($2::text[])',[user.space_id,p.participants]);if(valid.rowCount!==p.participants.length)throw error(403,'Invalid participants');}
      if(change.action==='delete'){
       const result=await c.query('DELETE FROM todos WHERE id=$1 AND space_id=$2',[change.id,user.space_id]);if(!result.rowCount)throw error(404,'Todo missing');
      }else{
       const result=await c.query('UPDATE todos SET title=COALESCE($3,title),due=COALESCE($4,due),done=COALESCE($5,done),participants=COALESCE($6,participants) WHERE id=$1 AND space_id=$2',[change.id,user.space_id,p.title,p.due,p.done,p.participants]);if(!result.rowCount)throw error(404,'Todo missing');
      }
     }
    }
    const count=await c.query('SELECT count(*)::int AS n FROM todos WHERE space_id=$1',[user.space_id]);if(count.rows[0].n>10000)throw error(409,'Capacity exceeded');
   });
  });
  api.get('/hearts',async req=>{metrics.heartReads++;return (await pool.query('SELECT id FROM hearts WHERE recipient=$1 ORDER BY created_at,id LIMIT 100',[who(req).uid])).rows;});
  api.post('/hearts/send',async req=>{
   const user=who(req);return mutation(user,req.headers['idempotency-key'],'heart',{},async c=>{await c.query('INSERT INTO hearts(sender,recipient) SELECT $1,uid FROM members WHERE space_id=$2 AND uid<>$1',[user.uid,user.space_id]);});
  });
  api.post('/hearts/ack',async req=>{const {ids}=ackSchema.parse(req.body);await pool.query('DELETE FROM hearts WHERE recipient=$1 AND id=ANY($2::uuid[])',[who(req).uid,ids]);return {ok:true};});
  api.get('/events',async(req,reply)=>{
   if(!realtime.ready)throw error(503,'Realtime reconnecting');
   if(realtime.count>=20)throw error(429,'Too many subscriptions');
   reply.hijack();reply.raw.writeHead(200,{'Content-Type':'text/event-stream','Cache-Control':'no-cache, no-transform','Connection':'keep-alive','X-Accel-Buffering':'no'});
   realtime.subscribe(who(req),reply.raw);
  });
 },{prefix:'/v1'});
 // Diagnostics are only reachable on the loopback bind and never proxied publicly.
 app.get('/internal/metrics',async(req,reply)=>{
  if(req.headers['x-mmemo-admin']!==process.env.ADMIN_TOKEN||!process.env.ADMIN_TOKEN)return reply.code(403).send({error:'Forbidden'});
  return {...metrics,...realtime.counters,subscribers:realtime.count,listenerReady:realtime.ready};
 });
 app.addHook('onClose',async()=>{await realtime.stop();await pool.end();});
 await realtime.start();
 return app;
}
