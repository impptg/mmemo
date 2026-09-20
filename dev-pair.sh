#!/bin/sh
set -eu
cd "$(dirname "$0")"
./run.sh --build
python3 - <<'PY'
import json,os,plistlib,shutil,subprocess,uuid
from pathlib import Path
root=Path.cwd()
base=Path.home()/'Library/Application Support/mmemo'
credentials=json.loads((base/'cloudbase-development-users.json').read_text())
identities={'user_pptg':'2100541450115510274','user_mm':'2100541456125558785'}
for user in credentials['users']:
    name=user['username']
    if name not in identities: continue
    folder=base/'development'/name
    folder.mkdir(parents=True,exist_ok=True,mode=0o700)
    os.chmod(folder,0o700)
    config_path=folder/'cloud.json'
    old=json.loads(config_path.read_text()) if config_path.exists() else {}
    config={**user,'envId':credentials['envId'],'uid':identities[name],'deviceId':old.get('deviceId',str(uuid.uuid4()))}
    fd=os.open(config_path,os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600)
    with os.fdopen(fd,'w') as f: json.dump(config,f,indent=2)
    os.chmod(config_path,0o600)
    if not (folder/'ai.json').exists() and (base/'ai.json').exists():
        shutil.copyfile(base/'ai.json',folder/'ai.json');os.chmod(folder/'ai.json',0o600)
    app=root/'dist'/f'mmemo-{name}.app'
    subprocess.run(['ditto',str(root/'dist/mmemo.app'),str(app)],check=True)
    plist=app/'Contents/Info.plist'
    with plist.open('rb') as f: data=plistlib.load(f)
    data.update(CFBundleIdentifier='local.mmemo.desktop.'+name.replace('_','-'),CFBundleName='mmemo '+name,MMemoAccount=name)
    with plist.open('wb') as f:plistlib.dump(data,f)
    subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
    print('Prepared',name,'(independent credentials/cache/preferences)')
PY
if [ "${1:-}" != "--prepare" ]; then
  open "$PWD/dist/mmemo-user_pptg.app" --args --show
  open "$PWD/dist/mmemo-user_mm.app" --args --show
fi
