import SwiftUI

struct SearchBar: View {
    @Binding var query: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(isFocused ? Color.accentColor : Color.secondary)
                .imageScale(.medium)
                .animation(.easeOut(duration: 0.15), value: isFocused)

            TextField("Search screenshots…", text: $query)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($isFocused)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(NSColor.textBackgroundColor).opacity(isFocused ? 0.85 : 0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(
                    isFocused ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.06),
                    lineWidth: isFocused ? 1 : 0.5
                )
        )
        .animation(.easeOut(duration: 0.15), value: isFocused)
        .animation(.easeOut(duration: 0.12), value: query.isEmpty)
        .onAppear { isFocused = true }
    }
}
