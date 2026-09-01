import SwiftUI
import AppKit

struct PaletteView: View {
    @EnvironmentObject var appState: AppState
    @State private var query = ""
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var isFieldFocused: Bool
    let onDismiss: () -> Void

    private var visibleResults: [SearchResult] {
        Array(appState.searchResults.prefix(8))
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Search field ──
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.title3.weight(.medium))

                TextField("Search screenshots…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($isFieldFocused)

                if appState.semanticSearchAvailable {
                    PaletteModePicker(mode: $appState.searchMode)
                        .fixedSize()
                }

                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

            // ── Results or searching indicator ──
            if appState.isSearching && visibleResults.isEmpty {
                Divider()
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("Searching…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else if !visibleResults.isEmpty {
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(visibleResults.enumerated()), id: \.element.id) { idx, result in
                                PaletteResultRow(
                                    result: result,
                                    isSelected: idx == appState.paletteSelectedIndex,
                                    onSelect: {
                                        onDismiss()
                                        NSWorkspace.shared.activateFileViewerSelecting([result.fileURL])
                                    }
                                )
                                .id(idx)

                                if idx < visibleResults.count - 1 {
                                    Divider().padding(.leading, 60)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 320)
                    .onChange(of: appState.paletteSelectedIndex) { idx in
                        withAnimation(.easeInOut(duration: 0.1)) {
                            proxy.scrollTo(idx, anchor: .center)
                        }
                    }
                }

                // ── Footer hints ──
                Divider()
                HStack(spacing: 12) {
                    KeyHint(key: "↑↓", label: "navigate")
                    KeyHint(key: "↵", label: "open in Finder")
                    KeyHint(key: "Esc", label: "close")
                    Spacer()
                    if appState.searchResults.count > visibleResults.count {
                        Text("+\(appState.searchResults.count - visibleResults.count) more")
                            .font(.caption2)
                            .foregroundStyle(.quaternary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.28), radius: 20, y: 8)
        .padding(1)
        .onChange(of: query) { new in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                await appState.search(query: new, mode: appState.searchMode)
            }
        }
        .onAppear {
            // Brief delay so the panel is fully on screen before requesting focus
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isFieldFocused = true
            }
        }
    }
}

// MARK: – Result row

private struct PaletteResultRow: View {
    let result: SearchResult
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var isHovered = false

    private var thumbURL: URL? {
        result.thumbnailPath.map {
            FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Scout/Thumbnails/\($0)")
        }
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                AsyncImage(url: thumbURL ?? result.fileURL) { phase in
                    if case .success(let img) = phase {
                        img.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Color.secondary.opacity(0.15)
                    }
                }
                .frame(width: 44, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 5))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(result.createdDate.paletteRelative)
                            .font(.callout.weight(.medium))
                        if let app = result.sourceApp {
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text(app)
                                .font(.callout)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Text(result.createdDate, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.quaternary)
                    }
                    if let text = result.ocrText, !text.isEmpty {
                        Text(text)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.12)
                    : (isHovered ? Color.secondary.opacity(0.07) : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: – Footer key hint

private struct KeyHint: View {
    let key: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: – Mode picker

private struct PaletteModePicker: View {
    @Binding var mode: SearchMode

    var body: some View {
        Picker("", selection: $mode) {
            Text("Literal").tag(SearchMode.literal)
            Text("Semantic").tag(SearchMode.semantic)
            Text("Hybrid").tag(SearchMode.hybrid)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
    }
}

// MARK: – Date helper

private extension Date {
    var paletteRelative: String {
        let diff = Date().timeIntervalSince(self)
        if diff < 60    { return "Just now" }
        if diff < 3600  { return "\(Int(diff / 60))m ago" }
        if diff < 86400 { return "\(Int(diff / 3600))h ago" }
        if diff < 86400 * 2 { return "Yesterday" }
        return formatted(date: .abbreviated, time: .omitted)
    }
}
