import AppKit
import SwiftUI
import UniformTypeIdentifiers
import SnowdropCore

struct MenuBarCompanionView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.openWindow) private var openWindow
    @Bindable var store: SnowdropStore

    @State private var isDropTargeted = false
    @State private var showingImporter = false

    private var onlinePeers: [PeerItem] {
        store.sortedFilteredPeers.filter(\.online)
    }

    private var unmatchedActiveTransfers: [TransferItem] {
        let visiblePeers = Array(onlinePeers.prefix(5))
        let matchedIDs = Set(visiblePeers.flatMap { store.activeTransfers(for: $0).map(\.id) })
        return store.orderedActiveTransfers.filter { !matchedIDs.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection

            Divider()

            if case .needsAuth = store.status {
                authSection
            }

            if let request = store.pendingApprovals.first {
                approvalSection(request)
            }

            if !unmatchedActiveTransfers.isEmpty {
                unmatchedTransfersSection
            }

            stagingSection

            peersSection

            Divider()

            footerSection
        }
        .padding(16)
        .frame(width: 320)
        .textSelection(.disabled)
        .pointerStyle(.default)
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, lineWidth: 1.5)
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            store.stageFiles(urls) > 0
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                store.stageFiles(urls)
            case .failure(let error):
                store.reportError(error.localizedDescription)
            }
        }
    }

    private var headerSection: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Snowdrop")
                    .font(.headline.weight(.semibold))

                Text(store.deviceName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 4) {
                Circle()
                    .fill(statusTint)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)

                Text(store.status.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Connection status: \(store.status.title)")
        }
    }

    private var authSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tailscale sign-in required")
                .font(.callout.weight(.medium))

            if let url = store.authURL {
                Button("Sign in with Tailscale") {
                    openURL(url)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .pointerStyle(.link)
            } else {
                Text("Preparing sign-in link")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func approvalSection(_ request: IncomingApprovalRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Incoming from \(request.senderName)")
                .font(.callout.weight(.medium))
                .lineLimit(1)

            HStack(spacing: 8) {
                Text(request.fileName)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Text(request.formattedSize)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button("Decline") {
                    Task { await store.resolveApproval(request, decision: .decline) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .pointerStyle(.link)

                Button("Always Trust") {
                    Task { await store.resolveApproval(request, decision: .alwaysTrust) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .pointerStyle(.link)

                Spacer()

                Button("Accept") {
                    Task { await store.resolveApproval(request, decision: .accept) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .pointerStyle(.link)
            }
        }
        .padding(12)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var stagingSection: some View {
        Group {
            if store.stagedFiles.isEmpty {
                Button {
                    showingImporter = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 14, weight: .regular))
                        Text("Choose Files")
                            .font(.callout.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .pointerStyle(.link)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: store.stagedFiles.count > 1 ? "doc.on.doc" : "doc")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.stagedSummaryText)
                            .font(.callout.weight(.medium).monospacedDigit())
                            .lineLimit(1)

                        Text(SnowdropFormat.bytes(store.stagedTotalBytes))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Clear") {
                        store.clearStagedFiles()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .pointerStyle(.link)
                }
            }
        }
    }

    private var peersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Online devices (\(onlinePeers.count))")
                .font(.caption.weight(.medium).monospacedDigit())
                .foregroundStyle(.secondary)

            if onlinePeers.isEmpty {
                Text("No online devices")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                ForEach(onlinePeers.prefix(5)) { peer in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: peer.osSymbolName)
                                .font(.system(size: 14, weight: .regular))
                                .frame(width: 20, height: 20)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)

                            Text(peer.displayName)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)

                            Spacer()

                            Button("Send") {
                                Task { await store.sendStagedFiles(to: peer) }
                            }
                            .buttonStyle(MenuBarSendButtonStyle())
                            .disabled(peer.primaryIP == nil || store.stagedFiles.isEmpty)
                            .accessibilityLabel("Send staged files to \(peer.displayName)")
                        }

                        ForEach(store.activeTransfers(for: peer)) { transfer in
                            HStack(spacing: 8) {
                                ProgressView(value: transfer.progress)
                                    .progressViewStyle(.linear)

                                Text("\(Int(transfer.progress * 100))%")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)

                                Button {
                                    Task { await store.cancelTransfer(id: transfer.id) }
                                } label: {
                                    Image(systemName: "xmark.circle")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(MenuBarActionButtonStyle(isCompact: true))
                                .accessibilityLabel("Cancel transfer of \(transfer.fileName)")
                            }
                        }
                    }
                }
            }
        }
    }

    private var unmatchedTransfersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(unmatchedActiveTransfers) { transfer in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: transfer.direction == .outgoing ? "arrow.up.circle" : "arrow.down.circle")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(transfer.direction == .outgoing ? Color.accentColor : Color.green)
                            .accessibilityHidden(true)

                        Text(transfer.fileName)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        Text(transfer.peerName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 8) {
                        ProgressView(value: transfer.progress)
                            .progressViewStyle(.linear)

                        Text("\(Int(transfer.progress * 100))%")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)

                        Button {
                            Task { await store.cancelTransfer(id: transfer.id) }
                        } label: {
                            Image(systemName: "xmark.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(MenuBarActionButtonStyle(isCompact: true))
                        .accessibilityLabel("Cancel transfer of \(transfer.fileName)")
                    }
                }
                .padding(8)
                .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var footerSection: some View {
        HStack(spacing: 4) {
            Button("Open Snowdrop") {
                NSApp.setActivationPolicy(.regular)
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(MenuBarActionButtonStyle())

            Spacer()

            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(MenuBarActionButtonStyle())

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(MenuBarActionButtonStyle())
        }
        .font(.callout)
    }

    private var statusTint: Color {
        switch store.status {
        case .connected: .green
        case .needsAuth: .orange
        case .connecting: .accentColor
        case .disconnected: .secondary
        case .error: .red
        }
    }
}

private struct MenuBarActionButtonStyle: ButtonStyle {
    var isCompact = false

    func makeBody(configuration: Configuration) -> some View {
        MenuBarActionButtonBody(
            configuration: configuration,
            isCompact: isCompact
        )
    }

    private struct MenuBarActionButtonBody: View {
        let configuration: Configuration
        let isCompact: Bool
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .padding(.horizontal, isCompact ? 4 : 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.14 : (isHovered ? 0.08 : 0)))
                )
                .contentShape(RoundedRectangle(cornerRadius: 6))
                .onHover { isHovered = $0 }
                .pointerStyle(.link)
        }
    }
}

private struct MenuBarSendButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MenuBarSendButtonBody(configuration: configuration)
    }

    private struct MenuBarSendButtonBody: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .font(.callout.weight(.medium))
                .foregroundStyle(isEnabled ? Color.white : Color.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isEnabled ? Color.accentColor : Color.primary.opacity(0.08))
                        .overlay {
                            if isEnabled && (configuration.isPressed || isHovered) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.white.opacity(configuration.isPressed ? 0.22 : 0.14))
                            }
                        }
                )
                .contentShape(RoundedRectangle(cornerRadius: 6))
                .onHover { hovered in
                    isHovered = isEnabled && hovered
                }
                .pointerStyle(isEnabled ? .link : .default)
        }
    }
}
