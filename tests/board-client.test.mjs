import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from '../apps/board/node_modules/esbuild/lib/main.js';
const result=await build({entryPoints:['apps/board/src/sync.ts'],bundle:true,platform:'node',format:'esm',write:false});
const {fresh,enqueue,difference,materialize,accept,peerChange}=await import('data:text/javascript;base64,'+Buffer.from(result.outputFiles[0].text).toString('base64'));
const element={id:'a',type:'rectangle',x:10,y:20,width:100,height:80,isDeleted:false,version:1};
test('pending field patches preserve concurrent peer changes and survive serialization',()=>{
 const s=fresh('me');s.canonical=[element];
 enqueue(s,difference([element],[{...element,x:50}]),[],null);
 accept(s,{type:'update',revision:2,elements:[{...element,backgroundColor:'#abc',version:2}],latest:{peer:{revision:2,ids:['a']}}});
 const restored=JSON.parse(JSON.stringify(s));assert.equal(materialize(restored)[0].x,50);assert.equal(materialize(restored)[0].backgroundColor,'#abc');
 assert.equal(peerChange(restored).revision,2);
});
test('in-flight request body remains immutable; newer local edits keep their own outbox entry',()=>{
 const s=fresh('me');s.canonical=[element];enqueue(s,[{id:'a',patch:{x:50}}],[],null);
 const request=JSON.stringify(s.pending[0]);const id=s.pending[0].requestId;
 enqueue(s,[{id:'a',patch:{x:60}}],[],id);assert.equal(s.pending.length,2);assert.equal(JSON.stringify(s.pending[0]),request);
 accept(s,{type:'ack',requestId:id,revision:1,elements:[{...element,x:50}]});assert.equal(materialize(s)[0].x,60);
});
test('stale acknowledgements clear their outbox entry without overwriting a newer snapshot',()=>{
 const s=fresh('me');enqueue(s,[{id:'a',patch:{x:50}}],[],null);const id=s.pending[0].requestId;
 accept(s,{type:'snapshot',revision:5,elements:[{...element,x:80}],files:[]});
 accept(s,{type:'ack',requestId:id,revision:4,elements:[{...element,x:50}]});assert.equal(s.pending.length,0);assert.equal(materialize(s)[0].x,80);
});
test('conditional undo does not revert a field since changed by a peer; deletion leaves a tombstone',()=>{
 const s=fresh('me');s.canonical=[{...element,x:99}];enqueue(s,[{id:'a',patch:{x:10},expected:{x:50}}],[],null,true);assert.equal(materialize(s)[0].x,99);
 assert.deepEqual(difference([element],[]),[{id:'a',patch:{isDeleted:true}}]);
});

test('JSONB object key order is not a content change; fractional indexes keep scene order',()=>{
 const s=fresh('me');s.canonical=[{...element,id:'z',index:'a0'},{...element,id:'a',index:'a1'}];
 assert.deepEqual(materialize(s).map(e=>e.id),['z','a']);
 const left={...element,roundness:{type:3,value:20}};const right={...element,roundness:{value:20,type:3}};
 assert.deepEqual(difference([left],[right]),[]);
});

test('image picker placeholders never enter the outbox; resolving a file sends a complete image',()=>{
 const placeholder={...element,type:'image',fileId:null,scale:[1,1]};
 assert.deepEqual(difference([], [placeholder]),[]);
 assert.deepEqual(difference([placeholder],[]),[]);
 const image={...placeholder,fileId:'png'};
 const [operation]=difference([placeholder],[image]);
 assert.equal(operation.patch.type,'image');assert.equal(operation.patch.fileId,'png');assert.equal(operation.patch.x,10);
});

test('multiple image imports split into transport-sized durable batches',()=>{
 const s=fresh('me');const files=['png1','png2'].map(id=>({id,mimeType:'image/png',created:1,dataURL:'x'.repeat(7*1024*1024)}));
 enqueue(s,files.map(f=>({id:f.id,patch:{type:'image',fileId:f.id}})),files,null);
 assert.equal(s.pending.length,2);
 for(const request of s.pending){assert.ok(Buffer.byteLength(JSON.stringify(request))<12*1024*1024);assert.equal(request.operations[0].patch.fileId,request.files[0].id);}
});
