import pg from 'pg';
import { readFile } from 'node:fs/promises';
export const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL, max: 5, connectionTimeoutMillis:5000, idleTimeoutMillis:30000, statement_timeout:10000 });
pool.on('error', e => console.error('database idle connection:', e.message));
export async function migrate() {
 const c = await pool.connect();
 try {
  await c.query('BEGIN');
  await c.query('SELECT pg_advisory_xact_lock(7123456)');
  await c.query('CREATE TABLE IF NOT EXISTS schema_migrations (name text PRIMARY KEY, applied_at timestamptz DEFAULT now())');
  const name='001_initial.sql';
  if (!(await c.query('SELECT 1 FROM schema_migrations WHERE name=$1',[name])).rowCount) {
   await c.query(await readFile(new URL('../../../database/migrations/'+name, import.meta.url),'utf8'));
   await c.query('INSERT INTO schema_migrations(name) VALUES($1)',[name]);
  }
  await c.query('COMMIT');
 } catch(e) { await c.query('ROLLBACK'); throw e; } finally { c.release(); }
}
