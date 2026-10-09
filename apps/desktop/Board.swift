import AppKit
import WebKit
import UniformTypeIdentifiers

extension AppDelegate: NSWindowDelegate, WKUIDelegate {
    func makeBoard() {
        boardPanel = FloatingPanel(contentRect:NSRect(x:0,y:0,width:1040,height:740),styleMask:[.titled,.closable,.miniaturizable,.resizable,.nonactivatingPanel],backing:.buffered,defer:false)
        boardPanel.title="mmemo · 双人留言画板"
        boardPanel.isReleasedWhenClosed=false;boardPanel.hidesOnDeactivate=false
        boardPanel.level = .normal;boardPanel.collectionBehavior = [.fullScreenAuxiliary]
        boardPanel.minSize=NSSize(width:700,height:500);boardPanel.delegate=self
        boardPanel.setFrameAutosaveName("mmemo.board."+(account?.uid ?? "local"))
        if !boardPanel.setFrameUsingName("mmemo.board."+(account?.uid ?? "local")) {boardPanel.center()}
        let config=WKWebViewConfiguration();config.userContentController.add(self,name:"mmemo")
        boardWeb=WKWebView(frame:boardPanel.contentView!.bounds,configuration:config)
        boardWeb.autoresizingMask=[.width,.height];boardWeb.navigationDelegate=self;boardWeb.uiDelegate=self
        boardPanel.contentView=boardWeb
        boardWeb.loadFileURL(resources.appendingPathComponent("web/board/index.html"),allowingReadAccessTo:resources.appendingPathComponent("web/board"))
    }
    func webView(_ webView:WKWebView,runOpenPanelWith parameters:WKOpenPanelParameters,initiatedByFrame frame:WKFrameInfo,completionHandler:@escaping ([URL]?)->Void) {
        guard webView === boardWeb else {completionHandler(nil);return}
        #if MMEMO_BOARD_QA
        if let fixture=ProcessInfo.processInfo.environment["MMEMO_BOARD_QA_IMAGE"] {completionHandler([URL(fileURLWithPath:fixture)]);return}
        #endif
        let chooser=NSOpenPanel();chooser.allowedContentTypes=[.png,.jpeg,.gif,.webP,.svg]
        chooser.allowsMultipleSelection=parameters.allowsMultipleSelection;chooser.canChooseDirectories=false
        chooser.beginSheetModal(for:boardPanel){response in completionHandler(response == .OK ? chooser.urls : nil)}
    }
    @objc func showBoard() {
        guard account != nil, cloud != nil else {showAlert("画板需要双人账号","请先完成 mmemo 的账号配置。") ;return}
        if boardPanel.isMiniaturized {boardPanel.deminiaturize(nil)}
        if !NSScreen.screens.contains(where:{$0.visibleFrame.intersects(boardPanel.frame)}){boardPanel.center()}
        boardPanel.makeKeyAndOrderFront(nil);boardPanel.makeFirstResponder(boardWeb)
        boardCall("window.mmemoBoard.visibility(true)",args:[:])
    }
    func windowShouldClose(_ sender:NSWindow)->Bool {
        guard sender === boardPanel else {return true}
        boardCall("document.activeElement?.blur(); window.mmemoBoard.visibility(false)",args:[:]);boardPanel.orderOut(nil);return false
    }
    func windowDidMiniaturize(_ notification:Notification){if notification.object as? NSWindow === boardPanel {boardCall("window.mmemoBoard.visibility(false)",args:[:])}}
    func windowDidDeminiaturize(_ notification:Notification){if notification.object as? NSWindow === boardPanel {boardCall("window.mmemoBoard.visibility(true)",args:[:])}}
    func boardCall(_ script:String,args:[String:Any]) {
        guard boardReady else {return}
        boardWeb.callAsyncJavaScript(script,arguments:args,in:nil,in:.page){ result in
            if case .failure = result {NSLog("mmemo: board view message failed")}
        }
    }
    func startBoardRealtime(){
        guard boardReady,let cloud else {return}
        cloud.watchBoard(onMessage:{[weak self] message in self?.boardCall("window.mmemoBoard.receive(message)",args:["message":message])},onConnection:{[weak self] connected in self?.boardCall("window.mmemoBoard.connection(connected)",args:["connected":connected])})
    }
    func handleBoard(_ body:[String:Any]) {
        guard let action=body["action"] as? String else {return}
        switch action {
        case "boardReady":
            guard !boardReady else {return};boardReady=true
            let file=store.directory.appendingPathComponent("board-state.json")
            var saved:Any=NSNull()
            if FileManager.default.fileExists(atPath:file.path){
                do {
                    let data=try Data(contentsOf:file)
                    guard data.count<=80*1024*1024,let value=try JSONSerialization.jsonObject(with:data) as? [String:Any],value["version"] as? Int == 1,value["uid"] as? String == account?.uid else {throw AIError("Invalid board cache")}
                    saved=value
                }catch{
                    boardWeb.evaluateJavaScript("document.getElementById('root').textContent='画板本地数据无法读取，原文件已保留。请从菜单打开数据文件夹检查。'")
                    return
                }
            }
            boardCall("window.mmemoBoard.initialize(uid, saved, visible)",args:["uid":account?.uid ?? "local","saved":saved,"visible":boardPanel.isVisible])
            startBoardRealtime()
        case "boardPersist":
            guard let state=body["state"] as? [String:Any],let sequence=body["sequence"] as? Int,state["uid"] as? String == account?.uid,state["version"] as? Int == 1 else {return}
            do {
                try saveBoardState(state)
                boardCall("window.mmemoBoard.persisted(sequence)",args:["sequence":sequence])
            }catch {boardCall("window.mmemoBoard.persisted(sequence, message)",args:["sequence":sequence,"message":"Save failed"])}
        case "boardSend":
            guard let message=body["message"] as? [String:Any],let cloud else {return}
            Task { @MainActor in do {try await cloud.sendBoard(message)}catch {self.boardCall("window.mmemoBoard.connection(false)",args:[:])} }
        case "boardReconnect": startBoardRealtime()
        case "boardUnread":
            boardUnread=body["unread"] as? Bool ?? false
            call("window.mmemo.boardUnread(value)",args:["value":boardUnread])
        case "error": NSLog("mmemo board: %@",body["message"] as? String ?? "unknown")
        default:break
        }
    }
    func saveBoardState(_ state:[String:Any]) throws {
        let data=try JSONSerialization.data(withJSONObject:state)
        guard data.count<=80*1024*1024 else {throw AIError("Board cache too large")}
        try FileManager.default.createDirectory(at:store.directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let file=store.directory.appendingPathComponent("board-state.json")
        try data.write(to:file,options:[.atomic,.completeFileProtection])
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
    }
}
