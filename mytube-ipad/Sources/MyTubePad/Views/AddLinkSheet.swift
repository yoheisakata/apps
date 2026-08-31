import SwiftUI

/// OneDrive共有リンクの新規登録シート。
struct AddLinkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var url = ""
    let onAdd: (String, String) -> Void

    private var canAdd: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !url.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("名前") {
                    TextField("例: 家族の動画", text: $name)
                }
                Section("OneDrive共有リンク") {
                    TextField("https://1drv.ms/...", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
            }
            .navigationTitle("リンクを追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加") {
                        onAdd(
                            name.trimmingCharacters(in: .whitespaces),
                            url.trimmingCharacters(in: .whitespaces)
                        )
                        dismiss()
                    }
                    .disabled(!canAdd)
                }
            }
        }
    }
}
