#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
work=$(mktemp -d /tmp/mmemo-checkbox.XXXXXX)
trap 'rm -rf "$work"' EXIT
python3 - "$work/main.swift" <<'PY'
import sys
source=open('apps/desktop/main.swift').read().split('let app=NSApplication.shared')[0]
source=source.replace('let resources = Bundle.main.resourceURL!.absoluteURL', 'let resources = URL(fileURLWithPath: CommandLine.arguments[1])')

source=source.replace('store = TaskStore(directory: base.appendingPathComponent("mmemo"))', 'store = TaskStore(directory: URL(fileURLWithPath: CommandLine.arguments[2]))')
open(sys.argv[1],'w').write(source + r'''
let app=NSApplication.shared
let delegate=AppDelegate()
app.delegate=delegate
try delegate.store.save([Todo(id:"checkbox-test",title:"勾选验证",due:"",done:false)])
Timer.scheduledTimer(withTimeInterval:15,repeats:false) { _ in print("FAIL: checkbox bridge timeout", delegate.readyWebs.count, delegate.loaded, "phase", phase);exit(1) }

var phase=0
var checking=false
Timer.scheduledTimer(withTimeInterval:0.1,repeats:true) { timer in
    guard delegate.readyWebs.count == 2, !checking else { return }
    guard let saved=try? delegate.store.load(), let task=saved.first else { return }
    if phase==1 && !task.done { return }
    if phase==2 && task.done { return }
    checking=true
    let script: String
    switch phase {
    case 0:
        delegate.showPanels()
        script="""
        (()=>{const c=document.querySelector('.todo[data-task-id="checkbox-test"] .state');if(!c)return false;
        const input=document.getElementById('chatInput');input.textContent='保留这份草稿';input.dispatchEvent(new Event('input'));c.click();return true;})()
        """
    case 1:
        script="""
        (()=>{const c=document.querySelector('.todo[data-task-id="checkbox-test"] .state');if(!c || c.getAttribute('aria-checked')!=='true')return false;
        if(!c.closest('.completed-group'))throw Error('Completed group missing');document.querySelector('.completed-group').open=true;c.click();return true;})()
        """
    default:
        script="""
        (()=>{const c=document.querySelector('.todo[data-task-id="checkbox-test"] .state');if(!c || c.getAttribute('aria-checked')!=='false')return false;
        const input=document.getElementById('chatInput');if(c.closest('.completed-group') || input.textContent!=='保留这份草稿' || input.querySelector('.task-token'))throw Error('Group or draft changed incorrectly');return true;})()
        """
    }
    delegate.web.evaluateJavaScript(script) { value,error in
        checking=false
        if let error { print("FAIL:",error);exit(1) }
        guard value as? Bool == true else { return }
        if phase<2 { phase += 1; return }
        do {
            let backup=try JSONDecoder().decode([Todo].self,from:Data(contentsOf:delegate.store.directory.appendingPathComponent("todos.backup.json")))
            assert(backup.count==1 && backup[0].done==true)
            print("PASS: real checkbox clicks cross native allowlist, save completed/reopened states, update groups and preserve draft")
            exit(0)
        } catch { print("FAIL:",error);exit(1) }
    }
}
app.run()
''')
PY
swiftc apps/desktop/Store.swift apps/desktop/AI.swift apps/desktop/Cloud.swift "$work/main.swift" -o "$work/mmemo-checkbox-check" -framework AppKit -framework WebKit
"$work/mmemo-checkbox-check" "$PWD/dist/mmemo.app/Contents/Resources" "$work/data"
