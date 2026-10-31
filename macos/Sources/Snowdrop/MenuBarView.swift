import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Frost Sapphire & Slate Color Tokens

extension Color {
    static let frostSlate950 = Color(red: 9/255, green: 13/255, blue: 22/255)
    static let frostSlate900 = Color(red: 15/255, green: 23/255, blue: 42/255)
    static let frostSlate800 = Color(red: 30/255, green: 41/255, blue: 59/255)
    static let frostSlate700 = Color(red: 51/255, green: 65/255, blue: 85/255)
    static let frostSlate600 = Color(red: 71/255, green: 85/255, blue: 105/255)
    static let frostSlate400 = Color(red: 148/255, green: 163/255, blue: 184/255)
    static let frostSlate100 = Color(red: 241/255, green: 245/255, blue: 249/255)

    static let frostIceBlue  = Color(red: 56/255, green: 189/255, blue: 248/255)
    static let frostSapphire = Color(red: 37/255, green: 99/255, blue: 235/255)
    static let frostEmerald  = Color(red: 16/255, green: 185/255, blue: 129/255)
    static let frostAmber    = Color(red: 245/255, green: 158/255, blue: 11/255)
    static let frostRose     = Color(red: 244/255, green: 63/255, blue: 94/255)

    static let glassCardBg      = Color(red: 30/255, green: 41/255, blue: 59/255).opacity(0.75)
    static let glassBorder      = Color(red: 56/255, green: 189/255, blue: 248/255).opacity(0.22)
    static let glassBorderMuted = Color.white.opacity(0.10)
}

public final class MenuBarViewModel: ObservableObject {
    @Published public var isTargetedForDrop = false
    @Published public var showingSettings = false
    @Published public var showingRenameDialog = false
    @Published public var renameText = ""

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
                .background(Color.frostSlate700.opacity(0.5))

            ScrollView {
                VStack(spacing: 12) {
                    // Incoming Approval Banner
                    if let req = engine.pendingApproval {
                        incomingApprovalBanner(req)
                    }

                    // Auth Banner
                    if case .needsAuth = engine.status {
                        authBanner
                    }

                    // Active Transfer (Only if transfer is NOT matched to an existing visible peer)
                    if let transfer = engine.activeTransfer {
                        let isMatched = engine.peers.contains { p in
                            p.displayName == transfer.peerName ||
                            p.hostName == transfer.peerName ||
                            p.ipAddresses.contains(transfer.peerName)
                        }
                        if !isMatched {
                            TransferCardView(transfer: transfer) {
                                engine.cancelActiveTransfer()
                            }
                        }
                    }

                    // Prepare / Stage File
                    stagedFileOrDropView

                    // Available Peers
                    peersSection

                    // Recent Transfers
                    if !engine.recentTransfers.isEmpty {
                        recentTransfersSection
                    }
                }
                .padding(14)
            }
            .frame(maxHeight: 440)

            Divider()
                .background(Color.frostSlate700.opacity(0.5))

            // Footer / Settings
            footerView
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .frame(width: 320)
        .background(Color.frostSlate900)
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
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.frostIceBlue.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.frostIceBlue.opacity(0.3), lineWidth: 1)
                    )
                SnowdropFlowerIcon(size: 18)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text("Snowdrop")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.frostSlate100)

                HStack(spacing: 4) {
                    Text(engine.deviceName)
                        .font(.system(size: 10))
                        .foregroundColor(.frostSlate400)
                        .lineLimit(1)

                    Button(action: {
                        vm.renameText = engine.deviceName
                        vm.showingRenameDialog = true
                    }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 8))
                            .foregroundColor(.frostSlate400)
                    }
                    .buttonStyle(.plain)
                    .help("Rename device")
                }
            }

            Spacer()

            // Header Status Pill with Glowing Halo
            HStack(spacing: 6) {
                ZStack {
                    if engine.status == .connected {
                        Circle()
                            .fill(statusColor.opacity(0.3))
                            .frame(width: 12, height: 12)
                    }
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                }

                Text(engine.status.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(statusColor)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.12))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(statusColor.opacity(0.25), lineWidth: 1)
            )
        }
    }

    private var authBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tailscale Sign-in Required")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.frostAmber)

            Text("Sign in to discover devices on your Tailnet.")
                .font(.system(size: 10))
                .foregroundColor(.frostSlate400)

            Button(action: { engine.openAuthURL() }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right.square")
                    Text("Sign in with Tailscale")
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.frostSlate950)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color.frostAmber)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color.frostAmber.opacity(0.12))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.frostAmber.opacity(0.3), lineWidth: 1)
        )
    }

    private var stagedFileOrDropView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FILE")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.frostSlate400)

            if !engine.stagedFileURLs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.frostIceBlue.opacity(0.15))
                            Image(systemName: engine.stagedFileURLs.count > 1 ? "doc.on.doc.fill" : "doc.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.frostIceBlue)
                        }
                        .frame(width: 32, height: 32)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(engine.stagedFileName)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.frostSlate100)
                                .lineLimit(1)

                            if !engine.stagedFileSizeFormatted.isEmpty {
                                Text(engine.stagedFileSizeFormatted)
                                    .font(.system(size: 10))
                                    .foregroundColor(.frostSlate400)
                            }
                        }

                        Spacer()

                        Button(action: { engine.clearStagedFiles() }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.frostSlate400)
                                .font(.system(size: 14))
                        }
                        .buttonStyle(.plain)
                        .help("Cancel selection")
                    }

                    if engine.stagedFileURLs.count > 1 {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(engine.stagedFileURLs.prefix(3), id: \.path) { url in
                                HStack {
                                    Text(url.lastPathComponent)
                                        .font(.system(size: 9))
                                        .foregroundColor(.frostSlate100)
                                        .lineLimit(1)
                                    Spacer()
                                    if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                                       let size = attrs[.size] as? Int64 {
                                        Text(formatFileSize(size))
                                            .font(.system(size: 9))
                                            .foregroundColor(.frostSlate400)
                                    }
                                }
                            }
                            if engine.stagedFileURLs.count > 3 {
                                Text("... and \(engine.stagedFileURLs.count - 3) more")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(.frostIceBlue)
                            }
                        }
                        .padding(6)
                        .background(Color.frostSlate950.opacity(0.4))
                        .cornerRadius(6)
                    }

                    HStack {
                        Spacer()
                        Button(action: {
                            StatusItemManager.shared.selectFile()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.system(size: 9, weight: .bold))
                                Text("Add More Files")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundColor(.frostIceBlue)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(Color.glassCardBg)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.glassBorder, lineWidth: 1)
                )
            } else {
                dropZoneView
            }
        }
    }

    private var dropZoneView: some View {
        Button(action: {
            StatusItemManager.shared.selectFile()
        }) {
            VStack(spacing: 5) {
                Image(systemName: "paperclip")
                    .font(.system(size: 16))
                    .foregroundColor(vm.isTargetedForDrop ? .frostIceBlue : .frostIceBlue.opacity(0.85))

                Text("Choose Files")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(vm.isTargetedForDrop ? .frostIceBlue : .frostSlate100)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(vm.isTargetedForDrop ? Color.frostIceBlue.opacity(0.15) : Color.glassCardBg)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        vm.isTargetedForDrop ? Color.frostIceBlue : Color.glassBorderMuted,
                        style: StrokeStyle(lineWidth: 1.2, dash: [4, 4])
                    )
            )
        }
        .buttonStyle(.plain)
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: Binding(
            get: { vm.isTargetedForDrop },
            set: { vm.isTargetedForDrop = $0 }
        )) { providers in
            var loadedUrls: [URL] = []
            let group = DispatchGroup()
            for provider in providers {
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let fileURL = url {
                        loadedUrls.append(fileURL)
                    }
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                if !loadedUrls.isEmpty {
                    engine.stageFiles(loadedUrls)
                }
            }
            return true
        }
    }

    private var peersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DEVICES (\(engine.peers.count))")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.frostSlate400)

            if engine.peers.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "network.slash")
                            .font(.system(size: 18))
                            .foregroundColor(.frostSlate400.opacity(0.6))
                        Text(peersEmptyMessage)
                            .font(.system(size: 11))
                            .foregroundColor(.frostSlate400)
                    }
                    .padding(.vertical, 16)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .background(Color.glassCardBg)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.glassBorderMuted, lineWidth: 1)
                )
            } else {
                ForEach(engine.peers) { peer in
                    peerRow(peer: peer)
                }
            }
        }
    }

    private func peerRow(peer: PeerItem) -> some View {
        let isTransferring = engine.activeTransfer != nil &&
            (engine.activeTransfer?.peerName == peer.displayName ||
             engine.activeTransfer?.peerName == peer.hostName ||
             peer.ipAddresses.contains(engine.activeTransfer?.peerName ?? ""))
        let canSend = peer.online && !engine.stagedFileURLs.isEmpty && engine.activeTransfer == nil

        return VStack(spacing: 8) {
            HStack(spacing: 10) {
                // Device Icon in Frosted Circle
                ZStack {
                    Circle()
                        .fill(peer.online ? Color.frostIceBlue.opacity(0.12) : Color.frostSlate700.opacity(0.5))
                    Image(systemName: peer.osIcon)
                        .font(.system(size: 13))
                        .foregroundColor(peer.online ? .frostIceBlue : .frostSlate400)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(peer.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.frostSlate100)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        // Glowing Halo Status Dot
                        ZStack {
                            if isTransferring {
                                Circle()
                                    .fill(Color.frostIceBlue.opacity(0.3))
                                    .frame(width: 10, height: 10)
                                Circle()
                                    .fill(Color.frostIceBlue)
                                    .frame(width: 5, height: 5)
                            } else {
                                if peer.online {
                                    Circle()
                                        .fill(Color.frostEmerald.opacity(0.3))
                                        .frame(width: 10, height: 10)
                                }
                                Circle()
                                    .fill(peer.online ? Color.frostEmerald : Color.frostSlate600)
                                    .frame(width: 5, height: 5)
                            }
                        }

                        let statusText = isTransferring ? ((engine.activeTransfer?.direction == .incoming) ? "Receiving file" : "Sending file") : (peer.online ? "Connected" : "Offline")
                        let statusColor = isTransferring ? Color.frostIceBlue : (peer.online ? Color.frostEmerald : Color.frostSlate400)

                        Text(statusText)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(statusColor)
                    }
                }

                Spacer()

                if isTransferring {
                    Button(action: { engine.cancelActiveTransfer() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.frostRose)
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .help("Cancel transfer")
                } else {
                    Button(action: {
                        if !engine.stagedFileURLs.isEmpty {
                            engine.sendFiles(to: peer, fileURLs: engine.stagedFileURLs)
                            engine.clearStagedFiles()
                        }
                    }) {
                        Text("Send")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(canSend ? .frostSlate950 : .frostSlate400.opacity(0.7))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(canSend ? Color.frostIceBlue : Color.frostSlate700.opacity(0.4))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                }
            }

            // In-Place Inline Progress for active transfer with this peer
            if isTransferring, let active = engine.activeTransfer {
                VStack(spacing: 4) {
                    if active.isBatch && !active.currentFileName.isEmpty {
                        HStack {
                            Text("File \(active.fileIndex) of \(active.totalFiles): \(active.currentFileName)")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.frostSlate100)
                                .lineLimit(1)
                            Spacer()
                        }
                    }

                    ProgressView(value: active.progress)
                        .progressViewStyle(.linear)
                        .tint(Color.frostIceBlue)

                    HStack {
                        Text("\(Int(active.progress * 100))% • \(active.fileName)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.frostSlate400)
                            .lineLimit(1)

                        Spacer()

                        Text(active.speedFormatted)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.frostIceBlue)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(10)
        .background(Color.glassCardBg)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isTransferring ? Color.frostIceBlue.opacity(0.4) : (peer.online ? Color.glassBorder : Color.glassBorderMuted), lineWidth: 1)
        )
    }

    private var recentTransfersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("RECENT TRANSFERS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.frostSlate400)
                Spacer()
                Button(action: { engine.clearRecentTransfers() }) {
                    Text("Clear All")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.frostRose)
                }
                .buttonStyle(.plain)
            }

            ForEach(engine.recentTransfers) { recent in
                HStack(spacing: 8) {
                    Image(systemName: recent.isSuccess ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(recent.isSuccess ? .frostEmerald : .frostRose)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(recent.fileName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.frostSlate100)
                            .lineLimit(1)

                        Text(recent.isSuccess ? (recent.direction == .incoming ? "Received from \(recent.peerName)" : "Sent to \(recent.peerName)") : (recent.errorMessage ?? "Failed"))
                            .font(.system(size: 9))
                            .foregroundColor(.frostSlate400)
                            .lineLimit(1)
                    }

                    Spacer()
                }
                .padding(8)
                .background(Color.glassCardBg)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.glassBorderMuted, lineWidth: 1)
                )
                .contextMenu {
                    Button("Remove from History") {
                        engine.removeRecentTransfer(transferID: recent.id)
                    }
                    if recent.isSuccess && recent.direction == .incoming {
                        Button("Show in Finder") {
                            let fileUrl = engine.downloadDirectory.appendingPathComponent(recent.fileName)
                            if FileManager.default.fileExists(atPath: fileUrl.path) {
                                NSWorkspace.shared.activateFileViewerSelecting([fileUrl])
                            } else {
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: engine.downloadDirectory.path)
                            }
                        }
                    }
                }
            }
        }
    }

    private func formatFileSize(_ size: Int64) -> String {
        if size >= 1024 * 1024 * 1024 {
            return String(format: "%.2f GB", Double(size) / (1024 * 1024 * 1024))
        } else if size >= 1024 * 1024 {
            return String(format: "%.1f MB", Double(size) / (1024 * 1024))
        } else if size >= 1024 {
            return String(format: "%.0f KB", Double(size) / 1024)
        } else {
            return "\(size) B"
        }
    }

    private var footerView: some View {
        HStack {
            Button(action: { vm.showingSettings.toggle() }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundColor(.frostSlate400)
            }
            .buttonStyle(.plain)
            .popover(isPresented: Binding(
                get: { vm.showingSettings },
                set: { vm.showingSettings = $0 }
            )) {
                SettingsPopoverView(engine: engine, vm: vm)
            }

            Spacer()

            Button("Quit") {
                engine.stop()
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundColor(.frostSlate400)
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
        case .connected: return .frostEmerald
        case .needsAuth: return .frostAmber
        case .connecting: return .frostIceBlue
        case .disconnected, .error: return .frostSlate400
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
                .foregroundColor(.frostSlate100)

            TextField("Device Name", text: Binding(
                get: { vm.renameText },
                set: { vm.renameText = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 220)

            HStack(spacing: 12) {
                Button("Cancel", action: onCancel)
                    .foregroundColor(.frostSlate400)

                Button(action: { onSave(vm.renameText) }) {
                    Text("Save")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.frostSlate950)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(Color.frostIceBlue)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(vm.renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 260)
        .background(Color.frostSlate900)
    }
}

struct SettingsPopoverView: View {
    @ObservedObject var engine: SnowdropEngine
    @ObservedObject var vm: MenuBarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.frostSlate100)

            Divider()
                .background(Color.frostSlate700)

            // 1. Device Name
            VStack(alignment: .leading, spacing: 4) {
                Text("DEVICE NAME")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.frostSlate400)

                HStack {
                    Text(engine.deviceName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.frostSlate100)
                        .lineLimit(1)

                    Spacer()

                    Button("Rename") {
                        vm.renameText = engine.deviceName
                        vm.showingSettings = false
                        vm.showingRenameDialog = true
                    }
                    .font(.system(size: 10))
                    .controlSize(.small)
                }
            }

            Divider()
                .background(Color.frostSlate700)

            // 2. Storage Location
            VStack(alignment: .leading, spacing: 4) {
                Text("STORAGE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.frostSlate400)

                Text(engine.downloadDirectory.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.frostSlate100)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 8) {
                    Button("Change Folder...") {
                        engine.selectDownloadFolder()
                    }
                    .font(.system(size: 10))
                    .controlSize(.small)

                    if !engine.isDefaultDownloadDirectory {
                        Button("Reset") {
                            engine.resetDownloadFolder()
                        }
                        .font(.system(size: 10))
                        .controlSize(.small)
                    }
                }
            }

            Divider()
                .background(Color.frostSlate700)

            // 3. Security & Approvals
            VStack(alignment: .leading, spacing: 6) {
                Text("SECURITY & APPROVALS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.frostSlate400)

                Toggle("Require Approval for New Devices", isOn: Binding(
                    get: { engine.requireApproval },
                    set: { engine.requireApproval = $0 }
                ))
                .toggleStyle(.switch)
                .font(.system(size: 11))
                .foregroundColor(.frostSlate100)

                Toggle("Auto-accept from Trusted", isOn: Binding(
                    get: { engine.autoAccept },
                    set: { engine.autoAccept = $0 }
                ))
                .toggleStyle(.switch)
                .font(.system(size: 11))
                .foregroundColor(.frostSlate100)

                Text("Trusted Devices (\(engine.trustedPeers.count))")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.frostSlate400)
                    .padding(.top, 2)

                if engine.trustedPeers.isEmpty {
                    Text("No trusted devices yet")
                        .font(.system(size: 10))
                        .foregroundColor(.frostSlate400.opacity(0.7))
                } else {
                    ForEach(engine.trustedPeers) { peer in
                        HStack {
                            Text(peer.device_name)
                                .font(.system(size: 11))
                                .foregroundColor(.frostSlate100)
                                .lineLimit(1)
                            Spacer()
                            Button("Revoke") {
                                engine.revokeTrustedPeer(nodeID: peer.node_id)
                            }
                            .font(.system(size: 9))
                            .controlSize(.mini)
                            .foregroundColor(.frostRose)
                        }
                    }
                }
            }

            Divider()
                .background(Color.frostSlate700)

            // 4. Network Stack
            VStack(alignment: .leading, spacing: 4) {
                Text("NETWORK")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.frostSlate400)

                Button("Restart Network Stack") {
                    engine.restart()
                }
                .font(.system(size: 11))
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 270)
        .background(Color.frostSlate900)
        .onAppear {
            engine.refreshTrustedPeers()
        }
    }
}

// MARK: - Incoming Approval Banner Extension
extension MenuBarView {
    func incomingApprovalBanner(_ req: IncomingApprovalRequest) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "shield.lefthalf.filled")
                    .foregroundColor(.frostIceBlue)
                    .font(.system(size: 12, weight: .bold))
                Text("Transfer Request")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.frostSlate100)
                Spacer()
            }

            Text("\(req.senderName) wants to send \(req.fileName) (\(req.formattedSize))")
                .font(.system(size: 11))
                .foregroundColor(.frostSlate400)
                .lineLimit(2)

            HStack(spacing: 8) {
                // 1. Accept (Primary Solid Ice Blue)
                Button(action: {
                    engine.resolveApproval(transferID: req.id, decision: 1)
                }) {
                    Text("Accept")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.frostSlate950)
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .background(Color.frostIceBlue)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)

                // 2. Always Trust (Secondary Tinted Glass)
                Button(action: {
                    engine.resolveApproval(transferID: req.id, decision: 2)
                }) {
                    Text("Always Trust")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.frostIceBlue)
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .background(Color.frostIceBlue.opacity(0.12))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.frostIceBlue.opacity(0.35), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                // 3. Decline (Destructive Tinted Glass)
                Button(action: {
                    engine.resolveApproval(transferID: req.id, decision: 3)
                }) {
                    Text("Decline")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.frostRose)
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .background(Color.frostRose.opacity(0.12))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.frostRose.opacity(0.35), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color.frostSlate800)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.frostIceBlue.opacity(0.4), lineWidth: 1)
        )
    }
}

// MARK: - Snowdrop Flower Brand Mark
struct SnowdropFlowerIcon: View {
    var size: CGFloat = 20

    var body: some View {
        Canvas { ctx, canvasSize in
            let scale = (min(canvasSize.width, canvasSize.height) * 0.9) / 330.0
            ctx.translateBy(x: canvasSize.width / 2.0, y: canvasSize.height * 0.50)
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -256.0, y: -214.0)

            // 1. Stem and Outer Petals (#38BDF8)
            var outerPath = Path()
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
            outerPath.addArc(center: CGPoint(x: 256, y: 365), radius: 11, startAngle: .zero, endAngle: .degrees(180), clockwise: false)
            outerPath.closeSubpath()
            ctx.fill(outerPath, with: .color(Color(red: 0.22, green: 0.74, blue: 0.97)))

            // 2. Left Inner Petal (#BAE6FD)
            var leftInner = Path()
            leftInner.move(to: CGPoint(x: 248, y: 278))
            leftInner.addCurve(to: CGPoint(x: 184, y: 136), control1: CGPoint(x: 226, y: 252), control2: CGPoint(x: 178, y: 195))
            leftInner.addCurve(to: CGPoint(x: 218, y: 136), control1: CGPoint(x: 186, y: 116), control2: CGPoint(x: 206, y: 120))
            leftInner.addCurve(to: CGPoint(x: 253, y: 268), control1: CGPoint(x: 238, y: 164), control2: CGPoint(x: 248, y: 225))
            leftInner.closeSubpath()
            ctx.fill(leftInner, with: .color(Color(red: 0.73, green: 0.90, blue: 0.99)))

            // 3. Right Inner Petal (#BAE6FD)
            var rightInner = Path()
            rightInner.move(to: CGPoint(x: 264, y: 278))
            rightInner.addCurve(to: CGPoint(x: 328, y: 136), control1: CGPoint(x: 286, y: 252), control2: CGPoint(x: 334, y: 195))
            rightInner.addCurve(to: CGPoint(x: 294, y: 136), control1: CGPoint(x: 326, y: 116), control2: CGPoint(x: 306, y: 120))
            rightInner.addCurve(to: CGPoint(x: 259, y: 268), control1: CGPoint(x: 274, y: 164), control2: CGPoint(x: 264, y: 225))
            rightInner.closeSubpath()
            ctx.fill(rightInner, with: .color(Color(red: 0.73, green: 0.90, blue: 0.99)))

            // 4. Center Petal (White)
            var centerPetal = Path()
            centerPetal.move(to: CGPoint(x: 256, y: 52))
            centerPetal.addCurve(to: CGPoint(x: 256, y: 290), control1: CGPoint(x: 286, y: 125), control2: CGPoint(x: 288, y: 218))
            centerPetal.addCurve(to: CGPoint(x: 256, y: 52),  control1: CGPoint(x: 224, y: 218), control2: CGPoint(x: 226, y: 125))
            centerPetal.closeSubpath()
            ctx.fill(centerPetal, with: .color(.white))
        }
        .frame(width: size, height: size)
    }
}
