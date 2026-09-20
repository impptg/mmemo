import { z } from 'zod';
export const identities = [
  { username: 'user_pptg', uid: '2100541450115510274', avatar: 'frog' },
  { username: 'user_mm', uid: '2100541456125558785', avatar: 'raccoon' },
] as const;
const uid = z.enum(['2100541450115510274', '2100541456125558785']);
const due = z.string().refine(s => {
  if (s === '') return true;
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(s)) return false;
  const date = new Date(s + ':00Z');
  return !isNaN(date.valueOf()) && date.toISOString().slice(0,16) === s;
}, 'Invalid date');
export const patchSchema = z.object({ title: z.string().trim().min(1).max(200).optional(), due: due.optional(), done: z.boolean().optional(), participants: z.array(uid).min(1).max(2).refine(v => new Set(v).size === v.length).optional() }).strict();
export const changesSchema = z.object({ changes: z.array(z.object({ action: z.enum(['create','update','delete']), id: z.string().min(1).max(100), patch: patchSchema.optional() }).strict()).min(1).max(20) }).strict();
export const loginSchema = z.object({ username: z.string().max(100), password: z.string().min(1).max(256) }).strict();
export const refreshSchema = z.object({ refresh_token: z.string().min(32).max(200) }).strict();
export const ackSchema = z.object({ ids: z.array(z.uuid()).min(1).max(100) }).strict();
export type Todo = { id:string; title:string; due:string; done:boolean; created_by:string; participants:string[] };
export type SyncEvent = { kind:'todos'|'hearts'|'resync'; recipient?:string };
