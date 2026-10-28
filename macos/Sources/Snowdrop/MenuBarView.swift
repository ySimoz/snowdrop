import SwiftUI
import AppKit
import UniformTypeIdentifiers

public final class MenuBarViewModel: ObservableObject {
    @Published public var isTargetedForDrop = false
    @Published public var showingSettings = false
    @Published public var selectedPeerForDrop: PeerItem?
    @Published public var pendingDropURL: URL?

    public init() {}
}

public struct MenuBarView: View {
    @ObservedObject var engine = SnowdropEngine.shared
    @ObservedObject var vm = MenuBarViewModel()

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(spacing: 12) {
                    // Auth Banner
                    if case .needsAuth = engine.status {
                        authBanner
                    }

                    // Active Transfer
                    if let transfer = engine.activeTransfer {
                        TransferCardView(transfer: transfer) {
                            engine.cancelActiveTransfer()
                        }
                    }

                    // Available Peers
                    peersSection

                    // Quick Drop Zone
                    dropZoneView
                }
                .padding(14)
            }
            .frame(maxHeight: 420)

            Divider()

            // Footer / Settings
            footerView
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .frame(width: 320)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(item: Binding(
            get: { vm.selectedPeerForDrop },
            set: { vm.selectedPeerForDrop = $0 }
        )) { peer in
            PeerDropSheet(peer: peer, fileURL: vm.pendingDropURL) {
                vm.selectedPeerForDrop = nil
                vm.pendingDropURL = nil
            }
        }
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack {
            Image(systemName: "camera.macro")
                .foregroundColor(.accentColor)
                .font(.system(size: 16))

            VStack(alignment: .leading, spacing: 2) {
                Text("Snowdrop")
                    .font(.system(size: 14, weight: .bold))

                Text(engine.deviceName)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                Text(engine.status.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var authBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tailscale Authentication Required")
                .font(.system(size: 12, weight: .semibold))

            Text("Sign in to your Tailnet to discover and transfer files with your devices.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Button(action: { engine.openAuthURL() }) {
                HStack {
                    Image(systemName: "arrow.up.right.square")
                    Text("Sign in with Tailscale")
                }
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
        }
        .padding(10)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }

    private var peersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PEERS ON TAILNET")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)

            if engine.peers.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "network.slash")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary.opacity(0.6))
                        Text(engine.status == .connected ? "No peers found on Tailnet" : "Waiting for connection...")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 16)
                    Spacer()
                }
            } else {
                ForEach(engine.peers) { peer in
                    peerRow(peer: peer)
                }
            }
        }
    }

    private func peerRow(peer: PeerItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: peer.osIcon)
                .font(.system(size: 14))
                .foregroundColor(peer.online ? .accentColor : .secondary)
                .frame(width: 24, height: 24)
                .background(Color.secondary.opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(peer.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                if let ip = peer.primaryIP {
                    Text(ip)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button(action: { promptFileSelection(for: peer) }) {
                Text("Send")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!peer.online || engine.activeTransfer != nil)
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }

    private var dropZoneView: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 22))
                .foregroundColor(vm.isTargetedForDrop ? .accentColor : .secondary)

            Text("Drop file here to send")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(vm.isTargetedForDrop ? .accentColor : .secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 70)
        .background(vm.isTargetedForDrop ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(vm.isTargetedForDrop ? Color.accentColor : Color.secondary.opacity(0.2), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
        )
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: Binding(
            get: { vm.isTargetedForDrop },
            set: { vm.isTargetedForDrop = $0 }
        )) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let fileURL = url {
                    DispatchQueue.main.async {
                        self.handleDroppedFile(fileURL)
                    }
                }
            }
            return true
        }
    }

    private var footerView: some View {
        HStack {
            Button(action: { vm.showingSettings.toggle() }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .popover(isPresented: Binding(
                get: { vm.showingSettings },
                set: { vm.showingSettings = $0 }
            )) {
                SettingsPopoverView(engine: engine)
            }

            Spacer()

            Button("Quit") {
                engine.stop()
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
        }
    }

    // MARK: - Helpers

    private var statusColor: Color {
        switch engine.status {
        case .connected: return .green
        case .needsAuth: return .orange
        case .connecting: return .yellow
        case .disconnected, .error: return .gray
        }
    }

    private func promptFileSelection(for peer: PeerItem) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Send to \(peer.displayName)"

        if panel.runModal() == .OK, let fileURL = panel.url {
            engine.sendFile(to: peer, fileURL: fileURL)
        }
    }

    private func handleDroppedFile(_ url: URL) {
        if engine.peers.count == 1, let singlePeer = engine.peers.first {
            engine.sendFile(to: singlePeer, fileURL: url)
        } else if engine.peers.count > 1 {
            vm.pendingDropURL = url
            vm.selectedPeerForDrop = engine.peers.first
        }
    }
}

struct PeerDropSheet: View {
    let peer: PeerItem
    let fileURL: URL?
    let onDismiss: () -> Void
    @ObservedObject var engine = SnowdropEngine.shared

    var body: some View {
        VStack(spacing: 12) {
            Text("Send to Peer")
                .font(.headline)

            if let url = fileURL {
                Text(url.lastPathComponent)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            ForEach(engine.peers) { target in
                Button(action: {
                    if let url = fileURL {
                        engine.sendFile(to: target, fileURL: url)
                    }
                    onDismiss()
                }) {
                    HStack {
                        Image(systemName: target.osIcon)
                        Text(target.displayName)
                        Spacer()
                    }
                    .padding(8)
                }
                .buttonStyle(.bordered)
            }

            Button("Cancel", action: onDismiss)
                .controlSize(.small)
        }
        .padding(16)
        .frame(width: 260)
    }
}

struct SettingsPopoverView: View {
    @ObservedObject var engine: SnowdropEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Settings")
                .font(.system(size: 13, weight: .bold))

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Downloads Folder:")
                    .font(.system(size: 11, weight: .medium))

                Text(engine.downloadDirectory.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Button("Change Folder...") {
                    engine.selectDownloadFolder()
                }
                .controlSize(.small)
            }

            Toggle("Auto-accept transfers", isOn: Binding(
                get: { engine.autoAccept },
                set: { engine.autoAccept = $0 }
            ))
            .font(.system(size: 11))

            Divider()

            Button("Restart Tailscale Stack") {
                engine.stop()
                engine.start()
            }
            .font(.system(size: 11))
            .controlSize(.small)
        }
        .padding(12)
        .frame(width: 240)
    }
}
