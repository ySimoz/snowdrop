import SwiftUI
import SnowdropCore

struct ApprovalOverlayView: View {
    let request: IncomingApprovalRequest
    let totalCount: Int
    let onDecision: (ApprovalDecision) -> Void

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 24, height: 24)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("Incoming from \(request.senderName)")
                                .font(.callout.weight(.semibold))
                                .lineLimit(1)

                            if totalCount > 1 {
                                Text("1 of \(totalCount)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HStack(spacing: 8) {
                            Text(request.fileName)
                                .font(.callout)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Text(request.formattedSize)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 12)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Incoming transfer from \(request.senderName): \(request.fileName), \(request.formattedSize)\(totalCount > 1 ? ", 1 of \(totalCount)" : "")")

                HStack(spacing: 8) {
                    Button("Decline") {
                        onDecision(.decline)
                    }
                    .buttonStyle(.glass)

                    Button("Always Trust") {
                        onDecision(.alwaysTrust)
                    }
                    .buttonStyle(.glass)

                    Button("Accept") {
                        onDecision(.accept)
                    }
                    .buttonStyle(.glassProminent)
                }
            }
            .frame(maxWidth: 440)
        }
    }
}
