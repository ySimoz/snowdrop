import AppKit
import SwiftUI
import SnowdropCore

@main
struct SnowdropApp: App {
    @Environment(\.openWindow) private var openWindow
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("SnowdropShowMenuBarExtra") private var showMenuBarExtra = true

    var body: some Scene {
        MenuBarExtra(isInserted: $showMenuBarExtra) {
            MenuBarCompanionView(store: appDelegate.store)
                .onAppear { wireMainWindow() }
        } label: {
            Image(nsImage: MenuBarIconRenderer.templateImage())
                .accessibilityLabel("Snowdrop")
                .onAppear { wireMainWindow() }
        }
        .menuBarExtraStyle(.window)

        Window("Snowdrop", id: "main") {
            MainShellView(store: appDelegate.store)
                .frame(minWidth: 720, minHeight: 480)
                .onAppear {
                    wireMainWindow()
                    NSApp.setActivationPolicy(.regular)
                }
                .onDisappear {
                    if showMenuBarExtra {
                        NSApp.setActivationPolicy(.accessory)
                    }
                }
        }
        .defaultLaunchBehavior(.suppressed)
        .commands {
            SnowdropCommands(store: appDelegate.store)
        }

        Settings {
            SettingsShellView(store: appDelegate.store)
                .frame(width: 480, height: 340)
        }
    }

    private func wireMainWindow() {
        appDelegate.store.onRequestMainWindow = {
            NSApp.setActivationPolicy(.regular)
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
