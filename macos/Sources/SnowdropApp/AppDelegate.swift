import AppKit
import SnowdropBridge
import SnowdropCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = SnowdropStore(backend: LiveSnowdropBackend())
    private let notificationManager = NotificationManager()
    private var pendingFileURLs: [URL] = []
    private var pendingHandoffIDs: [UUID] = []
    private var didFinishLaunching = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        didFinishLaunching = true
        ProcessInfo.processInfo.disableAutomaticTermination("Snowdrop background engine")
        NSApp.servicesProvider = self
        notificationManager.configure(store: store)

        Task { @MainActor in
            await store.start()
            flushPendingInputs()
        }

        if let containerURL = ShareHandoffStore.defaultContainerURL() {
            Task.detached(priority: .utility) {
                ShareHandoffStore.cleanupExpiredHandoffs(in: containerURL)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if sender.activationPolicy() == .accessory {
            return false
        }
        if !flag {
            store.onRequestMainWindow?()
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { @MainActor in
            if let containerURL = ShareHandoffStore.defaultContainerURL() {
                await Task.detached(priority: .utility) {
                    ShareHandoffStore.cleanupExpiredHandoffs(in: containerURL)
                }.value
            }
            await store.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        var directFiles: [URL] = []

        for url in urls {
            if let handoffID = ShareHandoffStore.handoffID(from: url) {
                if didFinishLaunching {
                    consumeShareHandoff(id: handoffID)
                } else {
                    pendingHandoffIDs.append(handoffID)
                }
            } else if url.isFileURL {
                directFiles.append(url)
            }
            // Legacy snowdrop://send?path=... URLs are intentionally ignored.
        }

        if !directFiles.isEmpty {
            stageOrQueue(directFiles)
        }
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        if !didFinishLaunching {
            pendingFileURLs.append(url)
            return true
        }
        let added = store.stageFiles([url])
        if added > 0 {
            presentMainWindowForStaging()
        }
        return added > 0
    }

    @objc func handleSendService(
        _ pboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        var urls: [URL] = []
        if let objects = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            urls.append(contentsOf: objects.filter(\.isFileURL))
        }
        if urls.isEmpty, let items = pboard.pasteboardItems {
            for item in items {
                if let raw = item.string(forType: .fileURL),
                   let url = URL(string: raw),
                   url.isFileURL {
                    urls.append(url)
                }
            }
        }

        if !urls.isEmpty {
            stageOrQueue(urls)
        }
    }

    private func presentMainWindowForStaging() {
        store.selectedSection = .devices
        NSApp.setActivationPolicy(.regular)
        store.onRequestMainWindow?()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func stageOrQueue(_ urls: [URL]) {
        if !didFinishLaunching {
            pendingFileURLs.append(contentsOf: urls)
            return
        }
        if store.stageFiles(urls) > 0 {
            presentMainWindowForStaging()
        }
    }

    private func flushPendingInputs() {
        if !pendingFileURLs.isEmpty {
            let queuedFiles = pendingFileURLs
            pendingFileURLs.removeAll()
            if store.stageFiles(queuedFiles) > 0 {
                presentMainWindowForStaging()
            }
        }

        if !pendingHandoffIDs.isEmpty {
            let queuedIDs = pendingHandoffIDs
            pendingHandoffIDs.removeAll()
            for id in queuedIDs {
                consumeShareHandoff(id: id)
            }
        }
    }

    private func consumeShareHandoff(id: UUID) {
        guard let containerURL = ShareHandoffStore.defaultContainerURL() else {
            store.reportError("App Group sharing requires a signed build")
            return
        }

        Task { @MainActor [weak self] in
            let stagedURLs = await Task.detached(priority: .userInitiated) {
                try? ShareHandoffStore.consumeHandoff(id: id, in: containerURL)
            }.value

            guard let self, let stagedURLs, !stagedURLs.isEmpty else {
                self?.store.reportError("Shared files could not be loaded")
                return
            }
            self.stageOrQueue(stagedURLs)
        }
    }
}
