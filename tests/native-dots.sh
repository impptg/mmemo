#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
work=$(mktemp -d /tmp/mmemo-dot-layout.XXXXXX)
python3 - "$work/main.swift" <<'PY'
import sys
source=open('apps/desktop/main.swift').read().split('let app=NSApplication.shared')[0]
source=source.replace('let resources = Bundle.main.resourceURL!.absoluteURL','let resources = URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("dist/mmemo.app/Contents/Resources")')
open(sys.argv[1],'w').write(source+open('tests/native-dots.swift').read())
PY
swiftc apps/desktop/Store.swift apps/desktop/AI.swift apps/desktop/Cloud.swift "$work/main.swift" -o "$work/check" -framework AppKit -framework WebKit
"$work/check"
