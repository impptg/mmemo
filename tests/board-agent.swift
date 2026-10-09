// Compiled only into disposable MMEMO_BOARD_QA apps. Never included in release bundles.
let boardQA=URL(fileURLWithPath:ProcessInfo.processInfo.environment["MMEMO_BOARD_QA_DIRECTORY"]!)
let boardQAName=Bundle.main.object(forInfoDictionaryKey:"MMemoAccount") as! String
var boardQABusy=false
Timer.scheduledTimer(withTimeInterval:0.04,repeats:true){ _ in
    guard !boardQABusy else {return}
    let file=boardQA.appendingPathComponent(boardQAName+".command.json")
    guard let data=try? Data(contentsOf:file),let command=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any] else {return}
    try? FileManager.default.removeItem(at:file);boardQABusy=true
    Task { @MainActor in
        var result:[String:Any]=["ok":true,"request":command["request"] ?? ""]
        do {
            switch command["action"] as? String {
            case "status":
                result["ready"]=delegate.boardReady
                result["visible"]=delegate.boardPanel.isVisible
                result["frame"]=[delegate.boardPanel.frame.origin.x,delegate.boardPanel.frame.origin.y,delegate.boardPanel.frame.width,delegate.boardPanel.frame.height]
                result["unread"]=delegate.boardUnread
                if delegate.boardReady {result["board"]=try await delegate.boardWeb.evaluateJavaScript("JSON.stringify(window.mmemoBoard?.inspect())")}
            case "boardJS":result["value"]=try await delegate.boardWeb.evaluateJavaScript(command["script"] as! String)
            case "listJS":result["value"]=try await delegate.web.evaluateJavaScript(command["script"] as! String)
            case "show":delegate.showPanels()
            case "open":delegate.showBoard()
            case "close":delegate.boardPanel.performClose(nil)
            case "outside":delegate.hide()
            case "resize":delegate.boardPanel.setFrame(NSRect(x:70,y:100,width:980,height:700),display:true)
            case "disconnect":delegate.cloud?.stopBoardWatching();delegate.boardCall("window.mmemoBoard.connection(false)",args:[:])
            case "reconnect":delegate.startBoardRealtime()
            case "snapshot":
                let config=WKSnapshotConfiguration()
                let image=try await delegate.boardWeb.takeSnapshot(configuration:config)
                let rep=NSBitmapImageRep(data:image.tiffRepresentation!)!
                try rep.representation(using:.png,properties:[:])!.write(to:boardQA.appendingPathComponent(command["name"] as! String))
            case "draw":
                delegate.showBoard();NSApp.activate(ignoringOtherApps:true)
                // App activation completes on the next runloop. Otherwise the first
                // synthetic mouseDown is consumed merely focusing the other account.
                try await Task.sleep(nanoseconds:150_000_000)
                delegate.boardPanel.makeKeyAndOrderFront(nil)
                let frame=delegate.boardWeb.bounds;let points=(command["points"] as! [[Double]]).map{NSPoint(x:$0[0],y:Double(frame.height)-$0[1])}
                for (index,point) in points.enumerated(){
                    let kind:NSEvent.EventType=index==0 ? .leftMouseDown : (index==points.count-1 ? .leftMouseUp : .leftMouseDragged)
                    let event=NSEvent.mouseEvent(with:kind,location:point,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:delegate.boardPanel.windowNumber,context:nil,eventNumber:index,clickCount:1,pressure:index==points.count-1 ? 0 : 1)!
                    NSApp.sendEvent(event)
                    try await Task.sleep(nanoseconds:40_000_000)
                }
            case "quit":NSApp.terminate(nil)
            default:throw AIError("Unknown board QA command")
            }
        }catch{result=["ok":false,"request":command["request"] ?? "","error":error.localizedDescription]}
        try! JSONSerialization.data(withJSONObject:result).write(to:boardQA.appendingPathComponent(boardQAName+".result.json"),options:.atomic)
        boardQABusy=false
    }
}
