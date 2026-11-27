import SwiftUI

struct RenameDeviceSheet: View {
    @Environment(\.dismiss) private var dismiss

    let currentName: String
    let isSaving: Bool
    let onSave: (String) -> Void

    @State private var draftName: String

    init(currentName: String, isSaving: Bool, onSave: @escaping (String) -> Void) {
        self.currentName = currentName
        self.isSaving = isSaving
        self.onSave = onSave
        _draftName = State(initialValue: currentName)
    }

    private var trimmedName: String {
        draftName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && trimmedName != currentName && !isSaving
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename device")
                .font(.headline.weight(.semibold))

            TextField("Device name", text: $draftName)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    if canSave {
                        submit()
                    }
                }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    private func submit() {
        guard canSave else { return }
        onSave(trimmedName)
        dismiss()
    }
}
