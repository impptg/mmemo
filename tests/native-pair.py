"""Exercise two real AppDelegate + WebKit processes over the deployed HTTPS service."""
import json,os,time,uuid,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
WORK=ROOT/'artifacts/private/native-pair'
NAMES=['user_pptg','user_mm']
UIDS=['2100541450115510274','2100541456125558785']
processes={}
def start(name):
    env={**os.environ,'MMEMO_QA_DIRECTORY':str(WORK)}
    log=open(WORK/(name+'.log'),'a')
    processes[name]=subprocess.Popen([str(WORK/f'mmemo-qa-{name}.app/Contents/MacOS/mmemo'),'--show'],env=env,stdout=log,stderr=log)
def command(name,action,**data):
    p=WORK/(name+'.command.json');out=WORK/(name+'.result.json');request=str(uuid.uuid4())
    tmp=p.with_suffix('.tmp');tmp.write_text(json.dumps({'action':action,'request':request,**data}));tmp.replace(p)
    deadline=time.monotonic()+30
    while time.monotonic()<deadline:
        if out.exists():
            result=json.loads(out.read_text())
            if result.get('request')==request:
                assert result['ok'],result
                return result
        if processes.get(name) and processes[name].poll() is not None:raise RuntimeError(f'{name} terminated')
        time.sleep(.04)
    raise RuntimeError(f'{name}: {action} timeout')
def wait(name,predicate,seconds=15):
    deadline=time.monotonic()+seconds
    while time.monotonic()<deadline:
        state=command(name,'status')
        if predicate(state):return state
        time.sleep(.08)
    raise AssertionError(f'{name} condition timeout')
def has(state,id,**fields):
    return any(t['id']==id and all(t.get(k)==v for k,v in fields.items()) for t in state['tasks'])
def apply(name,changes):return command(name,'apply',changes=changes)
def js(name,script):return command(name,'js',script=script)
def stop(name):
    processes[name].terminate();processes[name].wait(timeout=10)
def run():
    report=[];ids=[]
    for name in NAMES:start(name)
    try:
        for name in NAMES:wait(name,lambda s:s['ready'])
        original=command(NAMES[0],'status')['tasks']
        assert original==command(NAMES[1],'status')['tasks']
        report.append({'check':'Both real apps loaded identical migrated snapshot','count':len(original)})
        for actor,peer in [NAMES,NAMES[::-1]]:
            id='native-pair-'+str(uuid.uuid4());ids.append(id)
            start_time=time.monotonic()
            apply(actor,[{'action':'create','id':id,'patch':{'title':'双实例实时同步验收','due':'','done':False,'participants':UIDS}}])
            peer_state=wait(peer,lambda s:has(s,id))
            latency=round((time.monotonic()-start_time)*1000)
            assert latency<2000,f'Sync too slow: {latency}ms'
            row=next(r for r in json.loads(peer_state['dom'])['rows'] if r['id']==id);assert row['avatars']==2
            js(actor,"document.getElementById('chatInput').textContent='保留中的草稿';true")
            js(peer,f"document.querySelector('[data-task-id=\"{id}\"] .state').click();true")
            wait(actor,lambda s:has(s,id,done=True))
            assert json.loads(command(actor,'status')['dom'])['draft']=='保留中的草稿'
            apply(peer,[{'action':'update','id':id,'patch':{'title':'对端修改已同步'}}]);wait(actor,lambda s:has(s,id,title='对端修改已同步'))
            apply(actor,[{'action':'delete','id':id}]);wait(peer,lambda s:not has(s,id));ids.remove(id)
            js(actor,"document.getElementById('chatInput').textContent='';true")
            report.append({'check':f'{actor} -> {peer}: create/update/delete, native checkbox, two avatars, draft preservation','latencyMs':latency})
        # Hearts through the actual buttons, including one sent with receiving app disconnected.
        for actor,peer in [NAMES,NAMES[::-1]]:
            before=set(command(peer,'status')['received'])
            js(actor,"document.getElementById('sendHeart').click();true")
            wait(peer,lambda s:len(set(s['received'])-before)==1)
            report.append({'check':f'{actor} -> {peer}: native heart button delivered once'})
        command(NAMES[1],'disconnect');before=set(command(NAMES[1],'status')['received'])
        id='native-offline-'+str(uuid.uuid4());ids.append(id)
        apply(NAMES[0],[{'action':'create','id':id,'patch':{'title':'离线期间创建的验收待办','due':'','done':False}}])
        js(NAMES[0],"document.getElementById('sendHeart').click();true")
        time.sleep(.5);assert not has(command(NAMES[1],'status'),id)
        command(NAMES[1],'reconnect')
        state=wait(NAMES[1],lambda s:has(s,id) and len(set(s['received'])-before)==1)
        received=set(state['received']);command(NAMES[1],'wake');wait(NAMES[1],lambda s:s['canWrite']);time.sleep(.6)
        assert set(command(NAMES[1],'status')['received'])==received
        report.append({'check':'Disconnected receiver catches up todo and durable heart; wake handler reconnect does not duplicate'})
        stop(NAMES[1]);start(NAMES[1]);wait(NAMES[1],lambda s:s['ready'] and has(s,id))
        report.append({'check':'App process restart preserves session and reloads state'})
        apply(NAMES[0],[{'action':'delete','id':id}]);ids.remove(id);wait(NAMES[1],lambda s:not has(s,id))
        # Real model call from the native composer's submit path.
        label='验收'+uuid.uuid4().hex[:8]
        prompt=f'新增一个我们两个人一起参与的待办，标题必须是“{label}”，不设置日期。只创建这一条。'
        js(NAMES[0],f"document.getElementById('chatInput').textContent={json.dumps(prompt)};document.getElementById('chatForm').requestSubmit();true")
        state=wait(NAMES[0],lambda s:any(t['title']==label for t in s['tasks']) and not s['responding'],90)
        task=next(t for t in state['tasks'] if t['title']==label);ids.append(task['id']);assert set(task['participants'])==set(UIDS)
        wait(NAMES[1],lambda s:has(s,task['id']))
        report.append({'check':'Real AI native composer creates shared todo; second real app receives it'})
        apply(NAMES[0],[{'action':'delete','id':task['id']}]);ids.remove(task['id']);wait(NAMES[1],lambda s:not has(s,task['id']))
        for name in NAMES:assert command(name,'status')['tasks']==original
        report.append({'check':'All QA todos removed; original migrated data unchanged'})
        (ROOT/'docs/implementation/native-pair-results.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
        print(json.dumps(report,ensure_ascii=False,indent=2),flush=True)
    finally:
        for id in ids:
            try:apply(NAMES[0],[{'action':'delete','id':id}])
            except Exception:pass
        for name,process in processes.items():
            if process.poll() is None:stop(name)
if __name__=='__main__':run()
