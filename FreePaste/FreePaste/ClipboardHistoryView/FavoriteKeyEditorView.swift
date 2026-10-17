import SwiftUI

struct FavoriteKeyEditorView: View {
    let item: ClipboardItem
    let onSave: (String) -> Bool
    let onCancel: () -> Void

    @State private var key: String
    @State private var saveFailed = false
    @FocusState private var isKeyFocused: Bool

    init(item: ClipboardItem, onSave: @escaping (String) -> Bool, onCancel: @escaping () -> Void) {
        self.item = item
        self.onSave = onSave
        self.onCancel = onCancel
        _key = State(initialValue: item.favoriteKey ?? "")
    }

    private var normalizedKey: String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(item.isPinned ? "设置 Key" : "收藏")
                .font(.system(size: 15, weight: .semibold))

            TextField("Key", text: $key)
                .textFieldStyle(.roundedBorder)
                .focused($isKeyFocused)
                .accessibilityLabel("收藏 Key")

            if saveFailed {
                Text("记录已失效或保存失败，请重试。")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.danger)
            }

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(item.isPinned ? "保存" : "收藏") {
                    saveFailed = !onSave(normalizedKey)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!item.isPinned && normalizedKey.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear { isKeyFocused = true }
    }
}
