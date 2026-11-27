import AppKit
import SwiftUI
import SnowdropCore

struct SnowdropCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @Bindable var store: SnowdropStore

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Snowdrop Window") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("0", modifiers: .command)

            Divider()

            Button("Choose Files") {
                store.showFileImporter = true
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("Clear Staged Files") {
                store.clearStagedFiles()
            }
            .keyboardShortcut(.delete, modifiers: [.command, .shift])
            .disabled(store.stagedFiles.isEmpty)
        }

        CommandGroup(after: .sidebar) {
            Button("Devices") {
                store.selectedSection = .devices
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("Transfers") {
                store.selectedSection = .transfers
            }
            .keyboardShortcut("2", modifiers: .command)

            Button("Trusted Devices") {
                store.selectedSection = .trusted
            }
            .keyboardShortcut("3", modifiers: .command)
        }

        CommandMenu("Device") {
            Button("Rename Device") {
                store.showRenameSheet = true
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(store.isRestarting)

            Button("Restart Network Stack") {
                Task { await store.restartEngine() }
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
            .disabled(store.isRestarting)
        }

        CommandMenu("Transfer") {
            Button("Cancel Active Transfers") {
                Task { await store.cancelAllActiveTransfers() }
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(store.activeTransfers.isEmpty)

            Divider()

            Button("Show in Finder") {
                if let transfer = store.selectedRevealableTransfer {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        store.revealURLs(for: transfer)
                    )
                }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(store.selectedRevealableTransfer == nil)

            Button("Clear Transfer History") {
                store.clearRecentTransfers()
            }
            .disabled(store.recentTransfers.isEmpty)
        }
    }
}
