import { migrate } from './db.js';
import { buildApp } from './app.js';
await migrate();
const app=await buildApp();
await app.listen({port:Number(process.env.PORT??8787),host:process.env.HOST??'127.0.0.1'});
for(const signal of ['SIGINT','SIGTERM'])process.on(signal,()=>void app.close());
