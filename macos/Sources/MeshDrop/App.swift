import SwiftUI
import AppKit

@main
struct MeshDropApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject var engine = MeshDropEngine.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: statusIconName)
                if let transfer = engine.activeTransfer {
                    Text("\(Int(transfer.progress * 100))%")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                }
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
            return "paperplane.fill"
        case .needsAuth:
            return "exclamationmark.triangle.fill"
        case .connecting:
            return "dot.radiowaves.left.and.right"
        case .disconnected, .error:
            return "paperplane"
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure app doesn't show in dock
        NSApp.setActivationPolicy(.accessory)
        MeshDropEngine.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        MeshDropEngine.shared.stop()
    }
}
