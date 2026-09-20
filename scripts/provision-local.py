"""Provision private account configs from generated bootstrap; never print credentials."""
from pathlib import Path
import json,uuid,shutil,os
root=Path(__file__).resolve().parent.parent
source=json.loads((root/'.secrets/bootstrap.json').read_text())
base=Path.home()/'Library/Application Support/mmemo/development'
ai=base/'user_mm/ai.json'
for name,uid in [('user_pptg','2100541450115510274'),('user_mm','2100541456125558785')]:
    folder=base/name;folder.mkdir(parents=True,exist_ok=True);folder.chmod(0o700)
    p=folder/'server.json'
    data={'baseURL':'https://59.110.153.116','username':name,'password':source['passwords'][name],'uid':uid,'deviceId':str(uuid.uuid4())}
    if p.exists():data['deviceId']=json.loads(p.read_text())['deviceId']
    p.write_text(json.dumps(data,indent=2));p.chmod(0o600)
    if not (folder/'ai.json').exists() and ai.exists():shutil.copyfile(ai,folder/'ai.json');(folder/'ai.json').chmod(0o600)
print('Both private accounts provisioned')
