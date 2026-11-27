import AppKit
import SwiftUI
import SnowdropCore

struct DevicesView: View {
    @Environment(\.openURL) private var openURL
    @Bindable var store: SnowdropStore
    @State private var isDropTargeted = false

    var body: some View {
        Group {
            if case .needsAuth = store.status {
                ContentUnavailableView {
                    Label("Tailscale sign-in required", systemImage: "person.badge.key")
                } description: {
                    Text("Sign in with Tailscale to discover devices on your Tailnet")
                } actions: {
                    if let url = store.authURL {
                        Button("Sign in with Tailscale") {
                            openURL(url)
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Text("Preparing sign-in link")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if store.peers.isEmpty {
                ContentUnavailableView {
                    Label(emptyTitle, systemImage: "laptopcomputer.and.iphone")
                } description: {
                    Text(emptyDescription)
                } actions: {
                    Button("Choose Files") {
                        store.showFileImporter = true
                    }
                    .buttonStyle(.bordered)
                }
            } else if store.sortedFilteredPeers.isEmpty {
                ContentUnavailableView.search(text: store.searchText)
            } else {
                List(store.sortedFilteredPeers) { peer in
                    PeerRowView(store: store, peer: peer)
                }
                .listStyle(.inset)
            }
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, lineWidth: 1.5)
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            store.stageFiles(urls) > 0
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .searchable(text: $store.searchText, prompt: "Search devices")
    }

    private var emptyTitle: String {
        switch store.status {
        case .connected: "No devices found"
        case .connecting: "Connecting to Tailnet"
        case .disconnected, .error: "Not connected"
        case .needsAuth: "Tailscale sign-in required"
        }
    }

    private var emptyDescription: String {
        switch store.status {
        case .connected: "Drop files here or wait for peers on your Tailnet"
        case .connecting: "Waiting for Tailnet connection"
        case .disconnected, .error: "Restart the network stack to connect"
        case .needsAuth: "Sign in with Tailscale to discover devices"
        }
    }
}

private struct PeerRowView: View {
    @Bindable var store: SnowdropStore
    let peer: PeerItem

    private var canSend: Bool {
        peer.online && peer.primaryIP != nil && !store.stagedFiles.isEmpty
    }

    private var peerTransfers: [TransferItem] {
        store.activeTransfers(for: peer)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: peer.osSymbolName)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(peer.online ? .primary : .secondary)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(peer.displayName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(peer.online ? .primary : .secondary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(peer.online ? Color.green : Color.secondary.opacity(0.5))
                                .frame(width: 6, height: 6)
                                .accessibilityHidden(true)

                            Text(peer.online ? "Online" : "Offline")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let ip = peer.primaryIP {
                            Text(ip)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(peer.displayName), \(peer.online ? "Online" : "Offline")\(peer.primaryIP.map { ", \($0)" } ?? "")")

                Spacer()

                Button("Send") {
                    Task { await store.sendStagedFiles(to: peer) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!canSend)
                .accessibilityLabel("Send staged files to \(peer.displayName)")
            }

            ForEach(peerTransfers) { transfer in
                PeerInlineTransferRow(transfer: transfer) {
                    Task { await store.cancelTransfer(id: transfer.id) }
                }
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Send Staged Files") {
                Task { await store.sendStagedFiles(to: peer) }
            }
            .disabled(!canSend)

            if let ip = peer.primaryIP {
                Button("Copy Tailscale IP") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(ip, forType: .string)
                }
            }
        }
    }
}

private struct PeerInlineTransferRow: View {
    let transfer: TransferItem
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if transfer.isBatch && !transfer.currentFileName.isEmpty {
                Text("File \(transfer.fileIndex) of \(transfer.totalFiles): \(transfer.currentFileName)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                ProgressView(value: transfer.progress)
                    .progressViewStyle(.linear)

                Button(action: onCancel) {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Cancel transfer of \(transfer.fileName)")
            }

            HStack {
                Text("\(Int(transfer.progress * 100))% • \(transfer.fileName)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                Text("\(transfer.speedFormatted) • \(transfer.remainingTimeFormatted)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 36)
    }
}
