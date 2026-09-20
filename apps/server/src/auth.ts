import { randomBytes, scrypt as scryptCallback, timingSafeEqual, createHash } from 'node:crypto';
import { promisify } from 'node:util';
import { pool } from './db.js';
const scrypt=promisify(scryptCallback);
export const hash = (value:string) => createHash('sha256').update(value).digest('hex');
export async function passwordHash(password:string) {
 const salt=randomBytes(16).toString('hex');
 const key=await scrypt(password,salt,64) as Buffer;
 return salt+':'+key.toString('hex');
}
export async function passwordMatches(password:string, stored:string) {
 const [salt,key]=stored.split(':');
 const actual=await scrypt(password,salt,64) as Buffer;
 const expected=Buffer.from(key,'hex');
 return actual.length===expected.length && timingSafeEqual(actual,expected);
}
export async function issueSession(uid:string) {
 const access=randomBytes(32).toString('hex'), refresh=randomBytes(32).toString('hex');
 const seconds=Number(process.env.SESSION_SECONDS ?? 3600);
 await pool.query("INSERT INTO sessions VALUES($1,$2,$3,now()+$4*interval '1 second',now()+interval '30 days')",[hash(access),hash(refresh),uid,seconds]);
 return { access_token:access, refresh_token:refresh, expires_in:seconds, sub:uid };
}
export type Identity={uid:string;space_id:string;expires_at:Date};
export async function identity(authorization:string|undefined):Promise<Identity|null> {
 if (!authorization?.startsWith('Bearer ')) return null;
 const result=await pool.query('SELECT s.uid,m.space_id,s.expires_at FROM sessions s JOIN members m USING(uid) WHERE access_hash=$1 AND expires_at>now()',[hash(authorization.slice(7))]);
 return result.rows[0] ?? null;
}
