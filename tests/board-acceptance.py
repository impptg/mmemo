"""Native pair acceptance: real windows, native mouse input, outbox, restart and stored content."""
import importlib.util,json,time,threading,os,subprocess,urllib.request,base64,uuid,datetime,hashlib
from urllib.parse import urlsplit
from pathlib import Path
spec=importlib.util.spec_from_file_location('qa',Path(__file__).with_name('native-board.py'));q=importlib.util.module_from_spec(spec);spec.loader.exec_module(q)
a,b=q.NAMES
report=[]
success=False
started=datetime.datetime.now(datetime.timezone.utc).isoformat()
database=os.environ.get('BOARD_QA_DATABASE_URL','postgres://mmemo:local-testing-only@127.0.0.1:55432/mmemo_board_qa')
address=urlsplit(database)
if address.hostname not in ['127.0.0.1','localhost'] or address.path!='/mmemo_board_qa':raise RuntimeError('Board QA requires the localhost mmemo_board_qa database')
server=None
serverLog=open(q.WORK/'backend.log','a')
def startBackend():
 global server
 server=subprocess.Popen(['node','apps/server/dist/index.js'],cwd=q.ROOT,env={**os.environ,'DATABASE_URL':database,'PORT':'18787','ADMIN_TOKEN':'board-qa','LOG_LEVEL':'warn'},stdout=serverLog,stderr=serverLog)
 end=time.monotonic()+15
 while time.monotonic()<end:
  try:
   with urllib.request.urlopen('http://127.0.0.1:18787/health') as response:
    if response.status==200:return
  except Exception:time.sleep(.1)
 raise RuntimeError('QA backend failed to start')
(q.WORK/'fixture.png').write_bytes(base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg=='))
def record(check,**data):
 report.append({'check':check,**data});print(check,json.dumps(data,ensure_ascii=False),flush=True)
def visible(s,id):return any(e['id']==id and not e['isDeleted'] for e in s['board']['elements'])
def draw(actor,tool,points):
 before={e['id'] for e in q.state(actor)['board']['elements']}
 q.js(actor,f"document.querySelector('[data-testid=toolbar-{tool}]').click();true")
 q.command(actor,'draw',points=points)
 state=q.wait(actor,lambda s:any(e['id'] not in before for e in s['board']['elements']))
 return next(e['id'] for e in state['board']['elements'] if e['id'] not in before)
try:
 startBackend()
 for name in q.NAMES:q.start(name);q.wait(name,lambda s:s['board'].get('online'))
 q.command(a,'show')
 # The exact entry button, rather than the direct open test command.
 q.command(a,'listJS',script="document.getElementById('openBoard').click();true")
 q.wait(a,lambda s:s['visible']);q.command(b,'open')
 origin=10000+int(time.time()%10000)*500
 for name in q.NAMES:q.js(name,f'window.mmemoBoard.api.updateScene({{appState:{{scrollX:{-origin},scrollY:0,zoom:{{value:1}}}}}});true')
 time.sleep(.15)
 record('画板 icon 打开独立窗口；两个真实账号连接同一画板')
 before={e['id'] for e in q.state(b)['board']['elements']}
 q.js(a,"document.querySelector('[data-testid=toolbar-freedraw]').click();true")
 thread=threading.Thread(target=lambda:q.command(a,'draw',points=[[480+i*2,310+(i%10)*2] for i in range(50)]));thread.start();time.sleep(.7)
 mid=q.state(b)['board'];live=[e for e in mid['elements'] if e['id'] not in before]
 assert any(1<len(e.get('points',[]))<50 for e in live),live
 # The peer edit must not activate another local macOS app during A's drag:
 # real remote peers are on different machines and cannot steal that focus.
 whileDrawing='active-'+str(uuid.uuid4())
 peerElement={'id':whileDrawing,'type':'rectangle','x':origin+720,'y':440,'width':80,'height':70,'angle':0,'strokeColor':'#222222','backgroundColor':'transparent','fillStyle':'solid','strokeWidth':2,'strokeStyle':'solid','roughness':1,'opacity':100,'groupIds':[],'frameId':None,'index':None,'roundness':None,'seed':1234,'version':1,'versionNonce':1,'updated':int(time.time()*1000),'isDeleted':False,'boundElements':None,'link':None,'locked':False}
 q.js(b,f"window.mmemoBoard.api.updateScene({{elements:[...window.mmemoBoard.api.getSceneElementsIncludingDeleted(),{json.dumps(peerElement)}],captureUpdate:'IMMEDIATELY'}});true")
 thread.join();stroke=q.wait(b,lambda s:any(e['id'] not in before and len(e.get('points',[]))>=45 for e in s['board']['elements']))
 q.wait(a,lambda s:visible(s,whileDrawing))
 assert stroke['board']['collaborators']
 record('原生鼠标绘画：对方在绘制完成前收到中间笔画和光标',intermediatePoints=len(live[0]['points']))
 record('绘制途中收到对方图形，本地完整笔画与对方图形均保留')
 rect=draw(a,'rectangle',[[470,410],[530,455],[590,490],[590,490]])
 q.wait(b,lambda s:visible(s,rect))
 peerRect=draw(b,'ellipse',[[470,230],[530,260],[590,290],[590,290]])
 q.wait(a,lambda s:visible(s,peerRect));record('双向绘制图形并同步')
 # Actual editor text input and native canvas entry.
 drawStart={e['id'] for e in q.state(a)['board']['elements']}
 q.js(a,"document.querySelector('[data-testid=toolbar-text]').click();true");q.command(a,'draw',points=[[500,550],[500,550]])
 q.js(a,"var t=document.querySelector('textarea.excalidraw-wysiwyg');t.value='双人留言验收 ♡';t.dispatchEvent(new Event('input',{bubbles:true}));true")
 textCamera=q.state(a)['board']['viewport']
 q.js(b,f"window.mmemoBoard.api.updateScene({{elements:window.mmemoBoard.api.getSceneElementsIncludingDeleted().map(e=>e.id==={json.dumps(peerRect)}?{{...e,backgroundColor:'#b0ccde',version:e.version+1,versionNonce:123456,updated:Date.now()}}:e),captureUpdate:'IMMEDIATELY'}});true")
 q.wait(a,lambda s:any(e['id']==peerRect and e['backgroundColor']=='#b0ccde' for e in s['board']['elements']))
 assert q.js(a,"document.activeElement?.matches('textarea.excalidraw-wysiwyg') && document.activeElement.value==='双人留言验收 ♡'")['value'] is True
 assert q.state(a)['board']['viewport']==textCamera
 q.js(a,"document.activeElement.blur();true")
 record('对方修改不打断正在输入的文字，也不改变本地视野')
 text=q.wait(b,lambda s:any(e.get('text')=='双人留言验收 ♡' and e['id'] not in drawStart for e in s['board']['elements']))
 textId=next(e['id'] for e in text['board']['elements'] if e.get('text')=='双人留言验收 ♡' and e['id'] not in drawStart)
 q.js(a,"document.querySelector('[data-testid=button-undo]').click();true");q.wait(b,lambda s:not visible(s,textId));assert visible(q.state(b),peerRect)
 q.js(a,"document.querySelector('[data-testid=button-redo]').click();true");q.wait(b,lambda s:visible(s,textId));record('中文文字、撤销与重做；对方独立图形保留')
 # Same element, different fields: two editors must converge without whole-scene replacement.
 original=next(e for e in q.state(a)['board']['elements'] if e['id']==rect)
 errors=[]
 def edit(actor,patch):
  try:q.js(actor,f"window.mmemoBoard.api.updateScene({{elements:window.mmemoBoard.api.getSceneElementsIncludingDeleted().map(e=>e.id==={json.dumps(rect)}?{{...e,...{json.dumps(patch)},version:e.version+1,versionNonce:Math.floor(Math.random()*1000000000),updated:Date.now()}}:e),captureUpdate:'IMMEDIATELY'}});true")
  except Exception as error:errors.append(error)
 tasks=[threading.Thread(target=edit,args=(a,{'x':original['x']+80})),threading.Thread(target=edit,args=(b,{'backgroundColor':'#cbe7d0'}))]
 for task in tasks:task.start()
 for task in tasks:task.join()
 assert not errors,errors
 for actor in q.NAMES:q.wait(actor,lambda s:any(e['id']==rect and e['x']==original['x']+80 and e['backgroundColor']=='#cbe7d0' for e in s['board']['elements']))
 q.js(a,"document.querySelector('[data-testid=button-undo]').click();true")
 for actor in q.NAMES:q.wait(actor,lambda s:any(e['id']==rect and e['x']==original['x'] and e['backgroundColor']=='#cbe7d0' for e in s['board']['elements']))
 record('双方同时修改同一图形的不同属性均保留；撤销自己的位移保留对方颜色')
 # Import through Excalidraw's image tool and the native file chooser.
 imageBefore={e['id'] for e in q.state(a)['board']['elements']}
 coordinates=json.loads(q.js(a,"var r=document.querySelector('[data-testid=toolbar-image]').closest('label').getBoundingClientRect();JSON.stringify([r.x+r.width/2,r.y+r.height/2])")['value'])
 q.command(a,'draw',points=[coordinates,coordinates])
 time.sleep(.7);q.command(a,'draw',points=[[680,370],[680,370]])
 imported=q.wait(b,lambda s:any(e['id'] not in imageBefore and e['type']=='image' for e in s['board']['elements']))
 image=next(e for e in imported['board']['elements'] if e['id'] not in imageBefore and e['type']=='image')
 assert imported['board']['files'][image['fileId']]['dataURL'].startswith('data:image/png;base64,')
 record('图片工具通过原生文件选择器导入 PNG，并传到对方')
 before=q.state(a)['board']['viewport'];q.js(b,"window.mmemoBoard.api.updateScene({appState:{scrollX:1234,scrollY:-432,zoom:{value:1.3}}});true");time.sleep(.2)
 assert q.state(a)['board']['viewport']==before;record('双方视野独立')
 q.command(b,'close');new=draw(a,'diamond',[[430,440],[480,480],[530,520],[530,520]])
 s=q.wait(b,lambda s:s['unread'] and visible(s,new));assert not s['visible']
 dot=q.command(b,'listJS',script="document.getElementById('openBoard').querySelector('.board-dot').hidden")['value'];assert dot is False
 q.command(b,'open');q.wait(b,lambda s:not s['unread']);q.js(b,"document.getElementById('jumpLatest').click();true");time.sleep(.5)
 assert q.state(b)['board']['viewport']['scrollX']!=1234;record('关闭时显示红点且不弹窗；打开清除；跳转最新修改')
 q.command(b,'outside');assert q.state(b)['visible'];q.command(b,'resize');frame=q.state(b)['frame'];assert frame[2:]==[980,700]
 camera=q.state(b)['board']['viewport'];q.command(b,'close');q.command(b,'open');assert q.state(b)['board']['viewport']==camera;record('独立窗口保持打开，可调整大小，关闭重开保留视野')
 # Fully disconnect native transport, make local changes, kill app before reconnect.
 q.command(a,'disconnect');offline=draw(a,'rectangle',[[420,220],[470,260],[520,300],[520,300]])
 q.wait(a,lambda s:s['board']['pending']>0);assert not visible(q.state(b),offline)
 cache=json.loads((q.WORK/'accounts'/a/'board-state.json').read_text());assert cache['pending']
 q.stop(a);q.start(a);q.wait(a,lambda s:s['board'].get('online'));q.wait(b,lambda s:visible(s,offline));q.wait(a,lambda s:s['board']['pending']==0)
 record('断网修改落盘；离线期间强制退出后，重启补同步且不重复')
 server.terminate();server.wait(timeout=10)
 q.wait(a,lambda s:not s['board']['online']);q.wait(b,lambda s:not s['board']['online'])
 q.command(a,'open');outage=draw(a,'ellipse',[[410,350],[440,390],[490,430],[490,430]])
 q.wait(a,lambda s:s['board']['pending']>0)
 startBackend();q.wait(a,lambda s:s['board']['online'] and s['board']['pending']==0,40);q.wait(b,lambda s:visible(s,outage),40)
 assert visible(q.state(b),image['id'])
 record('后端真实停止再启动：恢复既有内容和图片，补同步停机期间的修改')
 q.command(b,'snapshot',name='board-accepted.png')
 # Repeated snapshots must never create element-order or version synchronization loops.
 q.wait(a,lambda s:s['board']['pending']==0);q.wait(b,lambda s:s['board']['pending']==0)
 r=q.state(a)['board']['revision'];time.sleep(1.5);assert q.state(a)['board']['revision']==r;record('双方空闲时没有反复保存或排序抖动')
 q.stop(b);q.start(b);q.wait(b,lambda s:s['board'].get('online'));assert visible(q.state(b),offline)
 assert q.state(b)['frame']==frame;assert q.state(b)['board']['viewport']==camera
 record('应用重启后恢复画板、窗口位置大小和各自视野')
 q.command(a,'disconnect');q.command(a,'open');q.js(a,"document.querySelector('[data-testid=toolbar-text]').click();true")
 q.command(a,'draw',points=[[750,250],[750,250]])
 quittingText='正常退出保存未结束输入 '+str(uuid.uuid4())
 q.js(a,f"var t=document.querySelector('textarea.excalidraw-wysiwyg');t.value={json.dumps(quittingText)};t.dispatchEvent(new Event('input',{{bubbles:true}}));true")
 q.command(a,'quit');q.processes[a].wait(timeout=15)
 q.start(a);q.wait(a,lambda s:s['board'].get('online') and s['board']['pending']==0)
 q.wait(b,lambda s:any(e.get('text')==quittingText for e in s['board']['elements']))
 record('正常退出会完成未结束的文字输入并落盘，重启后补同步')
 success=True
except Exception:
 for name in q.NAMES:
  if q.processes.get(name) and q.processes[name].poll() is None:
   try:
    (q.WORK/(name+'.failure.json')).write_text(json.dumps(q.state(name),ensure_ascii=False))
    q.command(name,'snapshot',name=name+'.failure.png')
   except Exception:pass
 raise
finally:
 evidence={'status':'passed' if success else 'failed','startedAt':started,'finishedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'apps':{n:hashlib.sha256((q.WORK/f'mmemo-{n}.app/Contents/Resources/web/board/board.js').read_bytes()).hexdigest() for n in q.NAMES},'checks':report}
 (q.ROOT/'docs/implementation/board-native-results.json').write_text(json.dumps(evidence,ensure_ascii=False,indent=2)+'\n')
 for name in q.NAMES:
  if q.processes.get(name) and q.processes[name].poll() is None:q.stop(name)
 if server and server.poll() is None:server.terminate();server.wait(timeout=10)
