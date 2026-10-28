import SwiftUI
import AppKit
import UserNotifications

@main
struct SnowdropApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject var engine = SnowdropEngine.shared

    var body: some Scene {
        Window("Snowdrop", id: "main") {
            MenuBarView()
                .frame(width: 340, height: 520)
                .onOpenURL { url in
                    if let peer = SnowdropEngine.shared.peers.first {
                        SnowdropEngine.shared.sendFile(to: peer, fileURL: url)
                    }
                }
        }
        .windowResizability(.contentSize)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        SnowdropEngine.shared.start()
        setupStatusItem()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if let win = self.findMainWindow() {
                win.delegate = self
            }
        }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "camera.macro", accessibilityDescription: "Snowdrop")
            button.title = " Snowdrop"
            button.target = self
            button.action = #selector(statusItemClicked)
        }
        self.statusItem = item
    }

    private func findMainWindow() -> NSWindow? {
        return NSApp.windows.first(where: {
            $0.title == "Snowdrop" || $0.identifier?.rawValue == "main"
        })
    }

    @objc private func statusItemClicked() {
        if let win = findMainWindow() {
            if win.isVisible && win.isKeyWindow {
                win.orderOut(nil)
            } else {
                win.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            findMainWindow()?.makeKeyAndOrderFront(nil)
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let peer = SnowdropEngine.shared.peers.first, let url = urls.first {
            SnowdropEngine.shared.sendFile(to: peer, fileURL: url)
        }
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let fileURL = URL(fileURLWithPath: filename)
        if let peer = SnowdropEngine.shared.peers.first {
            SnowdropEngine.shared.sendFile(to: peer, fileURL: fileURL)
            return true
        }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        SnowdropEngine.shared.stop()
    }
}
