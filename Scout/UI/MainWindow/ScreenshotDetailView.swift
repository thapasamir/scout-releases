import SwiftUI

struct ScreenshotDetailView: View {
    let result: SearchResult
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var imageSize: CGSize = .zero
    @State private var tags: [String] = []
    @State private var tagInput: String = ""

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            HStack(spacing: 0) {
                imagePanel
                Divider()
                infoPanel
                    .frame(width: 240)
            }
        }
        .frame(minWidth: 760, idealWidth: 920, minHeight: 500, idealHeight: 600)
    }

    // MARK: – Header

    private var headerBar: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])

            Text(result.fileName)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if appState.semanticSearchAvailable {
                Button {
                    Task { await appState.findSimilar(to: result) }
                } label: {
                    Label("Find Similar", systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Find screenshots with visually similar content")
            }

            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([result.fileURL])
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: – Image panel

    private var imagePanel: some View {
        GeometryReader { geo in
            let size = CGSize(
                width: geo.size.width - 32,
                height: geo.size.height - 32
            )
            AsyncImage(url: result.fileURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size.width, height: size.height)
                        .frame(width: geo.size.width, height: geo.size.height)
                case .empty:
                    ProgressView()
                        .frame(width: geo.size.width, height: geo.size.height)
                default:
                    ZStack {
                        Color.secondary.opacity(0.08)
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
            }
        }
        .background(Color.black.opacity(0.04))
    }

    // MARK: – Info panel

    private var infoPanel: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {

                // Metadata
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("Info")
                    metaRow(icon: "calendar", text: result.createdDate.relativeFormatted)
                    metaRow(icon: "clock", text: result.createdDate, style: .time)
                    if let app = result.sourceApp {
                        metaRow(icon: "app.badge", text: app)
                    }
                    metaRow(icon: "doc", text: result.fileName)
                }

                Divider()

                // Tags
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("Tags")

                    if !tags.isEmpty {
                        TagFlow(tags: tags) { tag in
                            Task {
                                await appState.removeTag(tag, from: result.id)
                                tags.removeAll { $0 == tag }
                            }
                        }
                    }

                    HStack(spacing: 6) {
                        TextField("Add tag…", text: $tagInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                            .autocorrectionDisabled()
                            .onSubmit { commitTag() }
                        Button(action: commitTag) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(tagInput.trimmingCharacters(in: .whitespaces).isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.accentColor))
                        }
                        .buttonStyle(.plain)
                        .disabled(tagInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    if !appState.availableTags.isEmpty {
                        let suggestions = appState.availableTags.filter {
                            !tags.contains($0) &&
                            (tagInput.isEmpty || $0.contains(tagInput.lowercased()))
                        }.prefix(5)
                        if !suggestions.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 4) {
                                    ForEach(Array(suggestions), id: \.self) { s in
                                        Button(s) {
                                            guard !tags.contains(s) else { return }
                                            tags.append(s); tags.sort()
                                            Task { await appState.addTag(s, to: result.id) }
                                        }
                                        .buttonStyle(.plain)
                                        .font(.caption2)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(.secondary.opacity(0.1), in: Capsule())
                                        .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                Divider()

                // OCR text
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("Extracted Text")

                    if let text = result.ocrText, !text.isEmpty {
                        Text(text)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            guard let text = result.ocrText else { return }
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                            withAnimation { copied = true }
                            Task {
                                try? await Task.sleep(for: .milliseconds(1500))
                                await MainActor.run { withAnimation { copied = false } }
                            }
                        } label: {
                            Label(
                                copied ? "Copied!" : "Copy Text",
                                systemImage: copied ? "checkmark" : "doc.on.doc"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .animation(.easeInOut(duration: 0.2), value: copied)
                    } else {
                        Text("No text detected in this screenshot.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .italic()
                    }
                }

                Spacer(minLength: 8)
            }
            .padding(14)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .task { tags = await appState.tagsForScreenshot(result.id) }
    }

    private func commitTag() {
        let trimmed = tagInput.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty, !tags.contains(trimmed) else { tagInput = ""; return }
        tags.append(trimmed); tags.sort()
        tagInput = ""
        Task { await appState.addTag(trimmed, to: result.id) }
    }

    // MARK: – Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func metaRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .frame(width: 14, alignment: .center)
                .foregroundStyle(.secondary)
                .font(.caption)
            Text(text)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
    }

    private func metaRow(icon: String, text: Date, style: Text.DateStyle) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .frame(width: 14, alignment: .center)
                .foregroundStyle(.secondary)
                .font(.caption)
            Text(text, style: style)
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
    }
}

// MARK: – Tag flow layout

private struct TagFlow: View {
    let tags: [String]
    let onRemove: (String) -> Void

    var body: some View {
        // LazyVGrid with adaptive columns wraps chips naturally
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 58, maximum: 120), spacing: 4)],
            alignment: .leading,
            spacing: 4
        ) {
            ForEach(tags, id: \.self) { tag in
                TagChip(name: tag) { onRemove(tag) }
            }
        }
    }
}

private struct TagChip: View {
    let name: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 3) {
            Text(name)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.accentColor.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.22), lineWidth: 0.5))
        .foregroundStyle(.primary)
    }
}
