import SwiftUI
import UniformTypeIdentifiers
import SnowdropCore

struct MainShellView: View {
    @Environment(\.openURL) private var openURL
    @Bindable var store: SnowdropStore
    @State private var showingStagedPopover = false

    var body: some View {
        NavigationSplitView {
            List(NavigationSection.allCases, selection: $store.selectedSection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationTitle("Snowdrop")
        } detail: {
            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.windowBackground)
                .safeAreaInset(edge: .bottom) {
                    floatingChrome
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                }
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button("Choose Files", systemImage: "paperclip") {
                            store.showFileImporter = true
                        }
                        .accessibilityLabel("Choose files to send")

                        Button("Rename", systemImage: "pencil") {
                            store.showRenameSheet = true
                        }
                        .disabled(store.isRestarting)
                        .accessibilityLabel("Rename device")

                        Button("Restart Engine", systemImage: "arrow.clockwise") {
                            Task { await store.restartEngine() }
                        }
                        .disabled(store.isRestarting)
                        .accessibilityLabel("Restart network stack")
                    }
                }
                .sheet(isPresented: $store.showRenameSheet) {
                    RenameDeviceSheet(
                        currentName: store.deviceName,
                        isSaving: store.isRestarting
                    ) { newName in
                        Task { await store.renameDevice(to: newName) }
                    }
                }
                .fileImporter(
                    isPresented: $store.showFileImporter,
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
                .onChange(of: store.stagedFiles.isEmpty) { _, isEmpty in
                    if isEmpty {
                        showingStagedPopover = false
                    }
                }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch store.selectedSection {
        case .devices:
            DevicesView(store: store)
        case .transfers:
            TransfersView(store: store)
        case .trusted:
            TrustedDevicesView(store: store)
        }
    }

    private var floatingChrome: some View {
        VStack(spacing: 8) {
            if let approval = store.pendingApprovals.first {
                ApprovalOverlayView(
                    request: approval,
                    totalCount: store.pendingApprovals.count
                ) { decision in
                    Task { await store.resolveApproval(approval, decision: decision) }
                }
            }

            if let error = store.lastError {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .accessibilityHidden(true)

                        Text(error)
                            .font(.callout)
                            .lineLimit(2)

                        Button("Dismiss") {
                            store.dismissError()
                        }
                        .buttonStyle(.borderless)
                        .font(.callout.weight(.medium))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: .capsule)
                }
            }

            if !store.stagedFiles.isEmpty {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        Button {
                            showingStagedPopover.toggle()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: store.stagedFiles.count > 1 ? "doc.on.doc" : "doc")
                                    .accessibilityHidden(true)

                                Text(store.stagedSummaryText)
                                    .font(.callout.weight(.medium).monospacedDigit())
                                    .lineLimit(1)

                                Text(SnowdropFormat.bytes(store.stagedTotalBytes))
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .popover(isPresented: $showingStagedPopover) {
                            stagedFilesPopover
                        }
                        .accessibilityLabel("Inspect \(store.stagedSummaryText), \(SnowdropFormat.bytes(store.stagedTotalBytes))")

                        Button("Add") {
                            store.showFileImporter = true
                        }
                        .buttonStyle(.glass)

                        Button("Clear") {
                            store.clearStagedFiles()
                        }
                        .buttonStyle(.glass)
                    }
                }
            }

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(statusTint)
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)

                        Text(store.status.title)
                            .font(.callout.weight(.medium))

                        Text(store.deviceName)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Text("\(store.peers.count) devices")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: .capsule)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Connection status: \(store.status.title), device \(store.deviceName), \(store.peers.count) devices")

                    if case .needsAuth = store.status, let url = store.authURL {
                        Button("Sign in") {
                            openURL(url)
                        }
                        .buttonStyle(.glassProminent)
                    }
                }
            }
        }
    }

    private var stagedFilesPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Staged files")
                    .font(.headline.weight(.semibold))
                Spacer()
                Text(SnowdropFormat.bytes(store.stagedTotalBytes))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            List(store.stagedFiles) { item in
                HStack(spacing: 8) {
                    Text(item.name)
                        .font(.callout)
                        .lineLimit(1)
                    Spacer()
                    Text(SnowdropFormat.bytes(item.byteSize))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Button {
                        store.removeStagedFile(item)
                    } label: {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove \(item.name)")
                }
            }
            .listStyle(.plain)
            .frame(width: 280, height: min(220, CGFloat(max(1, store.stagedFiles.count)) * 32 + 16))
        }
        .padding(16)
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
