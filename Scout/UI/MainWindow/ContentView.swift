import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var query = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var showAbout = false
    private static var helpWindow: NSWindow?
    @State private var sidebarSelection: SidebarItem = .all
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $sidebarSelection)
                .environmentObject(appState)
                .navigationSplitViewColumnWidth(min: 160, ideal: 190, max: 220)
        } detail: {
            VStack(spacing: 0) {
                headerSection
                Divider()
                contentSection
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: query) { new in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
                await appState.search(query: new)
            }
        }
        .onChange(of: appState.searchMode) { _ in
            guard !query.isEmpty else { return }
            Task { await appState.search(query: query) }
        }
        .onChange(of: appState.sidebarSelection) { newItem in
            sidebarSelection = newItem
        }
        .onAppear {
            Task { await appState.refreshWatchedFolders() }
            appState.installGalleryKeyMonitor()
        }
        .onDisappear {
            appState.removeGalleryKeyMonitor()
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button { ContentView.openHelpWindow() } label: {
                    Image(systemName: "questionmark.circle")
                }
                .help("Scout Help")
            }
            ToolbarItem(placement: .automatic) {
                Button { showAbout = true } label: {
                    Image(systemName: "info.circle")
                }
                .help("About Scout")
            }
        }
        .sheet(item: $appState.selectedResult) { result in
            ScreenshotDetailView(result: result)
                .environmentObject(appState)
        }
        .sheet(isPresented: $showAbout) {
            AboutView()
        }
    }

    @MainActor
    static func openHelpWindow() {
        if let w = helpWindow, w.isVisible { w.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 800),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        w.title = "Scout Help"
        w.isReleasedWhenClosed = false
        w.contentMinSize = NSSize(width: 700, height: 500)
        w.contentView = NSHostingView(rootView: HelpWindow())
        w.center()
        w.makeKeyAndOrderFront(nil)
        helpWindow = w
    }

    // MARK: – Header

    private var headerSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                SearchBar(query: $query)

                if !query.isEmpty {
                    Button("Cancel") {
                        query = ""
                        appState.searchResults = []
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .animation(.easeOut(duration: 0.15), value: query.isEmpty)

            if let cluster = appState.activeCluster, query.isEmpty {
                Divider().opacity(0.5)
                clusterBanner(cluster)
            }
        }
        .background(.bar)
    }

    private func clusterBanner(_ cluster: ClusterInfo) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "square.grid.2x2.fill")
                .foregroundStyle(.tint)
                .imageScale(.small)
            Text(cluster.label)
                .font(.subheadline.weight(.medium))
            Text("· \(cluster.count) screenshots")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Clear") {
                Task { await appState.showCluster(nil) }
            }
            .buttonStyle(.plain)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color.accentColor.opacity(0.07))
    }

    // MARK: – Content area

    @ViewBuilder
    private var contentSection: some View {
        if appState.watchedFolders.isEmpty {
            WelcomeView { Task { await appState.addWatchedFolder() } }
        } else if appState.isSearching {
            LoadingStateView(mode: appState.searchMode)
        } else if !appState.searchResults.isEmpty {
            ResultsGrid(
                results: appState.searchResults,
                focusedIndex: $appState.galleryFocusedIndex
            )
            .transition(.opacity)
        } else if !query.isEmpty {
            EmptyStateView(
                icon: "magnifyingglass",
                title: "No results for \"\(query)\"",
                subtitle: appState.semanticSearchAvailable
                    ? "Try Semantic or Hybrid mode for meaning-based matching."
                    : "Try different words, or check that the screenshot was indexed."
            )
            .transition(.opacity)
        } else if appState.screenshotCount == 0 {
            IndexingView(
                folderPath: appState.watchedFolders.first?.displayPath ?? "",
                pendingCount: appState.pendingCount
            )
        } else if !appState.allScreenshots.isEmpty {
            ResultsGrid(
                results: appState.allScreenshots,
                isLibrary: true,
                focusedIndex: $appState.galleryFocusedIndex
            )
            .transition(.opacity)
        } else {
            emptyNavState
        }
    }

    private var emptyNavState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: sidebarEmptyIcon)
                .font(.system(size: 36, weight: .ultraLight))
                .foregroundStyle(.tertiary)
            Text(sidebarEmptyTitle)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(sidebarEmptySubtitle)
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    private var sidebarEmptyIcon: String {
        switch sidebarSelection {
        case .date:              return "calendar.badge.exclamationmark"
        case .folder:            return "folder.badge.questionmark"
        case .app:               return "app.badge"
        case .category(let c):   return ScreenshotCategory.from(c)?.icon ?? "square.stack"
        default:                 return "photo.stack"
        }
    }

    private var sidebarEmptyTitle: String {
        switch sidebarSelection {
        case .date(.today):       return "No screenshots today"
        case .date(.week):        return "No screenshots this week"
        case .date(.month):       return "No screenshots this month"
        case .dateRange(let f, let t):
            let fmt = Date.FormatStyle().month(.abbreviated).day()
            return "No screenshots \(f.formatted(fmt)) – \(t.formatted(fmt))"
        case .folder(let p):      return "No screenshots in \(URL(fileURLWithPath: p).lastPathComponent)"
        case .app(let a):         return "No screenshots from \(a)"
        case .category(let c):    return "No \(c) screenshots yet"
        default:                  return "No screenshots yet"
        }
    }

    private var sidebarEmptySubtitle: String {
        switch sidebarSelection {
        case .all:        return "Take a screenshot to get started."
        case .date:       return "Screenshots from other time periods are in All Screenshots."
        case .dateRange:  return "Try widening the date range."
        case .folder:     return "Take a screenshot saved to this folder."
        case .app:        return "Screenshots from other apps are in All Screenshots."
        case .tag:        return "Tag screenshots in their detail view to add them here."
        case .category:   return "Screenshots will appear here as they are classified."
        }
    }
}

