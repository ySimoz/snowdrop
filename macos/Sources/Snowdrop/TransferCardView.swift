import SwiftUI

public struct TransferCardView: View {
    public let transfer: TransferItem
    public let onCancel: () -> Void

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: transfer.direction == .outgoing ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .foregroundColor(transfer.direction == .outgoing ? Color(red: 56/255, green: 189/255, blue: 248/255) : Color(red: 16/255, green: 185/255, blue: 129/255))
                    .font(.system(size: 16))

                VStack(alignment: .leading, spacing: 1) {
                    Text(transfer.fileName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(red: 241/255, green: 245/255, blue: 249/255))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(transfer.direction == .outgoing ? "To: \(transfer.peerName)" : "From: \(transfer.peerName)")
                        .font(.system(size: 10))
                        .foregroundColor(Color(red: 148/255, green: 163/255, blue: 184/255))
                }

                Spacer()

                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color(red: 244/255, green: 63/255, blue: 94/255))
                }
                .buttonStyle(.plain)
                .help("Cancel Transfer")
            }

            if transfer.isBatch && !transfer.currentFileName.isEmpty {
                Text("File \(transfer.fileIndex) of \(transfer.totalFiles): \(transfer.currentFileName)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(red: 241/255, green: 245/255, blue: 249/255))
                    .lineLimit(1)
            }

            ProgressView(value: transfer.progress)
                .progressViewStyle(.linear)
                .tint(Color(red: 56/255, green: 189/255, blue: 248/255))

            HStack {
                Text("\(Int(transfer.progress * 100))%")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(red: 56/255, green: 189/255, blue: 248/255))

                Spacer()

                Text(transfer.speedFormatted)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(red: 148/255, green: 163/255, blue: 184/255))

                Text("•")
                    .foregroundColor(Color(red: 148/255, green: 163/255, blue: 184/255))
                    .font(.system(size: 8))

                Text(transfer.remainingTimeFormatted)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(red: 148/255, green: 163/255, blue: 184/255))
            }
        }
        .padding(10)
        .background(Color(red: 30/255, green: 41/255, blue: 59/255).opacity(0.85))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(red: 56/255, green: 189/255, blue: 248/255).opacity(0.35), lineWidth: 1)
        )
    }
}
