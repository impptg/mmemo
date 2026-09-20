// App-level test seam, compiled only into the disposable QA bundles.
// Commands use a private local directory; the release binary contains no test IPC.
let qaDirectory=URL(fileURLWithPath:ProcessInfo.processInfo.environment["MMEMO_QA_DIRECTORY"]!)
let qaName=Bundle.main.object(forInfoDictionaryKey:"MMemoAccount") as! String
var qaBusy=false
Timer.scheduledTimer(withTimeInterval:0.05,repeats:true) { _ in
    guard !qaBusy else {return}
    let commandURL=qaDirectory.appendingPathComponent(qaName+".command.json")
    guard let data=try? Data(contentsOf:commandURL),let command=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any] else {return}
    try? FileManager.default.removeItem(at:commandURL)
    qaBusy=true
    Task { @MainActor in
        var result:[String:Any]=["ok":true,"request":command["request"] ?? ""]
        do {
            switch command["action"] as? String {
            case "status":
                result["ready"]=delegate.cloudReady && delegate.loaded && delegate.heartsReady
                result["responding"]=delegate.responding
                result["canWrite"]=delegate.canWrite
                result["received"]=delegate.heartState.received
                result["latestReply"]=delegate.latestReply ?? ""
                result["tasks"]=try JSONSerialization.jsonObject(with:JSONEncoder().encode(delegate.store.load()))
                if delegate.loaded {result["dom"]=try await delegate.web.evaluateJavaScript("JSON.stringify({rows:[...document.querySelectorAll('.todo')].map(r=>({id:r.dataset.taskId,done:r.querySelector('.state').getAttribute('aria-checked'),avatars:r.querySelectorAll('.avatar').length})),draft:document.getElementById('chatInput').textContent,status:document.getElementById('accountStatus').textContent})")}
            case "apply":try await delegate.cloud!.apply(command["changes"] as! [[String:Any]])
            case "js":result["value"]=try await delegate.web.evaluateJavaScript(command["script"] as! String)
            case "disconnect":delegate.cloud?.stopWatching()
            case "reconnect":delegate.startRealtime()
            case "wake":delegate.systemWoke(Notification(name:NSWorkspace.didWakeNotification))
            case "show":delegate.showPanels()
            case "quit":NSApp.terminate(nil)
            default:throw AIError("Unknown QA command")
            }
        }catch{result=["ok":false,"error":error.localizedDescription,"request":command["request"] ?? ""]}
        let output=try! JSONSerialization.data(withJSONObject:result)
        try! output.write(to:qaDirectory.appendingPathComponent(qaName+".result.json"),options:.atomic)
        qaBusy=false
    }
}
