import React, {useEffect,useState} from 'react';
import {createRoot} from 'react-dom/client';
import {Excalidraw,MainMenu,CaptureUpdateAction,restoreElements,reconcileElements} from '@excalidraw/excalidraw';
import type {ExcalidrawImperativeAPI} from '@excalidraw/excalidraw/types';
import {accept,copy,difference,enqueue,fresh,materialize,peerChange,same,type State,type Element,type FileData} from './sync';
import '@excalidraw/excalidraw/index.css';
import './style.css';

declare global {interface Window {webkit:any;mmemoBoard:any;EXCALIDRAW_ASSET_PATH:string;}}
const native=(body:any)=>window.webkit.messageHandlers.mmemo.postMessage(body);
let state:State,api:ExcalidrawImperativeAPI|null=null,observed:Element[]=[],initialized=false,online=false,visible=false,inFlight:string|null=null,sequence=0,persisted=0,error='',historyAction=false,applying=false;
let sendTimer:ReturnType<typeof setTimeout>|undefined,renderUI=()=>{};
const collaborators=new Map<any,any>();
let pointerAt=0;
let interacting=false;const activeIds=new Set<string>();
document.addEventListener('pointerdown',event=>{
 if(!(event.target instanceof HTMLCanvasElement))return;
 interacting=true;activeIds.clear();
 for(const [id,selected] of Object.entries(api?.getAppState().selectedElementIds??{}))if(selected)activeIds.add(id);
},true);
const finishInteraction=()=>{if(!interacting)return;interacting=false;activeIds.clear();requestAnimationFrame(()=>applyRemote());};
document.addEventListener('pointerup',finishInteraction,true);
document.addEventListener('pointercancel',finishInteraction,true);
function persist(){if(!initialized)return;native({action:'boardPersist',sequence:++sequence,state});}
function unread(){const peer=peerChange(state);return !!peer&&peer.revision>state.seen;}
function notify(){native({action:'boardUnread',unread:unread()});renderUI();}
function read(){if(!initialized||!visible||!online)return;state.seen=state.revision;native({action:'boardSend',message:{type:'read',revision:state.seen}});persist();notify();}
function scheduleSend(){if(sendTimer)return;sendTimer=setTimeout(()=>{sendTimer=undefined;send();},100);}
function send(){if(!online||!initialized||inFlight||error||persisted<sequence)return;const next=state.pending[0];if(!next)return;inFlight=next.requestId;native({action:'boardSend',message:next});renderUI();}
function applyRemote(){if(!api||!initialized)return;
 const current=api.getSceneElementsIncludingDeleted();const appState=api.getAppState();
 const restored=restoreElements(materialize(state) as any,current);
 const changed=new Set(difference(current as any,restored as any).map(op=>op.id));
 const target=restored.map(e=>{
  const local=current.find(c=>c.id===e.id);
  // Excalidraw's drag handlers retain the actual mutable element instance.
  // Replacing it mid-gesture leaves the handler drawing into a detached object.
  if(interacting&&activeIds.has(e.id)&&local)return local;
  return changed.has(e.id)?{...e,version:Math.max(e.version??1,local?.version??0)+1,versionNonce:0}:local??e;
 });
 // Official reconciliation preserves the element currently being drawn/edited.
 const next=reconcileElements(current,target as any,appState);
 observed=copy(next as any);applying=true;
 api.addFiles(Object.values(state.files) as any);
 api.updateScene({elements:next,captureUpdate:CaptureUpdateAction.NEVER});
 applying=false;
}
function changes(elements:readonly any[],appState:any,files:Record<string,FileData>){if(!initialized)return;
 if(!applying){
  // Reconciliation may retain a local active element before onChange has queued it
  // (notably an image while the native chooser is resolving). It is still new.
  const known=new Set(materialize(state).map(e=>e.id));
  const ops=difference(observed.filter(e=>known.has(e.id)),elements,historyAction);historyAction=false;
  if(interacting)for(const op of ops)activeIds.add(op.id);
  if(ops.length){const upload:FileData[]=[];for(const file of Object.values(files))if(!state.files[file.id]){upload.push(copy(file));state.files[file.id]=copy(file);}
   enqueue(state,ops,upload,inFlight,ops.some(o=>o.expected!==undefined));observed=copy(elements as any);persist();scheduleSend();renderUI();
  }else observed=copy(elements as any);
 }
 const viewport={scrollX:appState.scrollX,scrollY:appState.scrollY,zoom:{value:appState.zoom.value}};
 if(!same(state.viewport,viewport)){state.viewport=viewport;persist();}
}
function undoGuard(event:KeyboardEvent){if((event.metaKey||event.ctrlKey)&&event.key.toLowerCase()==='z')historyAction=true;}
document.addEventListener('keydown',undoGuard,true);
document.addEventListener('click',event=>{const button=(event.target as HTMLElement).closest('button');if(button?.matches('[data-testid="button-undo"],[data-testid="button-redo"]'))historyAction=true;},true);
window.addEventListener('error',event=>native({action:'error',message:event.message}));
window.addEventListener('unhandledrejection',event=>native({action:'error',message:String(event.reason)}));
window.mmemoBoard={
 initialize(uid:string,saved:any,isVisible:boolean){
  if(initialized)return;if(saved && (saved.version!==1||saved.uid!==uid)){error='画板本地数据无法读取，原文件已保留';renderUI();return;}
  state=saved?copy(saved):fresh(uid);observed=materialize(state);visible=isVisible;initialized=true;
  createRoot(document.getElementById('root')!).render(<Board/>);notify();
 },
 persisted(value:number,message?:string){if(message){error='本地保存失败，修改仍在窗口中，请检查磁盘后重试';renderUI();return;}persisted=Math.max(persisted,value);scheduleSend();},
 connection(connected:boolean){online=connected;inFlight=null;if(!connected){collaborators.clear();api?.updateScene({collaborators});}renderUI();},
 visibility(value:boolean){visible=value;if(!value){collaborators.clear();api?.updateScene({collaborators});}else{read();applyRemote();}},
 receive(message:any){if(!initialized)return;
  if(message.type==='pointer'){if(message.uid===state.uid)return;collaborators.set(message.session,{pointer:message.pointer,button:message.button,username:message.uid=== '2100541450115510274'?'小青蛙':'小浣熊',color:{background:'#daf0df',stroke:'#4a8260'}});api?.updateScene({collaborators:new Map(collaborators)});return;}
  if(message.type==='leave'){collaborators.delete(message.session);api?.updateScene({collaborators:new Map(collaborators)});return;}
  if(message.type==='error'){error=message.retryable?'云端保存暂不可用，修改已保留':`修改未同步：${message.message}`;inFlight=null;renderUI();return;}
  if(!['snapshot','update','ack'].includes(message.type))return;
  if(message.type==='snapshot'){online=true;error='';inFlight=null;}
  if(message.type==='ack'&&message.requestId===inFlight)inFlight=null;
  accept(state,message);applyRemote();persist();notify();read();scheduleSend();
 },
 flush(){persist();return {pending:state.pending.length,sequence,state:copy(state)};},
 async prepareToQuit(){
  (document.activeElement as HTMLElement)?.blur();
  // Hidden WKWebViews can suspend animation frames indefinitely. Let text blur
  // settle, but always finish saving when the board is closed or never opened.
  await new Promise<void>(resolve=>{
   const timer=setTimeout(resolve,100);
   requestAnimationFrame(()=>requestAnimationFrame(()=>{clearTimeout(timer);resolve();}));
  });
  persist();return copy(state);
 },
 retry(){error='';persist();native({action:'boardReconnect'});renderUI();},
 get api(){return api;},
 inspect(){return {initialized,online,visible,pending:state?.pending.length??0,inFlight,revision:state?.revision,unread:initialized&&unread(),viewport:state?.viewport,latest:state?.latest,error,elements:api?.getSceneElementsIncludingDeleted(),files:api?.getFiles(),collaborators:[...collaborators.keys()]};}
};
function Board(){const [,updateUI]=useState(0);useEffect(()=>{renderUI=()=>updateUI(n=>n+1);return()=>{renderUI=()=>{};};},[]);
 const pending=state.pending.length;const latest=peerChange(state);
 const jump=()=>{if(!api||!latest)return;const elements=api.getSceneElements().filter(e=>latest.ids.includes(e.id));if(elements.length)api.scrollToContent(elements,{fitToContent:true,animate:true});else {const deleted=state.canonical.find(e=>latest.ids.includes(e.id));if(deleted)api.scrollToContent([deleted] as any,{animate:true});}};
 const status=error||(online?(pending?'正在同步…':'已保存'):'离线 · 修改保存在本机');
 return <><div id="canvas"><Excalidraw name="双人留言画板" langCode="zh-CN" isCollaborating autoFocus handleKeyboardGlobally
  initialData={{elements:restoreElements(observed as any,null),appState:{...state.viewport,viewBackgroundColor:'#fafaf8',currentItemFontFamily:1} as any,files:state.files as any,scrollToContent:false}}
  excalidrawAPI={value=>{api=value;setTimeout(()=>{applyRemote();read();},0);}}
  onChange={changes}
  onPointerUpdate={data=>{if(!online||!visible||performance.now()-pointerAt<50)return;pointerAt=performance.now();native({action:'boardSend',message:{type:'pointer',pointer:data.pointer,button:data.button}});}}
  validateEmbeddable={false} UIOptions={{canvasActions:{loadScene:false,saveToActiveFile:false,export:false,saveAsImage:false}}}
 ><MainMenu><MainMenu.DefaultItems.ClearCanvas/><MainMenu.DefaultItems.ToggleTheme/></MainMenu></Excalidraw></div>
 <div className="board-context"><span id="boardStatus" role="status" className={error?'error':''}>{status}</span>{error&&<button onClick={()=>window.mmemoBoard.retry()}>重试</button>}<button id="jumpLatest" disabled={!latest} onClick={jump}>跳到对方最新修改</button></div></>;
}
native({action:'boardReady'});
