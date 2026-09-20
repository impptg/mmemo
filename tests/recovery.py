import sys,json,time,uuid,subprocess
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent))
import importlib.util
spec=importlib.util.spec_from_file_location('pair',Path(__file__).with_name('native-pair.py'));pair=importlib.util.module_from_spec(spec);spec.loader.exec_module(pair)
SSH=['ssh','-S','/tmp/mmemo-ecs-ssh-%r@%h:%p','root@59.110.153.116']
def remote(command):return subprocess.check_output(SSH+[command],text=True)
def metrics():
    return json.loads(remote("python3 - <<'PY'\nfrom pathlib import Path\nimport urllib.request\ne=dict(line.split('=',1) for line in Path('/opt/mmemo/server.env').read_text().splitlines())\nr=urllib.request.Request('http://127.0.0.1:8787/internal/metrics',headers={'x-mmemo-admin':e['ADMIN_TOKEN']})\nprint(urllib.request.urlopen(r).read().decode())\nPY"))
report=[]
import atexit
for name in pair.NAMES:pair.start(name)
def cleanup():
 for name,process in pair.processes.items():
  if process.poll() is None:pair.stop(name)
atexit.register(cleanup)
a,b=pair.NAMES
for name in pair.NAMES:pair.wait(name,lambda s:s['ready'])
original=pair.command(a,'status')['tasks']
for container in ['mmemo-server-1','mmemo-db-1']:
    remote('docker restart '+container)
    deadline=time.monotonic()+45
    while time.monotonic()<deadline:
        try:
            if metrics()['subscribers']==2:break
        except subprocess.CalledProcessError:pass
        time.sleep(1)
    else:raise AssertionError('Subscriptions failed to recover')
    id='recovery-'+str(uuid.uuid4())
    pair.apply(a,[{'action':'create','id':id,'patch':{'title':'重启恢复验收','due':'','done':False}}])
    pair.wait(b,lambda s:pair.has(s,id));pair.apply(a,[{'action':'delete','id':id}]);pair.wait(b,lambda s:not pair.has(s,id))
    report.append({'check':container+' restart: both subscriptions and subsequent writes recovered'})
# Expire actual server sessions, then reconnect; clients must renew their saved credentials.
remote("docker exec mmemo-db-1 psql -U mmemo -d mmemo -c \"UPDATE sessions SET expires_at=now()-interval '1 second';\"")
for name in pair.NAMES:pair.command(name,'wake')
deadline=time.monotonic()+20
while time.monotonic()<deadline:
    if metrics()['subscribers']==2 and all(pair.command(n,'status')['canWrite'] for n in pair.NAMES):break
    time.sleep(.3)
else:raise AssertionError('Session refresh failed')
report.append({'check':'Expired server access tokens: both apps reauthenticated and resubscribed'})
before=metrics();time.sleep(35);after=metrics()
assert before['todoReads']==after['todoReads'],(before,after)
assert before['heartReads']==after['heartReads'],(before,after)
assert after['subscribers']==2
report.append({'check':'Two live apps idle 35 seconds: no todo/heart reads; 2 SSE subscriptions','before':before,'after':after})
for name in pair.NAMES:assert pair.command(name,'status')['tasks']==original
(pair.ROOT/'docs/implementation/recovery-results.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report,indent=2))
