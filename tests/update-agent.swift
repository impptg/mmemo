// Compiled only into isolated update QA bundles, never shipped in Releases.
let qaDirectory=delegate.store.directory
try! FileManager.default.createDirectory(at:qaDirectory,withIntermediateDirectories:true)
var qaBusy=false
Timer.scheduledTimer(withTimeInterval:0.1,repeats:true) { _ in
    guard !qaBusy else {return}
    let input=qaDirectory.appendingPathComponent("command.json")
    guard let data=try? Data(contentsOf:input),let command=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any] else {return}
    try? FileManager.default.removeItem(at:input);qaBusy=true
    Task { @MainActor in
        var result:[String:Any]=["ok":true,"request":command["request"] ?? ""]
        do {
            switch command["action"] as? String {
            case "status":
                result["version"]=Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion")
                result["ready"]=delegate.loaded && delegate.draftRestored
                result["account"]=delegate.account?.username
                result["dataDirectory"]=qaDirectory.path
                result["feed"]=Bundle.main.object(forInfoDictionaryKey:"SUFeedURL")
                result["menu"]=delegate.status.menu!.items.map { ["title":$0.title,"enabled":$0.isEnabled] as [String:Any] }
                result["available"]=delegate.updates.availableVersion ?? ""
                result["busy"]=delegate.responding || delegate.sendingHeart
                result["pid"]=ProcessInfo.processInfo.processIdentifier
                if delegate.loaded {result["draft"]=try await delegate.web.evaluateJavaScript("window.mmemo.snapshotDraft()")}
            case "js":result["value"]=try await delegate.web.evaluateJavaScript(command["script"] as! String)
            case "check":delegate.updates.check()
            case "background":delegate.updates.controller?.updater.checkForUpdatesInBackground()
            case "busy":delegate.responding=command["value"] as! Bool
            case "show":delegate.showPanels()
            case "quit":DispatchQueue.main.async {NSApp.terminate(nil)}
            default:throw AIError("Unknown QA command")
            }
        } catch { result=["ok":false,"error":error.localizedDescription,"request":command["request"] ?? ""] }
        try! JSONSerialization.data(withJSONObject:result).write(to:qaDirectory.appendingPathComponent("result.json"),options:.atomic)
        qaBusy=false
    }
}
