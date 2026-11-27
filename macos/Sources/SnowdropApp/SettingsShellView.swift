import SwiftUI
import UniformTypeIdentifiers
import SnowdropCore

struct SettingsShellView: View {
    @Environment(\.openURL) private var openURL
    @AppStorage("SnowdropShowMenuBarExtra") private var showMenuBarExtra = true
    @Bindable var store: SnowdropStore

    @State private var showingRenameSheet = false
    @State private var showingSignOutConfirmation = false
    @State private var showingFolderImporter = false

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                Form {
                    LabeledContent("Device name") {
                        HStack(spacing: 12) {
                            Text(store.deviceName)
                            Button("Rename") {
                                showingRenameSheet = true
                            }
                            .disabled(store.isRestarting)
                        }
                    }

                    LabeledContent("Download folder") {
                        VStack(alignment: .trailing, spacing: 8) {
                            Text(store.downloadDirectory.path)
                                .font(.callout.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)

                            HStack(spacing: 8) {
                                Button("Choose Folder") {
                                    showingFolderImporter = true
                                }

                                if !store.isDefaultDownloadDirectory {
                                    Button("Reset to Downloads") {
                                        Task { await store.resetDownloadDirectory() }
                                    }
                                }
                            }
                        }
                    }

                    Toggle("Show in menu bar", isOn: $showMenuBarExtra)
                }
                .formStyle(.grouped)
                .sheet(isPresented: $showingRenameSheet) {
                    RenameDeviceSheet(
                        currentName: store.deviceName,
                        isSaving: store.isRestarting
                    ) { newName in
                        Task { await store.renameDevice(to: newName) }
                    }
                }
                .fileImporter(
                    isPresented: $showingFolderImporter,
                    allowedContentTypes: [.folder],
                    allowsMultipleSelection: false
                ) { result in
                    switch result {
                    case .success(let urls):
                        if let folder = urls.first {
                            Task { await store.updateDownloadDirectory(folder) }
                        }
                    case .failure(let error):
                        store.reportError(error.localizedDescription)
                    }
                }
            }

            Tab("Trust & Approvals", systemImage: "checkmark.shield") {
                Form {
                    Section("Incoming requests") {
                        Toggle("Require approval for new devices", isOn: Binding(
                            get: { store.requireApproval },
                            set: { value in
                                Task {
                                    await store.updateApprovalConfig(
                                        requireApproval: value,
                                        autoAcceptTrusted: store.autoAcceptTrusted
                                    )
                                }
                            }
                        ))
                        Toggle("Auto-accept from trusted devices", isOn: Binding(
                            get: { store.autoAcceptTrusted },
                            set: { value in
                                Task {
                                    await store.updateApprovalConfig(
                                        requireApproval: store.requireApproval,
                                        autoAcceptTrusted: value
                                    )
                                }
                            }
                        ))
                    }

                    Section("Trusted devices") {
                        if store.trustedPeers.isEmpty {
                            Text("No trusted devices")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(store.trustedPeers) { peer in
                                LabeledContent(peer.device_name) {
                                    Button("Revoke", role: .destructive) {
                                        Task { await store.revokeTrustedPeer(nodeID: peer.node_id) }
                                    }
                                    .controlSize(.small)
                                }
                            }
                        }
                    }
                }
                .formStyle(.grouped)
            }

            Tab("Network & Account", systemImage: "network") {
                Form {
                    LabeledContent("Status", value: store.status.title)

                    if case .needsAuth = store.status {
                        Button("Sign in with Tailscale") {
                            if let url = store.authURL {
                                openURL(url)
                            }
                        }
                        .disabled(store.authURL == nil)
                    }

                    Button("Restart Network Stack") {
                        Task { await store.restartEngine() }
                    }
                    .disabled(store.isRestarting)

                    Button("Sign Out & Unlink", role: .destructive) {
                        showingSignOutConfirmation = true
                    }
                    .disabled(store.isSigningOut || store.status == .disconnected)
                }
                .formStyle(.grouped)
                .confirmationDialog(
                    "Sign out of Tailscale?",
                    isPresented: $showingSignOutConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Sign Out & Unlink", role: .destructive) {
                        Task { await store.signOut() }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This device will disconnect from your Tailnet until you sign in again.")
                }
            }
        }
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
        }
        .onChange(of: showMenuBarExtra) { _, enabled in
            if !enabled {
                NSApp.setActivationPolicy(.regular)
                store.onRequestMainWindow?()
            }
        }
    }
}
