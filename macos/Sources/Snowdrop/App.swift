import SwiftUI
import AppKit
import UserNotifications

@main
struct SnowdropApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject var engine = SnowdropEngine.shared

    var body: some Scene {
        MenuBarExtra("Snowdrop", systemImage: "camera.macro") {
            MenuBarView()
                .frame(width: 320, height: 480)
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
        }
        .menuBarExtraStyle(.window)
    }

    private func handleIncomingURL(_ url: URL) {
        if url.scheme == "snowdrop" {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
            if components.host == "send", let path = components.queryItems?.first(where: { $0.name == "path" })?.value {
                let fileURL = URL(fileURLWithPath: path)
                if let peer = engine.peers.first {
                    engine.sendFile(to: peer, fileURL: fileURL)
                }
            }
        } else if let peer = engine.peers.first {
            engine.sendFile(to: peer, fileURL: url)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevent AppKit from terminating the daemon when the popover is dismissed
        ProcessInfo.processInfo.disableAutomaticTermination("Snowdrop background engine")

        SnowdropEngine.shared.start()
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
                    if let peer = SnowdropEngine.shared.peers.first {
                        SnowdropEngine.shared.sendFile(to: peer, fileURL: fileURL)
                    }
                }
            } else if let peer = SnowdropEngine.shared.peers.first {
                SnowdropEngine.shared.sendFile(to: peer, fileURL: url)
            }
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

    @objc func handleSendService(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let items = pboard.pasteboardItems else { return }
        for item in items {
            if let str = item.string(forType: .fileURL), let url = URL(string: str) {
                if let peer = SnowdropEngine.shared.peers.first {
                    SnowdropEngine.shared.sendFile(to: peer, fileURL: url)
                    return
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        SnowdropEngine.shared.stop()
    }
}

