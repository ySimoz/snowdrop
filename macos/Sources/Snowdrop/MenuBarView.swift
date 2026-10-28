import SwiftUI
import AppKit
import UniformTypeIdentifiers

public final class MenuBarViewModel: ObservableObject {
    @Published public var isTargetedForDrop = false
    @Published public var showingSettings = false
    @Published public var showingRenameDialog = false
    @Published public var renameText = ""
    @Published public var stagedFileURL: URL?
    @Published public var stagedFileName: String = ""
    @Published public var stagedFileSizeFormatted: String = ""
    @Published public var selectedPeerForDrop: PeerItem?
    @Published public var pendingDropURL: URL?

    public init() {}

    public func stageFile(_ url: URL) {
        self.stagedFileURL = url
        self.stagedFileName = url.lastPathComponent
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int64 {
            if size >= 1024 * 1024 * 1024 {
                self.stagedFileSizeFormatted = String(format: "%.2f GB", Double(size) / (1024 * 1024 * 1024))
            } else if size >= 1024 * 1024 {
                self.stagedFileSizeFormatted = String(format: "%.1f MB", Double(size) / (1024 * 1024))
            } else if size >= 1024 {
                self.stagedFileSizeFormatted = String(format: "%.0f KB", Double(size) / 1024)
            } else {
                self.stagedFileSizeFormatted = "\(size) B"
            }
        } else {
            self.stagedFileSizeFormatted = ""
        }
    }

    public func clearStagedFile() {
        self.stagedFileURL = nil
        self.stagedFileName = ""
        self.stagedFileSizeFormatted = ""
    }
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

                    // Prepare / Stage File
                    stagedFileOrDropView

                    // Available Peers
                    peersSection
                }
                .padding(14)
            }
            .frame(maxHeight: 440)

            Divider()

            // Footer / Settings
            footerView
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .frame(width: 320)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: Binding(
            get: { vm.showingRenameDialog },
            set: { vm.showingRenameDialog = $0 }
        )) {
            RenameDeviceSheet(
                vm: vm,
                onSave: { newName in
                    engine.setDeviceName(newName)
                    vm.showingRenameDialog = false
                },
                onCancel: {
                    vm.showingRenameDialog = false
                }
            )
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

                HStack(spacing: 4) {
                    Text(engine.deviceName)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Button(action: {
                        vm.showingRenameDialog = true
                    }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Rename device")
                }
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

    private var stagedFileOrDropView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PREPARE FILE TO SEND")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)

            if let _ = vm.stagedFileURL {
                HStack(spacing: 10) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(vm.stagedFileName)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)

                        if !vm.stagedFileSizeFormatted.isEmpty {
                            Text(vm.stagedFileSizeFormatted)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    Button(action: { vm.clearStagedFile() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                    .help("Cancel selection")
                }
                .padding(10)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                )
            } else {
                dropZoneView
            }
        }
    }

    private var dropZoneView: some View {
        Button(action: {
            selectFileToStage()
        }) {
            VStack(spacing: 6) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 20))
                    .foregroundColor(vm.isTargetedForDrop ? .accentColor : .secondary)

                Text("Drop file here or click to select")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(vm.isTargetedForDrop ? .accentColor : .primary)

                Text("Supports any file type")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 68)
            .background(vm.isTargetedForDrop ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(vm.isTargetedForDrop ? Color.accentColor : Color.secondary.opacity(0.2), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            )
        }
        .buttonStyle(.plain)
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: Binding(
            get: { vm.isTargetedForDrop },
            set: { vm.isTargetedForDrop = $0 }
        )) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let fileURL = url {
                    DispatchQueue.main.async {
                        vm.stageFile(fileURL)
                    }
                }
            }
            return true
        }
    }

    private var peersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("AVAILABLE DEVICES (\(engine.peers.count))")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)

                Spacer()

                if vm.stagedFileURL != nil {
                    Text("Ready to send")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
            }

            if engine.peers.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "network.slash")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary.opacity(0.6))
                        Text(peersEmptyMessage)
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
                .frame(width: 26, height: 26)
                .background(Color.secondary.opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(peer.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Circle()
                        .fill(peer.online ? Color.green : Color.gray)
                        .frame(width: 6, height: 6)

                    Text(peer.online ? "Connected" : "Offline")
                        .font(.system(size: 9))
                        .foregroundColor(peer.online ? .green : .secondary)

                    if let ip = peer.primaryIP {
                        Text("• \(ip)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            if let staged = vm.stagedFileURL {
                Button(action: {
                    engine.sendFile(to: peer, fileURL: staged)
                    vm.clearStagedFile()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 10))
                        Text("Send")
                            .font(.system(size: 11, weight: .bold))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!peer.online || engine.activeTransfer != nil)
            } else {
                Button(action: { promptFileSelection(for: peer) }) {
                    Text("Select & Send")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!peer.online || engine.activeTransfer != nil)
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
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

    private var peersEmptyMessage: String {
        switch engine.status {
        case .connected: return "No peers found on Tailnet"
        case .needsAuth: return "Sign in above to see peers"
        default: return "Waiting for connection..."
        }
    }

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
        NSApp.activate(ignoringOtherApps: true)

        if panel.runModal() == .OK, let fileURL = panel.url {
            engine.sendFile(to: peer, fileURL: fileURL)
        }
    }

    private func selectFileToStage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select File"
        NSApp.activate(ignoringOtherApps: true)

        if panel.runModal() == .OK, let fileURL = panel.url {
            vm.stageFile(fileURL)
        }
    }
}

struct RenameDeviceSheet: View {
    @ObservedObject var vm: MenuBarViewModel
    let onSave: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Rename Device")
                .font(.headline)

            TextField("Device Name", text: Binding(
                get: { vm.renameText },
                set: { vm.renameText = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 220)

            HStack(spacing: 12) {
                Button("Cancel", action: onCancel)
                Button("Save") {
                    onSave(vm.renameText)
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
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
                engine.restart()
            }
            .font(.system(size: 11))
            .controlSize(.small)
        }
        .padding(12)
        .frame(width: 240)
    }
}
