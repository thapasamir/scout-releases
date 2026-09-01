import SwiftUI

enum ViewMode: String {
    case grid, list
}

struct ResultsGrid: View {
    let results: [SearchResult]
    var isLibrary: Bool = false
    @Binding var focusedIndex: Int
    @EnvironmentObject private var appState: AppState
    @AppStorage("scout.viewMode") private var viewMode: String = ViewMode.grid.rawValue

    private var isGrid: Bool { viewMode == ViewMode.grid.rawValue }

    @State private var gridWidth: CGFloat = 900

    private var gridColumns: [GridItem] {
        let cardMin: CGFloat = 230
        let spacing: CGFloat = 14
        let padding: CGFloat = 28
        let available = gridWidth - padding
        let count = max(2, Int((available + spacing) / (cardMin + spacing)))
        return Array(repeating: GridItem(.flexible(), spacing: spacing), count: count)
    }

    private var countLabel: String {
        if isLibrary {
            return "\(results.count) screenshot\(results.count == 1 ? "" : "s")"
        }
        return "\(results.count) result\(results.count == 1 ? "" : "s")"
    }

    private var searchModeBinding: Binding<SearchMode> {
        Binding(get: { appState.searchMode }, set: { appState.searchMode = $0 })
    }

    @State private var showModePicker = false

    var body: some View {
        VStack(spacing: 0) {
            // Unified toolbar
            HStack(spacing: 8) {
                if appState.isSelectMode {
                    Button("Cancel") { appState.toggleSelectMode() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .font(.subheadline)

                    Spacer()

                    Text(appState.selectedIDs.isEmpty ? "Tap cards to select" : "\(appState.selectedIDs.count) selected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Delete") { appState.showDeleteConfirm = true }
                        .buttonStyle(.plain)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(appState.selectedIDs.isEmpty ? Color.secondary.opacity(0.35) : .red)
                        .disabled(appState.selectedIDs.isEmpty)
                } else {
                    Text(countLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    Spacer(minLength: 8)

                    if appState.semanticSearchAvailable {
                        SearchModeButton(mode: searchModeBinding, isPresented: $showModePicker)
                    }

                    if isLibrary {
                        Button("Select") { appState.toggleSelectMode() }
                            .buttonStyle(.plain)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                    }

                    Picker("View", selection: $viewMode) {
                        Image(systemName: "square.grid.2x2").tag(ViewMode.grid.rawValue)
                        Image(systemName: "list.bullet").tag(ViewMode.list.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 58)
                    .focusable(false)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color(NSColor.textBackgroundColor).opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 6)
            .animation(.easeOut(duration: 0.18), value: appState.isSelectMode)

            if isGrid {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(columns: gridColumns, spacing: 16) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { idx, result in
                                ResultCard(result: result, isFocused: focusedIndex == idx)
                                    .id(result.id)
                            }
                        }
                        .padding(14)
                        .padding(.bottom, 8)
                    }
                    // Measure the scroll view's actual width so gridColumns never overflows
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .onAppear { gridWidth = geo.size.width }
                                .onChange(of: geo.size.width) { gridWidth = $0 }
                        }
                    )
                    .onChange(of: focusedIndex) { idx in
                        guard idx >= 0, idx < results.count else { return }
                        withAnimation(.easeInOut(duration: 0.18)) {
                            proxy.scrollTo(results[idx].id, anchor: .center)
                        }
                    }
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { idx, result in
                                ResultRow(result: result, isFocused: focusedIndex == idx)
                                    .id(result.id)
                                if idx < results.count - 1 {
                                    Divider().padding(.leading, 104)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onChange(of: focusedIndex) { idx in
                        guard idx >= 0, idx < results.count else { return }
                        withAnimation(.easeInOut(duration: 0.18)) {
                            proxy.scrollTo(results[idx].id, anchor: .center)
                        }
                    }
                }
            }
        }
        .alert(deleteAlertTitle, isPresented: $appState.showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                let ids = appState.selectedIDs
                Task { await appState.deleteScreenshots(ids: ids) }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The files will be permanently removed from your Mac.")
        }
    }

    private var deleteAlertTitle: String {
        let n = appState.selectedIDs.count
        return "Delete \(n) screenshot\(n == 1 ? "" : "s")?"
    }
}

// MARK: – Search mode button + popover

private struct SearchModeButton: View {
    @Binding var mode: SearchMode
    @Binding var isPresented: Bool

    var body: some View {
        Button { isPresented = true } label: {
            HStack(spacing: 5) {
                Image(systemName: mode.icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(mode.tint)
                Text(mode.friendlyName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            SearchModePickerPopover(mode: $mode, isPresented: $isPresented)
        }
    }
}

private struct SearchModePickerPopover: View {
    @Binding var mode: SearchMode
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Search Mode")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider()

            ForEach(SearchMode.allCases, id: \.self) { m in
                Button {
                    mode = m
                    isPresented = false
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(m.tint.opacity(0.12))
                                .frame(width: 32, height: 32)
                            Image(systemName: m.icon)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(m.tint)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.friendlyName)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            Text(m.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .opacity(mode == m ? 1 : 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(mode == m ? Color.accentColor.opacity(0.06) : .clear)

                if m != SearchMode.allCases.last {
                    Divider().padding(.leading, 60)
                }
            }

            Spacer(minLength: 8)
        }
        .frame(width: 280)
    }
}
