"""Two real macOS app processes over an isolated local board QA backend."""
import json,os,time,uuid,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
WORK=ROOT/'artifacts/private/board-qa'
NAMES=['user_pptg','user_mm']
processes={}
def start(name,native_picker=False):
 env={**os.environ,'MMEMO_BOARD_QA_DIRECTORY':str(WORK),'MMEMO_BOARD_QA_ACCOUNTS':str(WORK/'accounts'),'MMEMO_BOARD_QA_IMAGE':str(WORK/'fixture.png')}
 if native_picker:env.pop('MMEMO_BOARD_QA_IMAGE',None)
 log=open(WORK/(name+'.log'),'a')
 process=subprocess.Popen([str(WORK/f'mmemo-{name}.app/Contents/MacOS/mmemo'),'--show'],env=env,stdout=log,stderr=log)
 processes[name]=process;(WORK/(name+'.pid')).write_text(str(process.pid));return process

def command(account,action,**data):
 name=account
 p=WORK/(name+'.command.json');out=WORK/(name+'.result.json');request=str(uuid.uuid4())
 tmp=p.with_suffix('.tmp');tmp.write_text(json.dumps({'action':action,'request':request,**data}));tmp.replace(p)
 deadline=time.monotonic()+30
 while time.monotonic()<deadline:
  if out.exists():
   result=json.loads(out.read_text())
   if result.get('request')==request:
    assert result['ok'],result
    return result
  if processes.get(name) and processes[name].poll() is not None:
   if action=='quit' and processes[name].returncode==0:return {'ok':True,'terminated':True}
   raise RuntimeError(f'{name} terminated: {processes[name].returncode}')
  time.sleep(.04)
 raise RuntimeError(f'{name}: {action} timeout')

def state(name):
 result=command(name,'status');result['board']=json.loads(result.get('board','{}'));return result

def wait(name,predicate,seconds=20):
 end=time.monotonic()+seconds
 while time.monotonic()<end:
  s=state(name)
  if predicate(s):return s
  time.sleep(.08)
 raise AssertionError(f'{name} condition timeout: '+json.dumps({k:v for k,v in s.items() if k!='board'},ensure_ascii=False)+' '+json.dumps({k:v for k,v in s.get('board',{}).items() if k not in ['elements','files']},ensure_ascii=False))

def js(name,script):return command(name,'boardJS',script=script)

def stop(name):
 process=processes.get(name)
 if process:process.terminate();process.wait(timeout=10)
 else:os.kill(int((WORK/(name+'.pid')).read_text()),15)

if __name__=='__main__':
 for name in NAMES:start(name)
 for name in NAMES:
  s=wait(name,lambda s:s['board'].get('online'))
  print(name,json.dumps(s,ensure_ascii=False),flush=True)
 print('Two real QA apps ready.',flush=True)
 try:
  while True:time.sleep(1)
 finally:
  for name in NAMES:stop(name)
