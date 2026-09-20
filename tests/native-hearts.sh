#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
work=$(mktemp -d /tmp/mmemo-native-hearts.XXXXXX)
trap 'rm -rf "$work"' EXIT
python3 - "$work/main.swift" <<'PY'
import sys, uuid
from pathlib import Path
source=Path('desktop/main.swift').read_text().split('let app=NSApplication.shared')[0]
source=source.replace('"heartNotifications."', '"heartNotifications.test.'+uuid.uuid4().hex+'."')
source=source.replace('let resources = Bundle.main.resourceURL!.absoluteURL','let resources = URL(fileURLWithPath: CommandLine.arguments[1])')
source=source.replace('let username=Bundle.main.object(forInfoDictionaryKey:"MMemoAccount") as? String','let username=CommandLine.arguments[2]')
Path(sys.argv[1]).write_text(source+r'''
let app=NSApplication.shared
let delegate=AppDelegate()
app.delegate=delegate
var checking=false
Timer.scheduledTimer(withTimeInterval:50,repeats:false) {_ in print("FAIL: native cloud timeout");exit(1)}
Timer.scheduledTimer(withTimeInterval:0.1,repeats:true) { timer in
 guard delegate.cloudReady,delegate.readyWebs.count==2,delegate.heartsReady,!checking else {return}
 checking=true;timer.invalidate()
 Task { @MainActor in
   let username=delegate.account!.username
   let peerName=username=="user_pptg" ? "user_mm" : "user_pptg"
   let directory=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/mmemo/development/"+peerName)
   let peer=CloudClient(config:try CloudConfiguration.load(directory:directory),directory:directory)
   do {
     defer {UserDefaults.standard.removeObject(forKey:delegate.heartStateKey)}
     delegate.toggle();delegate.hide()
     assert(delegate.heartState.level()==0)
     let own=delegate.cloud!
     let initial=try await peer.fetchHearts()
     _ = try await delegate.web.evaluateJavaScript("document.getElementById('sendHeart').click()")
     var received:[String]=[]
     for _ in 0..<50 {
       received=try await peer.fetchHearts().filter {!initial.contains($0)}
       if !received.isEmpty {break}
       try await Task.sleep(nanoseconds:100_000_000)
     }
     assert(received.count==1,"header click sends one heart to peer")
     assert(delegate.heartState.level()==0,"sender must not preview locally")
     try await own.ackHearts(received)
     let protected=try await peer.fetchHearts()
     assert(received.allSatisfy {protected.contains($0)},"sender cannot acknowledge peer inbox")
     try await peer.ackHearts(received)
     try await peer.sendHeart()
     for _ in 0..<100 {
       if delegate.heartState.level()>0 {break}
       try await Task.sleep(nanoseconds:100_000_000)
     }
     assert(delegate.heartState.level()>0,"scheduled receiving plays hearts")
     let count=try await delegate.heartsWeb.evaluateJavaScript("document.querySelectorAll('.heart').length") as! Int
     assert(count>0,"received heart renders in native effect window")
     try await Task.sleep(nanoseconds:500_000_000)
     let remaining=try await own.fetchHearts()
     assert(remaining.isEmpty,"received hearts acknowledged")
     print("PASS: header send, recipient-only acknowledgment, scheduled receipt and rendered hearts")
     try await Task.sleep(nanoseconds:8_500_000_000)
     assert(delegate.heartState.level()==1,"notification persists past 8 seconds until viewed")
     try await peer.sendHeart()
     for _ in 0..<100 {
       if delegate.heartState.level()==2 {break}
       try await Task.sleep(nanoseconds:100_000_000)
     }
     assert(delegate.heartState.level()==2,"peer clicks manually raise notification level")
     delegate.heartState.startedAt=Date().addingTimeInterval(-240)
     delegate.refreshReminders()
     assert(delegate.heartState.level()==4,"unread time raises notification level")
     delegate.toggle()
     assert(delegate.heartState.level()==0,"avatar click clears notification")
     try await Task.sleep(nanoseconds:200_000_000)
     let cleared=try await delegate.heartsWeb.evaluateJavaScript("document.querySelectorAll('.heart').length") as! Int
     assert(cleared==0,"viewing clears rendered particles")
     try await delegate.receiveHearts();delegate.refreshReminders()
     assert(delegate.heartState.level()==0,"acknowledged hearts do not replay")
     print("PASS:",username,"persistent notification, manual/time levels, avatar reset, no replay")
     exit(0)
   } catch {
     print("FAIL:",error.localizedDescription,(error as NSError).userInfo);exit(1)
   }
 }
}
app.run()
''')
PY
swiftc desktop/Store.swift desktop/AI.swift desktop/Cloud.swift "$work/main.swift" -o "$work/native-cloud" -framework AppKit -framework WebKit
"$work/native-cloud" "$PWD/dist/mmemo.app/Contents/Resources" user_pptg
"$work/native-cloud" "$PWD/dist/mmemo.app/Contents/Resources" user_mm
