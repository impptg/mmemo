"""Build independent app bundles from already-provisioned private account configs."""
import plistlib, subprocess
from pathlib import Path
root=Path(__file__).resolve().parent.parent
base=Path.home()/'Library/Application Support/mmemo/development'
for name in ['user_pptg','user_mm']:
    if not (base/name/'server.json').exists():
        raise SystemExit(f'Missing private server.json for {name}; provision accounts first')
    app=root/'dist'/f'mmemo-{name}.app'
    subprocess.run(['ditto',str(root/'dist/mmemo.app'),str(app)],check=True)
    path=app/'Contents/Info.plist'
    data=plistlib.loads(path.read_bytes())
    data.update(CFBundleIdentifier='local.mmemo.desktop.'+name.replace('_','-'),CFBundleName='mmemo '+name,MMemoAccount=name)
    path.write_bytes(plistlib.dumps(data))
    subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
    print('Prepared',name)
