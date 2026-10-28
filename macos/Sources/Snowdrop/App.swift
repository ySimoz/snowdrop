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
        }
        .windowResizability(.contentSize)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        SnowdropEngine.shared.start()
        setupStatusItem()

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
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

    @objc private func statusItemClicked() {
        if let win = NSApp.windows.first(where: { $0.title == "Snowdrop" }) {
            if win.isVisible {
                win.orderOut(nil)
            } else {
                win.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NSApp.windows.first(where: { $0.title == "Snowdrop" })?.makeKeyAndOrderFront(nil)
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        SnowdropEngine.shared.stop()
    }
}
