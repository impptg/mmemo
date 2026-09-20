import AppKit
import WebKit

final class FloatingPanel: NSPanel {
    var acceptsKeyboard = true
    override var canBecomeKey: Bool { acceptsKeyboard }
    override var canBecomeMain: Bool { false }
}

final class FrogHandle: NSView {
    var toggle: (() -> Void)?
    var moved: (() -> Void)?
    var start = NSPoint.zero
    var origin = NSPoint.zero
    var dragged = false
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func accessibilityPerformPress() -> Bool { toggle?(); return true }
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(point) ? self : nil }
    override func mouseDown(with event: NSEvent) {
        start = window!.convertPoint(toScreen: event.locationInWindow); origin = window!.frame.origin; dragged = false
    }
    override func mouseDragged(with event: NSEvent) {
        let now = window!.convertPoint(toScreen: event.locationInWindow)
        if hypot(now.x-start.x, now.y-start.y) > 4 { dragged = true }
        if dragged { window?.setFrameOrigin(NSPoint(x: origin.x + now.x-start.x, y: origin.y + now.y-start.y)) }
    }
    override func mouseUp(with event: NSEvent) {
        if dragged { moved?() } else { toggle?() }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 49 { toggle?() } else { super.keyDown(with: event) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate {
    var frog: FloatingPanel!
    var panel: FloatingPanel!
    var web: WKWebView!
    var bubblePanel: FloatingPanel!
    var bubbleWeb: WKWebView!
    var readyWebs: [WKWebView] = []
    var latestReply: String?
    var bubbleTimer: Timer?
    var bubblePhrase = ""
    var phraseIndex = 0
    var bubbleHovered = false
    var bubbleDeadline: Date?
    var bubbleRemaining: TimeInterval = 6
    let thinkingPhrases = ["有点晕碳 ...", "小脑袋转转转 ...", "正在冥思苦想 ..."]
    var status: NSStatusItem!
    var monitors: [Any] = []
    var heartsPanel: FloatingPanel!
    var heartsWeb: WKWebView!
    var sendingHeart = false
    var heartsReady = false
    var heartState = HeartNotificationState()
    var heartStateKey: String { "heartNotifications."+(account?.uid ?? "local") }
    var loaded = false
    var canWrite = false
    var responding = false
    var responseTask: Task<Void, Never>?
    var history: [[String: String]] = []
    let store: TaskStore
    let account: CloudAccount?
    var cloud: CloudClient?
    var syncing = false
    var cloudGeneration = 0
    var syncPending = false
    var syncRetry: Task<Void,Never>?
    var cloudReady = false
    var loginStarted = false
    let resources = Bundle.main.resourceURL!.absoluteURL

    override init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let username=Bundle.main.object(forInfoDictionaryKey:"MMemoAccount") as? String
        account=CloudAccount.all.first { $0.username==username }
        if let account {store=TaskStore(directory:base.appendingPathComponent("mmemo/development/\(account.username)"))}
        else {store = TaskStore(directory: base.appendingPathComponent("mmemo"))}
        super.init()
        if let data=UserDefaults.standard.data(forKey:heartStateKey), let saved=try? JSONDecoder().decode(HeartNotificationState.self,from:data) {heartState=saved}
        else {heartState.dueSeen=UserDefaults.standard.dictionary(forKey:"readReminders") as? [String:String] ?? [:]}
    }

    func floating(_ size: NSSize) -> FloatingPanel {
        let result = FloatingPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        result.isOpaque = false; result.backgroundColor = .clear
        result.level = .floating; result.hidesOnDeactivate = false
        result.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        result.isReleasedWhenClosed = false
        return result
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildMenu()
        if account != nil {
            do {cloud=CloudClient(config:try CloudConfiguration.load(directory:store.directory),directory:store.directory)}
            catch {showAlert("账号配置错误",error.localizedDescription)}
        }
        frog = floating(NSSize(width: account?.avatar == "raccoon" ? 48 : 44, height: 88)); frog.hasShadow = false; frog.title = "mmemo · \(account?.username ?? "本机")"
        frog.acceptsKeyboard = false
        let host = NSView(frame: NSRect(origin: .zero, size: frog.frame.size))
        let sprite = WKWebView(frame: host.bounds)
        sprite.setValue(false, forKey: "drawsBackground")
        if account?.avatar=="raccoon" {
            sprite.loadHTMLString("<html><body style='margin:0;background:transparent;overflow:hidden'><img alt='user_mm 小浣熊' src='assets/raccoon-edge-blink-ui.apng' style='position:absolute;width:72px;height:72px;top:8px;left:-24px'></body></html>",baseURL:resources.appendingPathComponent("web"))
        } else {
        sprite.loadHTMLString("<html><body style='margin:0;background:transparent;overflow:hidden'><img alt='青蛙' src='assets/pp-edge-assistant-blink.apng' style='position:absolute;width:88px;height:88px;left:-44px;top:0'></body></html>", baseURL: resources.appendingPathComponent("web"))
        }
        host.addSubview(sprite)
        let handle = FrogHandle(frame: host.bounds)
        handle.setAccessibilityElement(true); handle.setAccessibilityRole(.button)
        handle.setAccessibilityLabel("展开或收起待办面板")
        handle.toolTip = "mmemo · \(account?.username ?? "本机") · 点击打开待办，上下拖动移动"
        handle.toggle = { [weak self] in self?.toggle() }
        handle.moved = { [weak self] in self?.dock(afterDrag: true) }
        host.addSubview(handle)
        frog.contentView = host
        heartsPanel = floating(NSSize(width: 100, height: 150))
        heartsPanel.hasShadow = false; heartsPanel.acceptsKeyboard = false; heartsPanel.ignoresMouseEvents = true
        heartsWeb = WKWebView(frame: NSRect(x: 0, y: 0, width: 100, height: 150))
        heartsWeb.setValue(false, forKey: "drawsBackground"); heartsWeb.navigationDelegate = self
        heartsPanel.contentView = heartsWeb
        heartsWeb.loadFileURL(resources.appendingPathComponent("web/hearts.html"), allowingReadAccessTo: resources.appendingPathComponent("web"))
        frog.addChildWindow(heartsPanel, ordered: .above)
        (panel, web) = makeSurface("list", size: NSSize(width: 392, height: 410), title: "mmemo 待办清单")
        (bubblePanel, bubbleWeb) = makeSurface("bubble", size: NSSize(width: 260, height: 64), title: "mmemo 最新回复")
        dock(afterDrag: false); frog.orderFrontRegardless()
        if CommandLine.arguments.contains("--show") { if account != nil {showPanels()} else {reveal()} }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in self?.hide() }) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            guard let self else { return event }
            if event.window !== self.frog && event.window !== self.panel && event.window !== self.bubblePanel { self.hide() }
            return event
        }) { monitors.append(monitor) }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector:#selector(systemWoke(_:)),name:NSWorkspace.didWakeNotification,object:nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self, self.loaded else { return }
            self.refreshReminders()
            if self.cloud == nil {self.web.evaluateJavaScript("window.mmemo.opened()", completionHandler: nil)}
        }
    }

    func makeSurface(_ role: String, size: NSSize, title: String) -> (FloatingPanel, WKWebView) {
        let window = floating(size); window.title = title; window.hasShadow = true
        window.appearance = NSAppearance(named: .aqua)
        let content = NSView(frame: NSRect(origin: .zero, size: size))
        let glass = NSVisualEffectView(frame: content.bounds.insetBy(dx: 8, dy: 8))
        glass.autoresizingMask = [.width, .height]
        // Codex desktop uses macOS menu vibrancy behind its transparent web surface.
        glass.material = .menu; glass.blendingMode = .behindWindow; glass.state = .active
        glass.wantsLayer = true; glass.layer?.cornerRadius = role == "list" ? 18 : 24; glass.layer?.masksToBounds = true
        let config = WKWebViewConfiguration(); config.userContentController.add(self, name: "mmemo")
        let view = WKWebView(frame: glass.frame, configuration: config)
        view.focusRingType = .none
        view.autoresizingMask = [.width, .height]; view.setValue(false, forKey: "drawsBackground"); view.navigationDelegate = self
        if role == "list" { content.addSubview(glass) }
        content.addSubview(view); window.contentView = content
        var url = URLComponents(url: resources.appendingPathComponent("web/index.html"), resolvingAgainstBaseURL: false)!
        url.fragment = role
        view.loadFileURL(url.url!, allowingReadAccessTo: resources.appendingPathComponent("web"))
        return (window, view)
    }

    func dock(afterDrag: Bool) {
        let prefs = UserDefaults.standard
        let screen: NSScreen
        if afterDrag { screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: frog.frame.midX, y: frog.frame.midY)) } ?? frog.screen ?? NSScreen.main! }
        else { screen = NSScreen.screens.first { $0.localizedName == prefs.string(forKey: "screen") } ?? NSScreen.main! }
        let frame = screen.visibleFrame
        let fraction = prefs.object(forKey: "heightFraction") as? Double ?? (account?.avatar=="raccoon" ? 0.45 : (account == nil ? 0.65 : 0.95))
        let proposed = afterDrag ? frog.frame.minY : frame.minY + (frame.height - 88) * fraction
        let y = min(max(proposed, frame.minY + 4), frame.maxY - 92)
        frog.setFrameOrigin(NSPoint(x: frame.maxX - frog.frame.width, y: y))
        prefs.set((y-frame.minY)/max(frame.height-88,1), forKey: "heightFraction")
        prefs.set(screen.localizedName, forKey: "screen")
        positionPanel()
    }

    func positionPanel() {
        let screen = (frog.screen ?? NSScreen.main!).visibleFrame
        let width = min(392, screen.width-64)
        let height = min(410, max(160, screen.height-110))
        let x = max(screen.minX+8, frog.frame.minX-width+28)
        // Keep the speech bubble beside the frog; move the list above when space below runs out.
        let below = frog.frame.minY-height+28
        let y = below >= screen.minY+12 ? below : min(frog.frame.maxY-28, screen.maxY-height-12)
        heartsPanel.setFrameOrigin(NSPoint(x: frog.frame.maxX - 100, y: min(frog.frame.maxY - 30, screen.maxY - 150)))
        panel.setFrame(NSRect(x:x,y:y,width:width,height:height),display:true)
        let hasDots = bubblePhrase.hasSuffix("...")
        let prefix = hasDots ? String(bubblePhrase.dropLast(3)) : bubblePhrase
        let prefixWidth = (prefix as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width
        let dotsWidth = hasDots ? ("..." as NSString).size(withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)]).width : 0
        let textWidth = ceil(prefixWidth + dotsWidth)
        let bubbleWidth = min(textWidth + 60, max(60, frog.frame.minX-screen.minX-8))
        bubblePanel.setFrame(NSRect(x:frog.frame.minX-bubbleWidth,y:frog.frame.minY+20,width:bubbleWidth,height:60),display:true)
    }
    func reveal() {
        guard panel != nil, bubblePanel != nil else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main!
        let frame = screen.visibleFrame
        if account == nil {frog.setFrameOrigin(NSPoint(x: frame.maxX-44, y: frame.midY-44))}
        dock(afterDrag: true)
        frog.orderFrontRegardless()
        showPanels()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        reveal(); return true
    }
    @objc func screenChanged() { dock(afterDrag: false) }
    @objc func toggle() {
        refreshReminders()
        heartState.viewed(); renderHearts()
        if panel.isVisible { hide() } else {
            showPanels()
            if loaded { if cloud != nil {syncCloud(force:true)} else {web.evaluateJavaScript("window.mmemo.opened()", completionHandler:nil)} }
        }
    }
    func showPanels() {
        positionPanel(); NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(web)
    }
    @objc func hide() { panel.orderOut(nil) }

    @objc func quit() { NSApp.terminate(nil) }
    @objc func showData() {
        do { try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true); NSWorkspace.shared.open(store.directory) }
        catch { showAlert("无法打开数据目录", error.localizedDescription) }
    }
    func showAlert(_ title: String, _ message: String) {
        let alert = NSAlert(); alert.messageText=title; alert.informativeText=message; alert.runModal()
    }
    func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出 mmemo", action: #selector(quit), keyEquivalent: "q").target=self
        appItem.submenu=appMenu;main.addItem(appItem)
        let editItem = NSMenuItem(); editItem.title="编辑"; let edit=NSMenu(title:"编辑")
        for (title, selector, key) in [("撤销","undo:","z"),("剪切","cut:","x"),("复制","copy:","c"),("粘贴","paste:","v"),("全选","selectAll:","a")] {edit.addItem(withTitle:title, action:Selector(selector),keyEquivalent:key)}
        editItem.submenu=edit;main.addItem(editItem);NSApp.mainMenu=main
        status=NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        status.button?.image=NSImage(systemSymbolName:"checkmark.circle",accessibilityDescription:"mmemo")
        status.button?.toolTip="mmemo · \(account?.username ?? "本机")"
        if let account {status.button?.image=NSImage(systemSymbolName:account.avatar=="frog" ? "person.crop.circle" : "person.crop.circle.fill",accessibilityDescription:account.username)}
        let menu=NSMenu()
        if let account {menu.addItem(withTitle:account.username,action:nil,keyEquivalent:"")}
        menu.addItem(withTitle:"展开 / 收起待办",action:#selector(toggle),keyEquivalent:"").target=self
        menu.addItem(withTitle:"打开本地数据文件夹",action:#selector(showData),keyEquivalent:"").target=self
        menu.addItem(.separator())
        menu.addItem(withTitle:"退出 mmemo",action:#selector(quit),keyEquivalent:"q").target=self
        status.menu=menu
    }
    func updateBubble(_ text: String) {
        bubblePhrase = text
        positionPanel()
        call("window.mmemo.status(text)", args:["text":text])
    }
    func startBubble() {
        bubbleTimer?.invalidate(); bubbleDeadline=nil; phraseIndex=0
        latestReply = "正在处理你的请求，回复会显示在这里。"
        call("window.mmemo.latest(text)", args:["text":latestReply!])
        updateBubble(thinkingPhrases[0]); positionPanel(); frog.addChildWindow(bubblePanel, ordered: .below); bubblePanel.orderFrontRegardless(); frog.orderFrontRegardless()
        bubbleTimer = Timer.scheduledTimer(withTimeInterval:5,repeats:true) { [weak self] _ in
            guard let self else { return }
            self.phraseIndex = (self.phraseIndex+1) % self.thinkingPhrases.count
            self.updateBubble(self.thinkingPhrases[self.phraseIndex])
        }
    }
    func finishBubble(_ text: String) {
        bubbleTimer?.invalidate(); bubbleDeadline=nil; bubbleRemaining=6
        updateBubble(text); positionPanel(); frog.addChildWindow(bubblePanel, ordered: .below); bubblePanel.orderFrontRegardless(); frog.orderFrontRegardless()
        if !bubbleHovered { scheduleBubbleHide() }
    }
    func scheduleBubbleHide() {
        bubbleDeadline = Date().addingTimeInterval(bubbleRemaining)
        bubbleTimer = Timer.scheduledTimer(withTimeInterval:max(0.05,bubbleRemaining),repeats:false) { [weak self] _ in
            guard let self else { return }
            self.frog.removeChildWindow(self.bubblePanel)
            self.bubblePanel.orderOut(nil); self.bubbleDeadline=nil; self.bubbleTimer=nil
        }
    }
    func hoverBubble(_ hovered: Bool) {
        guard hovered != bubbleHovered else { return }
        bubbleHovered=hovered
        guard !responding else { return }
        if hovered, let deadline=bubbleDeadline {
            bubbleRemaining=max(0,deadline.timeIntervalSinceNow); bubbleTimer?.invalidate(); bubbleDeadline=nil
        } else if !hovered && bubblePanel.isVisible { scheduleBubbleHide() }
    }
    func call(_ script: String, args: [String:Any]) {
        for view in readyWebs {
            view.callAsyncJavaScript(script, arguments:args,in:nil,in:.page) { result in
                if case .failure(let error)=result { NSLog("mmemo web: %@",error.localizedDescription) }
            }
        }
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let sender = message.webView, [web, bubbleWeb].contains(where: { $0 === sender }),
              let body=message.body as? [String:Any], let action=body["action"] as? String else { return }
        let allowed: Set<String> = sender === bubbleWeb ? ["ready", "showLatest", "bubbleHover", "error"] : ["ready", "chat", "setDone", "stop", "inputError", "hide", "reminders", "sendHeart", "showLatest", "error"]
        guard allowed.contains(action) else { return }
        switch action {
        case "ready":
            if !readyWebs.contains(where: { $0 === sender }) { readyWebs.append(sender) }
            if sender === web { loaded=true }
            do {
                let data=try JSONEncoder().encode(store.load())
                let tasks=try JSONSerialization.jsonObject(with:data)
                canWrite=account == nil || cloudReady; call("window.mmemo.load(tasks, null)",args:["tasks":tasks])
                let members=CloudAccount.all.map {["uid":$0.uid,"username":$0.username,"avatar":$0.avatar]}
                call("window.mmemo.identity(account, members)",args:["account":account?.username as Any? ?? NSNull(),"members":members])
                let name = (try? AIConfiguration.load(directory: store.directory))?.name
                call("window.mmemo.configure(name)", args:["name": name as Any? ?? NSNull()])
                if let latestReply { call("window.mmemo.latest(text)", args:["text":latestReply]) }
                call("window.mmemo.status(text)", args:["text":bubblePhrase])
            } catch {canWrite=false;call("window.mmemo.load([], error)",args:["error":"无法读取待办，请从菜单栏检查数据文件"])}
            if cloud != nil && !loginStarted {loginStarted=true;startRealtime()}
        case "setDone":
            guard sender === web, canWrite, !responding,
                  let id = body["id"] as? String, !id.isEmpty, id.count <= 100,
                  let done = body["done"] as? Bool else { return }
            if let cloud {
                responding=true;cloudGeneration += 1
                Task { @MainActor in
                    defer {self.responding=false;self.syncCloud(force:true)}
                    do {
                        try await cloud.apply([["action":"update","id":id,"patch":["done":done]]])
                        try await self.refreshCloud()
                    } catch {self.cloudFailure(error)}
                }
            } else {
                do {
                    try store.setDone(id:id,done:done)
                    let tasks=try JSONSerialization.jsonObject(with:JSONEncoder().encode(store.load()))
                    call("window.mmemo.load(tasks, null)",args:["tasks":tasks]);refreshReminders()
                } catch {call("window.mmemo.load([], error)",args:["error":"无法保存勾选状态，请重新打开清单后重试"])}
            }
        case "chat":
            guard !responding else { return }
            guard canWrite, let input = body["text"] as? String, !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, input.count <= 2000 else {
                call("window.mmemo.replied(null, null, error)", args:["error":"无法处理输入，请检查待办是否已加载"])
                showAlert("无法发送", "请检查待办是否已加载，输入已保留")
                return
            }
            responding = true;cloudGeneration += 1
            startBubble()
            responseTask = Task { @MainActor in
                defer { self.responding = false; self.responseTask = nil; if self.cloud != nil {self.syncCloud(force:true)} }
                var cloudSubmitted=false
                do {
                    let config: AIConfiguration
                    do { config = try AIConfiguration.load(directory: self.store.directory) }
                    catch { throw AIError("模型未配置或配置无法读取，输入已保留") }
                    if self.cloud != nil {try await self.refreshCloud()}
                    let before = try self.store.load()
                    let reply = try await TodoAssistant(config: config,currentUID:self.account?.uid).respond(to: input, tasks: before, history: self.history)
                    try Task.checkCancellation()
                    var next = try reply.applying(to: before, store: self.store,currentUID:self.account?.uid)
                    let receiptAfter=next
                    guard try self.store.load() == before else { throw AIError("待办已在其他地方变化，本次未写入，请重新发送") }
                    if !reply.changes.isEmpty {
                        if let cloud=self.cloud {
                            cloudSubmitted=true
                            try await cloud.apply(CloudClient.changes(before:before,after:next))
                            next=try await cloud.fetch()
                            try self.store.save(next)
                        } else {try self.store.save(next)}
                    }
                    let receipt = reply.receipt(before:before,after:receiptAfter)
                    self.history += [["role":"user", "content": input], ["role":"assistant", "content": receipt]]
                    self.history = Array(self.history.suffix(12))
                    let tasks = try JSONSerialization.jsonObject(with: JSONEncoder().encode(next))
                    self.latestReply = receipt
                    self.call("window.mmemo.replied(reply, tasks, null)", args:["reply":receipt,"tasks":tasks])
                    self.finishBubble("大功告成了")
                } catch {
                    if Task.isCancelled {
                        self.latestReply = cloudSubmitted ? "已停止等待，云端操作可能已提交，请刷新核对。" : "已停止本次请求，未修改待办。"
                        self.call("window.mmemo.latest(text)", args:["text":self.latestReply!])
                        self.call("window.mmemo.stopped()", args: [:]); self.finishBubble("好，先歇一会儿"); return
                    }
                    let message = (error as? AIError)?.message ?? "请求或保存失败，请刷新核对待办后重试"
                    self.call("window.mmemo.replied(null, null, error)", args:["error":message])
                    self.latestReply = message
                    self.call("window.mmemo.latest(text)", args:["text":message])
                    self.finishBubble("这次没成功，点我看看")
                }
            }
        case "bubbleHover": hoverBubble(body["hovered"] as? Bool ?? false)
        case "showLatest":
            guard latestReply != nil else { return }
            showPanels(); call("window.mmemo.showLatest()", args: [:])
            panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(web)
        case "inputError": showAlert("无法发送", body["message"] as? String ?? "请重试")
        case "stop": responseTask?.cancel()
        case "sendHeart":
            guard !sendingHeart else {return}
            guard let cloud else {showAlert("暂时无法发送", "请打开已登录的双人账号应用");return}
            sendingHeart=true
            call("window.mmemo.heartSending(true)",args:[:])
            Task { @MainActor in
                defer {self.sendingHeart=false;self.call("window.mmemo.heartSending(false)",args:[:])}
                do {try await cloud.sendHeart();self.finishBubble("爱心已发送")}
                catch {self.showAlert("爱心发送未确认", "请稍后再试；对方可能已经收到。")}
            }
        case "hide": hide()
        case "reminders": refreshReminders()
        case "error": NSLog("mmemo JS: %@",body["message"] as? String ?? "unknown")
        default: break
        }
    }
    func startRealtime() {
        cloud?.watch(onChange:{ [weak self] in self?.syncCloud(force:true) },onDisconnect:{ [weak self] in
            guard let self else {return}
            self.canWrite=false
            self.call("window.mmemo.connection(text)",args:["text":"离线 · 正在重连"])
        })
    }
    @objc func systemWoke(_ notification:Notification) {startRealtime()}
    func syncCloud(force: Bool = false) {
        guard cloud != nil else {return}
        syncPending=true
        guard !syncing,!responding else {return}
        syncRetry?.cancel();syncRetry=nil
        syncing=true
        Task { @MainActor in
            defer {self.syncing=false}
            do {
                while self.syncPending && !self.responding {
                    self.syncPending=false
                    try await self.refreshCloud()
                    try await self.receiveHearts()
                }
            } catch {
                self.canWrite=false
                self.call("window.mmemo.connection(text)",args:["text":"离线 · 正在重连"])
                // Retry only a failed synchronization; no periodic reads while idle.
                self.syncRetry=Task { @MainActor in
                    try? await Task.sleep(nanoseconds:5_000_000_000)
                    if !Task.isCancelled {self.syncCloud(force:true)}
                }
            }
        }
    }
    @MainActor func refreshCloud() async throws {
        guard let cloud else {return}
        let generation=cloudGeneration
        let tasks=try await cloud.fetch()
        guard generation==cloudGeneration else {return}
        if try store.load() != tasks {try store.save(tasks)}
        cloudReady=true;canWrite=true
        let rows=try JSONSerialization.jsonObject(with:JSONEncoder().encode(tasks))
        call("window.mmemo.load(tasks, null)",args:["tasks":rows])
        call("window.mmemo.connection(text)",args:["text":"已同步"])
        refreshReminders()
    }
    @MainActor func receiveHearts() async throws {
        guard heartsReady, let cloud else {return}
        while true {
            let ids=try await cloud.fetchHearts()
            guard !ids.isEmpty else {return}
            heartState.receive(ids)
            renderHearts()
            try await cloud.ackHearts(ids)
            if ids.count<100 {return}
        }
    }
    func cloudFailure(_ error: Error) {
        latestReply=error.localizedDescription
        call("window.mmemo.latest(text)",args:["text":latestReply!])
        call("window.mmemo.connection(text)",args:["text":"同步失败 · 正在重试"])
        finishBubble("同步失败，点我查看")
    }
    func refreshReminders() {
        if let tasks=try? store.load() {heartState.refresh(tasks)}
        renderHearts()
    }
    func renderHearts() {
        if let data=try? JSONEncoder().encode(heartState), data != UserDefaults.standard.data(forKey:heartStateKey) {
            UserDefaults.standard.set(data,forKey:heartStateKey)
        }
        guard heartsReady else {return}
        heartsWeb.callAsyncJavaScript("window.hearts.update(level)", arguments:["level":heartState.level()], in:nil, in:.page, completionHandler:nil)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView === heartsWeb { heartsReady = true; refreshReminders(); if cloudReady {syncCloud(force:true)} }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        var url = navigationAction.request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        url?.fragment = nil
        let allowed = url?.url?.standardizedFileURL == resources.appendingPathComponent(webView === heartsWeb ? "web/hearts.html" : "web/index.html").standardizedFileURL
        decisionHandler(allowed ? .allow : .cancel)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {false}
}

let app=NSApplication.shared
let delegate=AppDelegate()
app.delegate=delegate
app.run()
