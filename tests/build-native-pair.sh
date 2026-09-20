#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
work="$PWD/artifacts/private/native-pair"
mkdir -p "$work"
chmod 700 "$work"
python3 - "$work/main.swift" <<'PY'
from pathlib import Path
import sys
s=Path('apps/desktop/main.swift').read_text()
s=s.replace('app.run()',Path('tests/native-pair-agent.swift').read_text()+'\napp.run()')
Path(sys.argv[1]).write_text(s)
PY
swiftc apps/desktop/Store.swift apps/desktop/AI.swift apps/desktop/Cloud.swift "$work/main.swift" -o "$work/mmemo" -framework AppKit -framework WebKit
python3 - "$work" <<'PY'
import sys,subprocess,plistlib,shutil
from pathlib import Path
work=Path(sys.argv[1])
for name in ['user_pptg','user_mm']:
 app=work/f'mmemo-qa-{name}.app'
 subprocess.run(['ditto',f'dist/mmemo-{name}.app',str(app)],check=True)
 shutil.copyfile(work/'mmemo',app/'Contents/MacOS/mmemo')
 p=app/'Contents/Info.plist';d=plistlib.loads(p.read_bytes());d['CFBundleIdentifier']='local.mmemo.qa.'+name.replace('_','-');p.write_bytes(plistlib.dumps(d))
 subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
PY
