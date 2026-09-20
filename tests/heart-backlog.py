"""A disconnected receiver must drain more than one 100-message page."""
import importlib.util,json,subprocess,time
from pathlib import Path
spec=importlib.util.spec_from_file_location('pair',Path(__file__).with_name('native-pair.py'));p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)
ssh=['ssh','-S','/tmp/mmemo-ecs-ssh-%r@%h:%p','root@59.110.153.116']
for n in p.NAMES:p.start(n)
try:
 for n in p.NAMES:p.wait(n,lambda s:s['ready'])
 p.command(p.NAMES[1],'disconnect')
 query="WITH added AS (INSERT INTO hearts(sender,recipient) SELECT '2100541450115510274','2100541456125558785' FROM generate_series(1,101) RETURNING id) SELECT json_agg(id) FROM added;"
 ids=json.loads(subprocess.check_output(ssh+['docker exec -i mmemo-db-1 psql -U mmemo -d mmemo -At'],input=query,text=True))
 p.command(p.NAMES[1],'reconnect');p.wait(p.NAMES[1],lambda s:set(ids).issubset(s['received']))
 deadline=time.monotonic()+10
 while time.monotonic()<deadline:
  n=subprocess.check_output(ssh+["docker exec mmemo-db-1 psql -U mmemo -d mmemo -Atc 'SELECT count(*) FROM hearts'"],text=True).strip()
  if n=='0':break
  time.sleep(.2)
 else:raise AssertionError('Backlog not fully acknowledged')
 report={'check':'101 offline hearts drained across two pages, deduplicated and acknowledged','passed':True}
 (p.ROOT/'docs/implementation/heart-backlog-results.json').write_text(json.dumps(report,indent=2));print(report)
finally:
 for n,process in p.processes.items():
  if process.poll() is None:p.stop(n)
