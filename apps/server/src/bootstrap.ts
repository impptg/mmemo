import {readFile} from 'node:fs/promises';
import {identities} from '@mmemo/contracts';
import {pool,migrate} from './db.js';
import {passwordHash} from './auth.js';
// Private input stays outside the repository. Existing accounts/data are never overwritten.
const input=JSON.parse(await readFile(process.argv[2],'utf8'));
await migrate();
const c=await pool.connect();
try {
 await c.query('BEGIN');
 for(const user of identities){
  if(!input.passwords[user.username])throw Error('Missing password');
  await c.query('INSERT INTO members(uid,username,password_hash) VALUES($1,$2,$3) ON CONFLICT(uid) DO NOTHING',[user.uid,user.username,await passwordHash(input.passwords[user.username])]);
 }
 for(const t of input.todos){
  const creator=t.createdBy??identities[1].uid;
  const participants=t.participants??[creator];
  if(!identities.some(u=>u.uid===creator)||!participants.every((id:string)=>identities.some(u=>u.uid===id)))throw Error('Unknown local identity');
  await c.query('INSERT INTO todos(id,space_id,title,due,done,created_by,participants) VALUES($1,\'mmemo\',$2,$3,$4,$5,$6) ON CONFLICT(id) DO NOTHING',[t.id,t.title,t.due,t.done,creator,participants]);
 }
 await c.query('COMMIT');console.log('Bootstrap complete:',input.todos.length,'source todos');
} catch(e){await c.query('ROLLBACK');throw e;}finally{c.release();await pool.end();}
