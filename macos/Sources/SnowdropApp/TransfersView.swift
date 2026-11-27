import AppKit
import SwiftUI
import SnowdropCore

struct TransfersView: View {
    @Bindable var store: SnowdropStore

    var body: some View {
        Group {
            if store.orderedActiveTransfers.isEmpty && store.recentTransfers.isEmpty {
                ContentUnavailableView(
                    "No transfers",
                    systemImage: "arrow.up.arrow.down",
                    description: Text("Active and recent transfers appear here")
                )
            } else {
                List(selection: $store.selectedTransferID) {
                    if !store.orderedActiveTransfers.isEmpty {
                        Section("Active") {
                            ForEach(store.orderedActiveTransfers) { transfer in
                                ActiveTransferRow(transfer: transfer) {
                                    Task { await store.cancelTransfer(id: transfer.id) }
                                }
                                .tag(transfer.id)
                            }
                        }
                    }

                    if !store.recentTransfers.isEmpty {
                        Section("Recent") {
                            ForEach(store.recentTransfers) { transfer in
                                RecentTransferRow(
                                    transfer: transfer,
                                    onReveal: {
                                        NSWorkspace.shared.activateFileViewerSelecting(
                                            store.revealURLs(for: transfer)
                                        )
                                    },
                                    onRemove: {
                                        store.removeRecentTransfer(id: transfer.id)
                                    }
                                )
                                .tag(transfer.id)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button("Show in Finder", systemImage: "folder") {
                    if let transfer = store.selectedRevealableTransfer {
                        NSWorkspace.shared.activateFileViewerSelecting(
                            store.revealURLs(for: transfer)
                        )
                    }
                }
                .disabled(store.selectedRevealableTransfer == nil)
                .accessibilityLabel("Show selected transfer in Finder")

                Button("Clear History", systemImage: "trash") {
                    store.clearRecentTransfers()
                }
                .disabled(store.recentTransfers.isEmpty)
                .accessibilityLabel("Clear transfer history")
            }
        }
    }
}

private struct ActiveTransferRow: View {
    let transfer: TransferItem
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: transfer.direction == .outgoing ? "arrow.up.circle" : "arrow.down.circle")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(transfer.direction == .outgoing ? Color.accentColor : Color.green)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(transfer.fileName)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(transfer.direction == .outgoing ? "To \(transfer.peerName)" : "From \(transfer.peerName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)

                Spacer()

                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Cancel transfer of \(transfer.fileName)")
            }

            VStack(alignment: .leading, spacing: 8) {
                if transfer.isBatch && !transfer.currentFileName.isEmpty {
                    Text("File \(transfer.fileIndex) of \(transfer.totalFiles): \(transfer.currentFileName)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                ProgressView(value: transfer.progress)
                    .progressViewStyle(.linear)

                HStack {
                    Text("\(Int(transfer.progress * 100))%")
                        .font(.caption.weight(.medium).monospacedDigit())
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(transfer.speedFormatted) • \(transfer.remainingTimeFormatted)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(transfer.isBatch && !transfer.currentFileName.isEmpty ? "File \(transfer.fileIndex) of \(transfer.totalFiles): \(transfer.currentFileName), " : "")\(Int(transfer.progress * 100)) percent, \(transfer.speedFormatted), \(transfer.remainingTimeFormatted) remaining")
        }
        .padding(.vertical, 4)
    }
}

private struct RecentTransferRow: View {
    let transfer: TransferItem
    let onReveal: () -> Void
    let onRemove: () -> Void

    private var subtitleText: String {
        if transfer.isSuccess {
            return transfer.direction == .incoming
                ? "Received from \(transfer.peerName)"
                : "Sent to \(transfer.peerName)"
        }
        return transfer.errorMessage ?? "Failed"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: transfer.isSuccess ? "checkmark.circle" : "exclamationmark.circle")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(transfer.isSuccess ? Color.green : Color.red)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(transfer.fileName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(subtitleText)
                    .font(.caption)
                    .foregroundStyle(transfer.isSuccess ? Color.secondary : Color.red)
                    .lineLimit(1)
            }

            Spacer()

            if transfer.totalBytes > 0 {
                Text(SnowdropFormat.bytes(transfer.totalBytes))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(transfer.fileName), \(subtitleText)\(transfer.totalBytes > 0 ? ", \(SnowdropFormat.bytes(transfer.totalBytes))" : "")")
        .contextMenu {
            if transfer.isSuccess && transfer.direction == .incoming {
                Button("Show in Finder", action: onReveal)
            }
            Button("Remove from History", action: onRemove)
        }
    }
}
