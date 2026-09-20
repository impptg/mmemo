import pg from 'pg';
import type { ServerResponse } from 'node:http';
import type { Identity } from './auth.js';
type Subscriber={user:Identity;response:ServerResponse};
export class Realtime {
 private subscribers=new Set<Subscriber>();
 private listener?:pg.Client;
 private retry?:NodeJS.Timeout;
 private stopped=false;
 ready=false;
 counters={connections:0,notifications:0};
 async start() {
  if(this.stopped)return;
  const client=new pg.Client({connectionString:process.env.DATABASE_URL,application_name:'mmemo-listener',connectionTimeoutMillis:5000,keepAlive:true,keepAliveInitialDelayMillis:10000});
  this.listener=client;
  let failed=false;
  const fail=()=>{
   if(failed)return; failed=true;this.ready=false;
   // End streams: their reconnect reads a fresh snapshot after LISTEN is restored.
   for(const s of this.subscribers)s.response.end();
   void client.end().catch(()=>{});
   if(!this.stopped)this.retry=setTimeout(()=>void this.start(),1000);
  };
  client.on('error',fail); client.on('end',fail);
  client.on('notification',message=>{
   try {
    const event=JSON.parse(message.payload!);this.counters.notifications++;
    for(const s of this.subscribers) {
     if(event.kind==='todos' ? event.space===s.user.space_id : event.recipient===s.user.uid) this.send(s,event.kind);
    }
   } catch { /* Ignore malformed notifications from outside our triggers. */ }
  });
  try {await client.connect();await client.query('LISTEN mmemo_changes');this.ready=true;}
  catch {fail();}
 }
 private send(s:Subscriber,kind:string) {
  if(s.response.writableLength>65536){s.response.destroy();return;}
  s.response.write(`event: sync\ndata: ${JSON.stringify({kind})}\n\n`);
 }
 subscribe(user:Identity,response:ServerResponse) {
  const s={user,response};this.subscribers.add(s);this.counters.connections++;
  this.send(s,'resync');
  const heartbeat=setInterval(()=>response.write(': heartbeat\n\n'),15000);
  const expires=setTimeout(()=>response.end(),Math.max(1,user.expires_at.getTime()-Date.now()));
  response.on('close',()=>{clearInterval(heartbeat);clearTimeout(expires);this.subscribers.delete(s);});
 }
 get count(){return this.subscribers.size;}
 async stop(){this.stopped=true;clearTimeout(this.retry);for(const s of this.subscribers)s.response.end();await this.listener?.end().catch(()=>{});}
}
