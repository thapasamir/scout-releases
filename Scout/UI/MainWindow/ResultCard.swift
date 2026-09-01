import SwiftUI
import AppKit

struct ResultCard: View {
    let result: SearchResult
    var isFocused: Bool = false
    @EnvironmentObject private var appState: AppState
    @State private var isHovered = false
    @State private var copied = false
    @GestureState private var longPressActive = false

    private var isSelected: Bool { appState.selectedIDs.contains(result.id) }
    private var inSelectMode: Bool { appState.isSelectMode }

    // Single source of truth for card dimensions — both used in the view AND grid spacing
    private static let thumbHeight: CGFloat = 156
    private static let infoHeight: CGFloat = 34

    var body: some View {
        VStack(spacing: 0) {
            // Full-bleed thumbnail — height clamped on the ZStack so overlays can't escape
            ZStack(alignment: .bottom) {
                thumbnailView

                // Subtle always-on gradient at bottom
                LinearGradient(
                    colors: [.clear, .black.opacity(0.18)],
                    startPoint: .center, endPoint: .bottom
                )
                .frame(height: 48)
                .allowsHitTesting(false)

                // Hover action buttons (only outside select mode)
                if isHovered && !inSelectMode {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.6)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 72)

                    HStack(spacing: 8) {
                        CardActionButton(icon: "eye", label: "View") {
                            appState.selectedResult = result
                        }
                        CardActionButton(
                            icon: copied ? "checkmark" : "photo.on.rectangle",
                            label: copied ? "Copied!" : "Copy"
                        ) { copyImage() }
                        CardActionButton(icon: "arrow.up.right.square", label: "Finder") {
                            openInFinder()
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                if copied { Color.green.opacity(0.15).transition(.opacity) }

                // Select mode: checkmark overlay top-left + tint when selected
                if inSelectMode {
                    if isSelected {
                        Color.accentColor.opacity(0.25)
                    }
                    VStack {
                        HStack {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(isSelected ? Color.accentColor : Color.white.opacity(0.85))
                                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                                .padding(8)
                            Spacer()
                        }
                        Spacer()
                    }
                    .animation(.easeOut(duration: 0.12), value: isSelected)
                }
            }
            // frame(height:) is unambiguous — equivalent to min==ideal==max,
            // so the grid sees every card thumbnail as exactly thumbHeight.
            .frame(height: Self.thumbHeight)
            .clipped()

            // Info row — fixed height so every card is identical top-to-bottom
            HStack(spacing: 6) {
                Text(result.createdDate.relativeFormatted)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let app = result.sourceApp {
                    HStack(spacing: 4) {
                        CardAppIcon(appName: app)
                        Text(app)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
            .padding(.horizontal, 10)
            .frame(height: Self.infoHeight)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(cardBorder)
        .shadow(color: .black.opacity(isFocused ? 0.22 : isHovered ? 0.18 : 0.07),
                radius: isFocused ? 14 : isHovered ? 12 : 3,
                y: isFocused ? 5 : isHovered ? 4 : 1)
        .scaleEffect(longPressActive ? 0.93 : inSelectMode && isSelected ? 0.97 : isFocused ? 1.02 : isHovered ? 1.015 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.75), value: isHovered)
        .animation(.spring(response: 0.22, dampingFraction: 0.75), value: isFocused)
        .animation(.spring(response: 0.18, dampingFraction: 0.8), value: isSelected)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: longPressActive)
        .animation(.easeInOut(duration: 0.2), value: copied)
        .if(!inSelectMode) { view in
            view.simultaneousGesture(
                LongPressGesture(minimumDuration: 0.45)
                    .updating($longPressActive) { value, state, _ in state = value }
                    .onEnded { _ in
                        appState.isSelectMode = true
                        appState.selectedIDs.insert(result.id)
                    }
            )
        }
        .onHover { hovering in
            isHovered = hovering
            if hovering && appState.galleryFocusedIndex != -1 {
                appState.galleryFocusedIndex = -1
            }
        }
        .onTapGesture {
            if inSelectMode {
                appState.toggleSelection(result.id)
            } else {
                appState.selectedResult = result
            }
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                guard !inSelectMode else { return }
                openInFinder()
            }
        )
        .if(!inSelectMode) { view in
            view.onDrag { NSItemProvider(contentsOf: result.fileURL) ?? NSItemProvider() }
        }
        .accessibilityHint(inSelectMode ? "Tap to toggle selection" : "Click to view · Double-click for Finder · Drag to share")
        .contextMenu {
            if !inSelectMode {
                Button("View Detail") { appState.selectedResult = result }
                if appState.semanticSearchAvailable {
                    Button("Find Similar") {
                        Task { await appState.findSimilar(to: result) }
                    }
                }
                Divider()
                Button("Copy Image") { copyImage() }
                Button("Copy Text") { copyText() }
                    .disabled(result.ocrText?.isEmpty ?? true)
                Button("Open in Finder") { openInFinder() }
                Divider()
            }
            Button("Delete", role: .destructive) {
                Task { await appState.deleteScreenshots(ids: [result.id]) }
            }
        }
    }

    private var cardBorder: some View {
        let stroke: AnyShapeStyle
        let lineWidth: CGFloat

        if inSelectMode && isSelected {
            stroke = AnyShapeStyle(Color.accentColor)
            lineWidth = 2.5
        } else if isFocused {
            stroke = AnyShapeStyle(Color.accentColor)
            lineWidth = 2.5
        } else if isHovered {
            stroke = AnyShapeStyle(Color.accentColor.opacity(0.5))
            lineWidth = 1
        } else {
            stroke = AnyShapeStyle(Color.secondary.opacity(0.2))
            lineWidth = 0.5
        }
        return RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(stroke, lineWidth: lineWidth)
    }

    // MARK: – Thumbnail

    @ViewBuilder
    private var thumbnailView: some View {
        let thumbURL: URL? = result.thumbnailPath.map {
            FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Scout/Thumbnails/\($0)")
        }

        // Color is the concrete size anchor — it ALWAYS fills its proposed frame.
        // Overlaying AsyncImage on top passes that exact (width × thumbHeight)
        // proposal to the image, so portrait images can't push past the boundary.
        Color.secondary.opacity(0.06)
            .overlay(
                AsyncImage(url: thumbURL ?? result.fileURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    ProgressView().scaleEffect(0.6)
                }
            )
            .clipped()
    }

    // MARK: – Actions

    private func copyImage() {
        guard let image = NSImage(contentsOf: result.fileURL) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        withAnimation { copied = true }
        Task {
            try? await Task.sleep(for: .milliseconds(1500))
            await MainActor.run { withAnimation { copied = false } }
        }
    }

    private func copyText() {
        guard let text = result.ocrText, !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func openInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([result.fileURL])
    }
}

// MARK: – Card app icon

private struct CardAppIcon: View {
    let appName: String
    @State private var icon: NSImage?

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 12, height: 12)
            }
        }
        .onAppear { loadIcon() }
    }

    private func loadIcon() {
        let fm = FileManager.default
        let appBundleName = appName + ".app"
        let searchDirs = [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            NSHomeDirectory() + "/Applications"
        ]
        for dir in searchDirs {
            let path = dir + "/" + appBundleName
            if fm.fileExists(atPath: path) {
                icon = NSWorkspace.shared.icon(forFile: path)
                return
            }
        }
    }
}

// MARK: – Shared subviews

struct CardActionButton: View {
    let icon: String
    let label: String
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }
}

// MARK: – List row variant

struct ResultRow: View {
    let result: SearchResult
    var isFocused: Bool = false
    @EnvironmentObject private var appState: AppState
    @State private var isHovered = false
    @State private var copied = false

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            let thumbURL: URL? = result.thumbnailPath.map {
                FileManager.default
                    .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("Scout/Thumbnails/\($0)")
            }
            AsyncImage(url: thumbURL ?? result.fileURL) { phase in
                if case .success(let img) = phase {
                    img.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.secondary.opacity(0.1)
                }
            }
            .frame(width: 80, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Text content
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(result.createdDate.relativeFormatted)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    if let app = result.sourceApp {
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(.quaternary)
                        CardAppIcon(appName: app)
                        Text(app)
                            .font(.caption)
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

            // Actions on hover
            if isHovered {
                HStack(spacing: 6) {
                    Button { appState.selectedResult = result } label: {
                        Image(systemName: "eye")
                            .imageScale(.small)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("View detail")

                    Button { copyText() } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .imageScale(.small)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(result.ocrText?.isEmpty ?? true)
                    .help("Copy extracted text")

                    Button { openInFinder() } label: {
                        Image(systemName: "arrow.up.right.square")
                            .imageScale(.small)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Open in Finder")
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            isFocused ? Color.accentColor.opacity(0.1) : isHovered ? Color.accentColor.opacity(0.06) : .clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            isFocused ? RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1.5) : nil
        )
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.spring(response: 0.22, dampingFraction: 0.75), value: isFocused)
        .onHover { hovering in
            isHovered = hovering
            if hovering && appState.galleryFocusedIndex != -1 {
                appState.galleryFocusedIndex = -1
            }
        }
        .onTapGesture(count: 2) { openInFinder() }
        .onTapGesture(count: 1) { appState.selectedResult = result }
        .onDrag {
            NSItemProvider(contentsOf: result.fileURL) ?? NSItemProvider()
        }
        .contextMenu {
            Button("View Detail") { appState.selectedResult = result }
            if appState.semanticSearchAvailable {
                Button("Find Similar") {
                    Task { await appState.findSimilar(to: result) }
                }
            }
            Divider()
            Button("Copy Text") { copyText() }
                .disabled(result.ocrText?.isEmpty ?? true)
            Button("Open in Finder") { openInFinder() }
        }
    }

    private func copyText() {
        guard let text = result.ocrText else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        withAnimation { copied = true }
        Task {
            try? await Task.sleep(for: .milliseconds(1500))
            await MainActor.run { withAnimation { copied = false } }
        }
    }

    private func openInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([result.fileURL])
    }
}

// MARK: – Conditional modifier helper

private extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }
}

// MARK: – Date helper

extension Date {
    var relativeFormatted: String {
        let diff = Date().timeIntervalSince(self)
        if diff < 60 { return "Just now" }
        if diff < 3600 { return "\(Int(diff / 60))m ago" }
        if diff < 86400 { return "\(Int(diff / 3600))h ago" }
        if diff < 86400 * 2 { return "Yesterday" }
        if diff < 86400 * 7 { return "\(Int(diff / 86400))d ago" }
        return formatted(date: .abbreviated, time: .omitted)
    }
}
