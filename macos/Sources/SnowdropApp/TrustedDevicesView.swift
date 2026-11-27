import SwiftUI
import SnowdropCore

struct TrustedDevicesView: View {
    @Bindable var store: SnowdropStore

    var body: some View {
        Group {
            if store.trustedPeers.isEmpty {
                ContentUnavailableView(
                    "No trusted devices",
                    systemImage: "checkmark.shield",
                    description: Text("Devices you choose Always Trust for appear here")
                )
            } else {
                List(store.trustedPeers) { peer in
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.shield")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(peer.device_name)
                                .font(.body.weight(.medium))
                                .lineLimit(1)

                            HStack(spacing: 8) {
                                Text(peer.node_id)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)

                                if peer.auto_accept {
                                    Text("Auto-accept")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }

                        Spacer()

                        Button("Revoke", role: .destructive) {
                            Task { await store.revokeTrustedPeer(nodeID: peer.node_id) }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityLabel("Revoke trust for \(peer.device_name)")
                    }
                    .padding(.vertical, 4)
                    .contextMenu {
                        Button("Revoke Trust", role: .destructive) {
                            Task { await store.revokeTrustedPeer(nodeID: peer.node_id) }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}
