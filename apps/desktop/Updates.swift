import AppKit
#if canImport(Sparkle)
import Sparkle
#endif

/// Development bundles never start the updater. Account variants have separate feeds.
final class UpdateManager: NSObject, NSMenuItemValidation {
    private(set) var availableVersion: String?
    private(set) var checkItem: NSMenuItem!
    private var automaticItem: NSMenuItem!
    private var observations: [NSKeyValueObservation] = []
    var stateChanged: ((Bool) -> Void)?
    let enabled = Bundle.main.object(forInfoDictionaryKey: "MMemoUpdatesEnabled") as? Bool == true
    #if canImport(Sparkle)
    private(set) var controller: SPUStandardUpdaterController?
    #endif

    func addItems(to menu: NSMenu) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知"
        menu.addItem(withTitle: "版本 \(version)", action: nil, keyEquivalent: "")
        checkItem = menu.addItem(withTitle: enabled ? "检查更新…" : "检查更新（开发版未启用）", action: #selector(check), keyEquivalent: "")
        checkItem.target = self
        automaticItem = menu.addItem(withTitle: "自动检查更新", action: #selector(toggleAutomatic), keyEquivalent: "")
        automaticItem.target = self
    }

    func start() {
        guard enabled else { return }
        #if canImport(Sparkle)
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self)
        self.controller = controller
        observations = [controller.updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] _, _ in self?.refresh() }]
        controller.startUpdater()
        refresh()
        #endif
    }

    @objc func check() {
        #if canImport(Sparkle)
        controller?.checkForUpdates(nil)
        #endif
    }

    @objc private func toggleAutomatic() {
        #if canImport(Sparkle)
        guard let updater = controller?.updater else { return }
        updater.automaticallyChecksForUpdates.toggle()
        refresh()
        #endif
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        #if canImport(Sparkle)
        guard let updater = controller?.updater else { return false }
        return menuItem === automaticItem || updater.canCheckForUpdates
        #else
        return false
        #endif
    }

    private func refresh() {
        #if canImport(Sparkle)
        automaticItem?.state = controller?.updater.automaticallyChecksForUpdates == true ? .on : .off
        #endif
        checkItem?.title = availableVersion.map { "有新版本 · \($0)…" } ?? (enabled ? "检查更新…" : "检查更新（开发版未启用）")
        stateChanged?(availableVersion != nil)
    }
}

#if canImport(Sparkle)
extension UpdateManager: SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        availableVersion = update.displayVersionString
        refresh()
        return false
    }
    func standardUserDriverWillFinishUpdateSession() {
        availableVersion = nil
        refresh()
    }
}
#endif

extension AppDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if terminationPrepared { return .terminateNow }
        if responding || sendingHeart {
            showAlert("暂时不能退出或安装更新", "有请求正在处理。请等待完成后，再点击安装并重启；当前应用会继续运行。")
            return .terminateCancel
        }
        if preparingTermination { return .terminateLater }
        guard loaded, let web else { return .terminateNow }
        guard draftRestored else {
            showAlert("输入尚未恢复", "请等待窗口加载完成；如果数据读取失败，请先检查本地数据文件。")
            return .terminateCancel
        }
        preparingTermination = true
        // Begin WebKit work before returning terminateLater. A new MainActor Task can
        // be starved by AppKit's termination loop when quitting from a menu action.
        web.evaluateJavaScript("window.mmemo.prepareToQuit()") { [self] value, error in
            do {
                if let error { throw error }
                try ComposerDraft.save(value as Any, directory: store.directory)
                terminationPrepared = true
                sender.reply(toApplicationShouldTerminate: true)
            } catch {
                preparingTermination = false
                web.evaluateJavaScript("window.mmemo.stopped()", completionHandler: nil)
                showAlert("输入尚未保存", "本次退出或更新已暂停，请重试。你的输入仍保留在窗口中。")
                sender.reply(toApplicationShouldTerminate: false)
            }
        }
        return .terminateLater
    }
}
