import SwiftUI
import AppKit
import UserNotifications

@main
struct SnowdropApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class StatusItemManager: NSObject {
    static let shared = StatusItemManager()
    var statusItem: NSStatusItem?
    var popover: NSPopover?

    func setup() {
        let pop = NSPopover()
        pop.contentSize = NSSize(width: 320, height: 460)
        pop.behavior = .transient
        pop.contentViewController = NSHostingController(rootView: MenuBarView())
        self.popover = pop

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "camera.macro", accessibilityDescription: "Snowdrop")
            button.target = self
            button.action = #selector(togglePopover)
        }
        self.statusItem = item
    }

    @objc func togglePopover() {
        guard let pop = popover, let button = statusItem?.button else { return }
        if pop.isShown {
            pop.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            pop.contentViewController?.view.window?.makeKey()
        }
    }

    func showPopover() {
        guard let pop = popover, let button = statusItem?.button else { return }
        if !pop.isShown {
            NSApp.activate(ignoringOtherApps: true)
            pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            pop.contentViewController?.view.window?.makeKey()
        }
    }

    func selectFile() {
        guard let pop = popover else { return }
        // Keep popover pinned open so opening NSOpenPanel does NOT dismiss it
        pop.behavior = .applicationDefined

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose File"
        panel.level = .floating

        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            if response == .OK, let url = panel.url {
                SnowdropEngine.shared.stageFile(url)
            }
            // Restore transient auto-close behavior after selection or cancel
            DispatchQueue.main.async {
                self?.popover?.behavior = .transient
                self?.popover?.contentViewController?.view.window?.makeKey()
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination("Snowdrop background engine")

        SnowdropEngine.shared.start()
        StatusItemManager.shared.setup()
        NSApp.servicesProvider = self

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.scheme == "snowdrop" {
                if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   components.host == "send",
                   let path = components.queryItems?.first(where: { $0.name == "path" })?.value {
                    let fileURL = URL(fileURLWithPath: path)
                    SnowdropEngine.shared.stageFile(fileURL)
                    StatusItemManager.shared.showPopover()
                }
            } else {
                SnowdropEngine.shared.stageFile(url)
                StatusItemManager.shared.showPopover()
            }
        }
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let fileURL = URL(fileURLWithPath: filename)
        SnowdropEngine.shared.stageFile(fileURL)
        StatusItemManager.shared.showPopover()
        return true
    }

    @objc func handleSendService(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let items = pboard.pasteboardItems else { return }
        for item in items {
            if let str = item.string(forType: .fileURL), let url = URL(string: str) {
                SnowdropEngine.shared.stageFile(url)
                StatusItemManager.shared.showPopover()
                return
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        SnowdropEngine.shared.stop()
    }
}
