"""Run HTTP/WS/client regression checks without native apps consuming shared events."""
import os,subprocess,time,urllib.request
from pathlib import Path
from urllib.parse import urlsplit
ROOT=Path(__file__).resolve().parent.parent
work=ROOT/'artifacts/private/board-qa'
database=os.environ.get('BOARD_QA_DATABASE_URL','postgres://mmemo:local-testing-only@127.0.0.1:55432/mmemo_board_qa')
u=urlsplit(database)
if u.hostname not in ['127.0.0.1','localhost'] or u.path!='/mmemo_board_qa':raise RuntimeError('Service checks require localhost mmemo_board_qa')
for name in ['user_pptg','user_mm']:
 path=work/(name+'.pid')
 if path.exists():
  try:os.kill(int(path.read_text()),0)
  except ProcessLookupError:pass
  else:raise RuntimeError('Stop the disposable board QA apps before service checks')
env={**os.environ,'DATABASE_URL':database,'PORT':'18788','ADMIN_TOKEN':'board-qa','LOG_LEVEL':'warn','TEST_BASE_URL':'http://127.0.0.1:18788','BOOTSTRAP_CONFIG':str(work/'bootstrap.json'),'TEST_PEER_BASE_URL':'http://127.0.0.1:18789'}
with open(work/'service-checks.log','w') as log:
 server=subprocess.Popen(['node','apps/server/dist/index.js'],cwd=ROOT,env=env,stdout=log,stderr=log)
 peer=subprocess.Popen(['node','apps/server/dist/index.js'],cwd=ROOT,env={**env,'PORT':'18789'},stdout=log,stderr=log)
 try:
  for attempt in range(100):
   if server.poll() is not None:raise RuntimeError('QA backend exited before health check')
   try:
    with urllib.request.urlopen('http://127.0.0.1:18788/health') as response:
     if response.status==200:break
   except Exception:time.sleep(.1)
  else:raise RuntimeError('QA backend health timeout')
  with urllib.request.urlopen(env['TEST_PEER_BASE_URL']+'/health') as response:assert response.status==200
  subprocess.run(['pnpm','test'],cwd=ROOT,env=env,check=True)
 finally:
  for process in [server,peer]:process.terminate()
  for process in [server,peer]:process.wait(timeout=10)
