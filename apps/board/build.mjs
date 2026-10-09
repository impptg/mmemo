import {build} from 'esbuild';
import {mkdir,rm,cp,writeFile,readFile,readdir} from 'node:fs/promises';
import {createRequire} from 'node:module';
import path from 'node:path';
const require=createRequire(import.meta.url);
const out=new URL('../desktop/web/board/',import.meta.url);
await rm(out,{recursive:true,force:true});await mkdir(out,{recursive:true});
const bundled=await build({metafile:true,legalComments:'external',entryPoints:[new URL('src/main.tsx',import.meta.url).pathname],outfile:new URL('board.js',out).pathname,bundle:true,conditions:['production'],format:'iife',target:['safari16'],minify:true,define:{'process.env.NODE_ENV':'"production"','import.meta.env.DEV':'false','import.meta.env.PROD':'true'},loader:{'.woff2':'file','.woff':'file','.ttf':'file','.wasm':'binary'},banner:{js:'window.EXCALIDRAW_ASSET_PATH="./";'},logLevel:'warning'});
const pkg=path.resolve(path.dirname(require.resolve('@excalidraw/excalidraw')),'../..');
await cp(path.join(pkg,'dist/prod/fonts'),new URL('fonts',out),{recursive:true});
await writeFile(new URL('index.html',out),`<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'none'; worker-src blob:; base-uri 'none'; form-action 'none'"><title>mmemo 双人留言画板</title><link rel="stylesheet" href="board.css"><script defer src="board.js"></script></head><body><div id="root"></div></body></html>`);
await cp(new URL('licenses/',import.meta.url),new URL('licenses/',out),{recursive:true});
// Preserve notices for every dependency that actually contributes bundled code.
const packages=new Map();
for(const input of Object.keys(bundled.metafile.inputs)) {
 if(!input.includes('node_modules'))continue;
 let directory=path.dirname(path.resolve(input));
 while(directory!==path.dirname(directory)) {
  try {
   const metadata=JSON.parse(await readFile(path.join(directory,'package.json'),'utf8'));
   if(metadata.name){packages.set(metadata.name,{directory,metadata});break;}
  }catch{}
  directory=path.dirname(directory);
 }
}
const notices=['Bundled dependency notices. Font licenses are in licenses/.'];
for(const [name,{directory,metadata}] of [...packages].sort(([a],[b])=>a.localeCompare(b))) {
 notices.push(`\n${name} ${metadata.version} — ${metadata.license??'see package notice'}`);
 for(const filename of (await readdir(directory)).filter(n=>/^(licen[sc]e|copying|notice)(\.|$)/i.test(n))) {
  try{notices.push(await readFile(path.join(directory,filename),'utf8'));}catch{}
 }
 if(name==='@excalidraw/excalidraw')notices.push(await readFile(new URL('licenses/Excalidraw.txt',import.meta.url),'utf8'));
}
await writeFile(new URL('THIRD_PARTY_LICENSES.txt',out),notices.join('\n'));
console.log('Board assets bundled for offline WebKit use.');
