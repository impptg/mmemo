#!/bin/sh
set -eu
cd "$(dirname "$0")"
app="$PWD/dist/mmemo.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/web/assets"
MACOSX_DEPLOYMENT_TARGET=13.0 swiftc -O desktop/Store.swift desktop/AI.swift desktop/Cloud.swift desktop/main.swift -o "$app/Contents/MacOS/mmemo" -framework AppKit -framework WebKit
cp desktop/web/* "$app/Contents/Resources/web/"
cp design/assets/avatar-pair-love-white.png design/assets/avatar-raccoon.png design/assets/raccoon-edge-blink-ui.apng design/assets/pp-edge-assistant-blink.apng "$app/Contents/Resources/web/assets/"
swift desktop/icons.swift "$app/Contents/Resources/web/icons"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>mmemo</string>
<key>CFBundleIdentifier</key><string>local.mmemo.desktop</string>
<key>CFBundleName</key><string>mmemo</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app"
if [ "${1:-}" != "--build" ]; then open "$app"; fi
