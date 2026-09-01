import SwiftUI

struct WatchedFolderRow: View {
    let folder: WatchedFolderRecord
    let onRemove: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "folder")
                .foregroundStyle(.tint)
            Text(folder.displayPath)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button(role: .destructive) {
                onRemove()
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(folder.displayPath)")
        }
    }
}
