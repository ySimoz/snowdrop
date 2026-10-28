import SwiftUI

public struct TransferCardView: View {
    public let transfer: TransferItem
    public let onCancel: () -> Void

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: transfer.direction == .outgoing ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .foregroundColor(transfer.direction == .outgoing ? .blue : .green)
                    .font(.system(size: 16))

                VStack(alignment: .leading, spacing: 2) {
                    Text(transfer.fileName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(transfer.direction == .outgoing ? "To: \(transfer.peerName)" : "From: \(transfer.peerName)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }

            ProgressView(value: transfer.progress)
                .progressViewStyle(.linear)

            HStack {
                Text("\(Int(transfer.progress * 100))%")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))

                Spacer()

                Text(transfer.speedFormatted)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)

                Text("•")
                    .foregroundColor(.secondary)
                    .font(.system(size: 8))

                Text(transfer.remainingTimeFormatted)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
}
