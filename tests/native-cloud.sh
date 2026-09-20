#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
work=$(mktemp -d /tmp/mmemo-native-cloud.XXXXXX)
trap 'rm -rf "$work"' EXIT
python3 - "$work/main.swift" <<'PY'
import sys
from pathlib import Path
source=Path('apps/desktop/main.swift').read_text().split('let app=NSApplication.shared')[0]
source=source.replace('let resources = Bundle.main.resourceURL!.absoluteURL','let resources = URL(fileURLWithPath: CommandLine.arguments[1])')
source=source.replace('let username=Bundle.main.object(forInfoDictionaryKey:"MMemoAccount") as? String','let username=CommandLine.arguments[2]')
Path(sys.argv[1]).write_text(source+r'''
let app=NSApplication.shared
let delegate=AppDelegate()
app.delegate=delegate
var checking=false
Timer.scheduledTimer(withTimeInterval:50,repeats:false) {_ in print("FAIL: native cloud timeout");exit(1)}
Timer.scheduledTimer(withTimeInterval:0.1,repeats:true) { timer in
 guard delegate.cloudReady,delegate.readyWebs.count==2,!checking else {return}
 checking=true;timer.invalidate()
 Task { @MainActor in
   let username=delegate.account!.username
   let peerName=username=="user_pptg" ? "user_mm" : "user_pptg"
   let directory=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/mmemo/development/"+peerName)
   let peer=CloudClient(config:try CloudConfiguration.load(directory:directory),directory:directory)
   let id="native-sync-"+UUID().uuidString
   do {
     try await peer.apply([["action":"create","id":id,"patch":["title":"真实双端勾选验证","due":"","done":false,"participants":CloudAccount.all.map(\.uid)]]])
     // Exercise the application's SSE subscription, not a direct UI load.
     for _ in 0..<80 {
       if (try? delegate.store.load().contains(where:{$0.id==id}))==true {break}
       try await Task.sleep(nanoseconds:100_000_000)
     }
     let cached=try delegate.store.load();assert(cached.contains(where:{$0.id==id}))
     let expected=peerName=="user_mm" ? "partner" : "me"
     let json=String(data:try JSONSerialization.data(withJSONObject:[id,expected,peerName]),encoding:.utf8)!
     let script="""
     (()=>{const [id,avatar,peer]=\(json);const row=[...document.querySelectorAll('.todo')].find(r=>r.dataset.taskId===id);
     if(!row || row.querySelectorAll('.avatar').length!==2 || !row.querySelector('.avatar.me').title.includes('user_pptg') || !row.querySelector('.avatar.partner').title.includes('user_mm'))throw Error('shared avatars');
     if(!document.getElementById('accountStatus').textContent.includes('已同步'))throw Error('not synced');
     document.getElementById('chatInput').textContent='保留草稿';row.querySelector('.state').click();return true})()
     """
     _ = try await delegate.web.evaluateJavaScript(script)
     var done=false
     for _ in 0..<30 {
       if try await peer.fetch().first(where:{$0.id==id})?.done==true {done=true;break}
       try await Task.sleep(nanoseconds:200_000_000)
     }
     assert(done,"native checkbox must reach peer through cloud")
     let draft=try await delegate.web.evaluateJavaScript("document.getElementById('chatInput').textContent") as? String
     assert(draft=="保留草稿")
     try await peer.apply([["action":"delete","id":id]])
     try await delegate.refreshCloud()
     print("PASS:",username,"native login, SSE sync, two participant avatars, either member checkbox cloud write, draft preserved, cleanup")
     exit(0)
   } catch {
     try? await peer.apply([["action":"delete","id":id]])
     print("FAIL:",error.localizedDescription,(error as NSError).userInfo);exit(1)
   }
 }
}
app.run()
''')
PY
swiftc apps/desktop/Store.swift apps/desktop/AI.swift apps/desktop/Cloud.swift "$work/main.swift" -o "$work/native-cloud" -framework AppKit -framework WebKit
"$work/native-cloud" "$PWD/dist/mmemo.app/Contents/Resources" user_pptg
"$work/native-cloud" "$PWD/dist/mmemo.app/Contents/Resources" user_mm
