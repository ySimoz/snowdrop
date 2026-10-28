import SwiftUI
import AppKit
import UserNotifications

@main
struct SnowdropApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject var engine = SnowdropEngine.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: statusIconName)
                Text(statusLabel)
                    .font(.system(size: 11, weight: .medium))
            }
        }
        .menuBarExtraStyle(.window)
    }

    private var statusIconName: String {
        if engine.activeTransfer != nil {
            return "arrow.triangle.2.circlepath"
        }
        switch engine.status {
        case .connected:
            return "camera.macro"
        case .needsAuth:
            return "exclamationmark.triangle.fill"
        case .connecting:
            return "dot.radiowaves.left.and.right"
        case .disconnected, .error:
            return "camera.macro"
        }
    }

    private var statusLabel: String {
        if let transfer = engine.activeTransfer {
            return "\(Int(transfer.progress * 100))%"
        }
        switch engine.status {
        case .connected:
            return "Snowdrop"
        case .needsAuth:
            return "Sign In"
        case .connecting:
            return "Connecting..."
        case .disconnected:
            return "Snowdrop"
        case .error:
            return "Error"
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        SnowdropEngine.shared.start()

        // Inform user app is running in menu bar
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            if granted {
                let content = UNMutableNotificationContent()
                content.title = "Snowdrop"
                content.body = "Snowdrop is running in your menu bar."
                let req = UNNotificationRequest(identifier: "welcome-notice", content: content, trigger: nil)
                UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        SnowdropEngine.shared.stop()
    }
}
