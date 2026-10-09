// Durable client outbox. Transports and the drawing editor are deliberately separate.
export type Element = Record<string,any> & {id:string};
export type FileData = {id:string;mimeType:string;dataURL:string;created:number};
export type Operation = {id:string;patch:Record<string,any>;expected?:Record<string,any>};
export type Request = {type:'update';requestId:string;operations:Operation[];files:FileData[]};
export type State = {version:1;uid:string;revision:number;canonical:Element[];files:Record<string,FileData>;pending:Request[];viewport:{scrollX:number;scrollY:number;zoom:{value:number}};seen:number;latest:Record<string,{revision:number;ids:string[];updated:number}>};
const ignored=new Set(['id','version','versionNonce','updated','status']);
export function same(a:any,b:any):boolean {
 if(a===b)return true;
 if(a===null||b===null||typeof a!=='object'||typeof b!=='object')return false;
 if(Array.isArray(a)!==Array.isArray(b))return false;
 const keys=Object.keys(a);return keys.length===Object.keys(b).length&&keys.every(key=>Object.hasOwn(b,key)&&same(a[key],b[key]));
}
export const copy=<T>(value:T):T=>JSON.parse(JSON.stringify(value));
export function fresh(uid:string):State{return {version:1,uid,revision:0,canonical:[],files:{},pending:[],viewport:{scrollX:0,scrollY:0,zoom:{value:1}},seen:0,latest:{}};}
export function materialize(state:State):Element[] {
 const map=new Map(state.canonical.map(e=>[e.id,copy(e)]));
 for(const request of state.pending)for(const op of request.operations){const current=map.get(op.id)??{id:op.id};for(const [k,v] of Object.entries(op.patch)){if(op.expected&&Object.hasOwn(op.expected,k)&&!same(current[k],op.expected[k]))continue;current[k]=copy(v);}map.set(op.id,current);}
 return [...map.values()].sort((a,b)=>{const x=a.index??("z"+a.id),y=b.index??("z"+b.id);return x<y?-1:x>y?1:0;});
}
export function difference(before:Element[],after:readonly Element[],conditional=false):Operation[] {
 const old=new Map(before.map(e=>[e.id,e]));const result:Operation[]=[];const ids=new Set(after.map(e=>e.id));
 for(const element of after){
  // The image tool creates a temporary element before the file chooser resolves.
  // Send the complete element only once it actually has a file, never that placeholder.
  if(element.type==='image'&&!element.fileId)continue;
  const previous=old.get(element.id);const prior=previous?.type==='image'&&!previous.fileId?undefined:previous;
  const patch:Record<string,any>={},expected:Record<string,any>={};
  for(const [key,value] of Object.entries(element))if(!ignored.has(key)&&value!==undefined&&!same(prior?.[key],value)){patch[key]=copy(value);if(conditional&&prior&&prior[key]!==undefined)expected[key]=copy(prior[key]);}
  if(Object.keys(patch).length){if(element.type==='image')patch.status='saved';result.push({id:element.id,patch,...(conditional?{expected}:{})});}
 }
 for(const e of before)if(!ids.has(e.id)&&!e.isDeleted&&!(e.type==='image'&&!e.fileId))result.push({id:e.id,patch:{isDeleted:true},...(conditional?{expected:{isDeleted:false}}:{})});
 return result;
}
export function enqueue(state:State,operations:Operation[],files:FileData[],inFlight:string|null,conditional=false) {
 if(!operations.length)return;
 if(files.length>1){
  const assigned=new Set<Operation>();
  for(const file of files){const linked=operations.filter(op=>op.patch.fileId===file.id);for(const op of linked)assigned.add(op);if(linked.length)enqueue(state,linked,[file],inFlight,conditional);}
  enqueue(state,operations.filter(op=>!assigned.has(op)),[],inFlight,conditional);return;
 }
 let tail=state.pending.at(-1);
 const bytes=(value:any)=>new TextEncoder().encode(JSON.stringify(value)).length;
 const tooLarge=tail&&bytes(tail)+bytes({operations,files})>12*1024*1024-65536;
 if(!tail||tail.requestId===inFlight||conditional||tail.operations.some(o=>o.expected)||tail.operations.length+operations.length>1000||tooLarge){tail={type:'update',requestId:crypto.randomUUID(),operations:[],files:[]};state.pending.push(tail);}
 const map=new Map(tail.operations.map(o=>[o.id,o]));
 for(const op of operations){const existing=map.get(op.id);if(existing&&!op.expected)Object.assign(existing.patch,op.patch);else map.set(op.id,copy(op));}
 tail.operations=[...map.values()];
 const included=new Map(tail.files.map(f=>[f.id,f]));for(const file of files)included.set(file.id,copy(file));tail.files=[...included.values()];
}
export function accept(state:State,message:any) {
 if(message.type==='ack')state.pending=state.pending.filter(r=>r.requestId!==message.requestId);
 if(message.revision<state.revision)return;
 if(message.type==='snapshot')state.canonical=copy(message.elements);
 else {const map=new Map(state.canonical.map(e=>[e.id,e]));for(const e of message.elements??[])map.set(e.id,copy(e));state.canonical=[...map.values()];}
 state.revision=message.revision;state.latest=copy(message.latest??state.latest);state.seen=Math.max(state.seen,message.seen??0);
 for(const file of message.files??[])state.files[file.id]=copy(file);
}
export function peerChange(state:State){return Object.entries(state.latest).filter(([uid])=>uid!==state.uid).map(([,v])=>v).sort((a,b)=>b.revision-a.revision)[0];}
