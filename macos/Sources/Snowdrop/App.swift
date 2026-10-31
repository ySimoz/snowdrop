import SwiftUI
import AppKit
import UserNotifications

@main
struct SnowdropApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsPopoverView(engine: SnowdropEngine.shared, vm: MenuBarViewModel())
                .frame(width: 320)
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
            button.image = Self.createMenuBarTemplateIcon()
            button.target = self
            button.action = #selector(togglePopover)
        }
        self.statusItem = item
    }

    static func createMenuBarTemplateIcon() -> NSImage {
        let size = CGFloat(18)
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.saveGState()

            let scale = (size * 0.86) / 330.0
            ctx.translateBy(x: size / 2.0, y: size * 0.50)
            ctx.scaleBy(x: scale, y: -scale)
            ctx.translateBy(x: -256.0, y: -214.0)

            // 1. Unified Outer Shell & Stem
            let outerPath = CGMutablePath()
            outerPath.move(to: CGPoint(x: 245, y: 365))
            outerPath.addCurve(to: CGPoint(x: 225, y: 255), control1: CGPoint(x: 245, y: 320), control2: CGPoint(x: 242, y: 285))
            outerPath.addCurve(to: CGPoint(x: 142, y: 120), control1: CGPoint(x: 205, y: 220), control2: CGPoint(x: 138, y: 180))
            outerPath.addCurve(to: CGPoint(x: 192, y: 122), control1: CGPoint(x: 145, y: 94),  control2: CGPoint(x: 175, y: 102))
            outerPath.addCurve(to: CGPoint(x: 252, y: 278), control1: CGPoint(x: 218, y: 154), control2: CGPoint(x: 238, y: 230))
            outerPath.addCurve(to: CGPoint(x: 260, y: 278), control1: CGPoint(x: 253, y: 282), control2: CGPoint(x: 259, y: 282))
            outerPath.addCurve(to: CGPoint(x: 320, y: 122), control1: CGPoint(x: 274, y: 230), control2: CGPoint(x: 294, y: 154))
            outerPath.addCurve(to: CGPoint(x: 370, y: 120), control1: CGPoint(x: 337, y: 102), control2: CGPoint(x: 367, y: 94))
            outerPath.addCurve(to: CGPoint(x: 287, y: 255), control1: CGPoint(x: 374, y: 180), control2: CGPoint(x: 307, y: 220))
            outerPath.addCurve(to: CGPoint(x: 267, y: 365), control1: CGPoint(x: 270, y: 285), control2: CGPoint(x: 267, y: 320))
            outerPath.addArc(center: CGPoint(x: 256, y: 365), radius: 11, startAngle: 0, endAngle: .pi, clockwise: false)
            outerPath.closeSubpath()

            // 2. Center Petal
            let centerPath = CGMutablePath()
            centerPath.move(to: CGPoint(x: 256, y: 52))
            centerPath.addCurve(to: CGPoint(x: 256, y: 282), control1: CGPoint(x: 286, y: 125), control2: CGPoint(x: 288, y: 215))
            centerPath.addCurve(to: CGPoint(x: 256, y: 52),  control1: CGPoint(x: 224, y: 215), control2: CGPoint(x: 226, y: 125))
            centerPath.closeSubpath()

            // 3. Separation Slits
            let slitLeft = CGMutablePath()
            slitLeft.move(to: CGPoint(x: 256, y: 64))
            slitLeft.addCurve(to: CGPoint(x: 254, y: 274), control1: CGPoint(x: 224, y: 130), control2: CGPoint(x: 222, y: 215))

            let slitRight = CGMutablePath()
            slitRight.move(to: CGPoint(x: 256, y: 64))
            slitRight.addCurve(to: CGPoint(x: 258, y: 274), control1: CGPoint(x: 288, y: 130), control2: CGPoint(x: 290, y: 215))

            // Draw Outer Path
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.addPath(outerPath)
            ctx.fillPath()

            // Clear separation slits for crisp gap
            ctx.saveGState()
            ctx.setBlendMode(.clear)
            ctx.setLineWidth(14)
            ctx.setLineCap(.round)
            ctx.addPath(slitLeft)
            ctx.addPath(slitRight)
            ctx.strokePath()
            ctx.restoreGState()

            // Draw Center Petal
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.addPath(centerPath)
            ctx.fillPath()

            ctx.restoreGState()
            return true
        }
        img.isTemplate = true
        return img
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
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let pop = self.popover, let button = self.statusItem?.button else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.showPopover()
                }
                return
            }
            NSApp.activate(ignoringOtherApps: true)
            if !pop.isShown {
                pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
            pop.contentViewController?.view.window?.makeKey()
            pop.contentViewController?.view.window?.orderFrontRegardless()
        }
    }

    func selectFile() {
        guard let pop = popover else { return }
        // Keep popover pinned open so opening NSOpenPanel does NOT dismiss it
        pop.behavior = .applicationDefined

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Choose Files"
        panel.level = .floating

        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            if response == .OK {
                let urls = panel.urls
                if !urls.isEmpty {
                    SnowdropEngine.shared.stageFiles(urls)
                }
            }
            // Restore transient auto-close behavior after selection or cancel
            DispatchQueue.main.async {
                self?.popover?.behavior = .transient
                self?.popover?.contentViewController?.view.window?.makeKey()
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination("Snowdrop background engine")

        UNUserNotificationCenter.current().delegate = self
        SnowdropEngine.shared.start()
        StatusItemManager.shared.setup()
        NSApp.servicesProvider = self

        if SnowdropEngine.shared.stagedFileURL != nil {
            StatusItemManager.shared.showPopover()
        }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let transferID = response.notification.request.content.userInfo["transferID"] as? String
            ?? response.notification.request.identifier

        switch response.actionIdentifier {
        case "ACTION_ACCEPT":
            SnowdropEngine.shared.resolveApproval(transferID: transferID, decision: 1)
        case "ACTION_TRUST":
            SnowdropEngine.shared.resolveApproval(transferID: transferID, decision: 2)
        case "ACTION_DECLINE", UNNotificationDismissActionIdentifier:
            SnowdropEngine.shared.resolveApproval(transferID: transferID, decision: 3)
        default:
            StatusItemManager.shared.showPopover()
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.scheme == "snowdrop" {
                if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                    if components.host == "test-notif" {
                        SnowdropEngine.shared.handleIncomingApproval(
                            transferID: "test-\(UUID().uuidString.prefix(6))",
                            nodeID: "test-node",
                            senderName: "Pixel Phone",
                            fileName: "holiday_photo.jpg",
                            fileSize: 4500000
                        )
                        continue
                    }
                    if components.host == "send",
                       let path = components.queryItems?.first(where: { $0.name == "path" })?.value {
                    let fileURL = URL(fileURLWithPath: path).standardizedFileURL
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir), !isDir.boolValue {
                        let normalized = fileURL.path.lowercased()
                        let isSensitive = normalized.contains("/.ssh/") ||
                                          normalized.contains("/.aws/") ||
                                          normalized.contains("/.gnupg/") ||
                                          normalized.hasPrefix("/etc/") ||
                                          normalized.hasPrefix("/var/") ||
                                          fileURL.lastPathComponent.hasPrefix(".")
                        if !isSensitive {
                            SnowdropEngine.shared.stageFile(fileURL)
                            StatusItemManager.shared.showPopover()
                        }
                    }
                }
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
        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            SnowdropEngine.shared.stageFiles(urls)
            StatusItemManager.shared.showPopover()
            return
        }
        guard let items = pboard.pasteboardItems else { return }
        var staged: [URL] = []
        for item in items {
            if let str = item.string(forType: .fileURL), let url = URL(string: str) {
                staged.append(url)
            }
        }
        if !staged.isEmpty {
            SnowdropEngine.shared.stageFiles(staged)
            StatusItemManager.shared.showPopover()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        SnowdropEngine.shared.stop()
    }
}
