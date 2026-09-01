import SwiftUI
import AppKit

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @Binding var selection: SidebarItem

    @State private var folderToRemove: WatchedFolderRecord? = nil
    @State private var showDateRangePicker = false
    @State private var rangeFrom: Date = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: Date()) ?? Date()
    @State private var rangeTo: Date = Date()

    // Collapse state — persisted across launches
    @AppStorage("sidebar.expanded.library")    private var libraryExpanded    = true
    @AppStorage("sidebar.expanded.date")       private var dateExpanded       = true
    @AppStorage("sidebar.expanded.folders")    private var foldersExpanded    = true
    @AppStorage("sidebar.expanded.categories") private var categoriesExpanded = true
    @AppStorage("sidebar.expanded.tags")       private var tagsExpanded       = true
    @AppStorage("sidebar.expanded.apps")       private var appsExpanded       = true

    var body: some View {
        List(selection: $selection) {

            // ── Library ──────────────────────────────
            SectionHeader("Library", isExpanded: $libraryExpanded)
            if libraryExpanded {
                Label {
                    Text("All Screenshots")
                } icon: {
                    Image(systemName: "photo.stack").foregroundStyle(.secondary)
                }
                .tag(SidebarItem.all)
            }

            // ── Date ─────────────────────────────────
            SectionHeader("Date", isExpanded: $dateExpanded)
            if dateExpanded {
                SidebarDateRow(label: "Today", icon: "sun.max", filter: .today)
                    .tag(SidebarItem.date(.today))
                SidebarDateRow(label: "This Week", icon: "calendar.badge.clock", filter: .week)
                    .tag(SidebarItem.date(.week))
                SidebarDateRow(label: "This Month", icon: "calendar", filter: .month)
                    .tag(SidebarItem.date(.month))
                customRangeRow
            }

            // ── Watched Folders ───────────────────────
            SectionHeader("Watched Folders", isExpanded: $foldersExpanded)
            if foldersExpanded {
                ForEach(appState.watchedFolders, id: \.displayPath) { folder in
                    let name = URL(fileURLWithPath: folder.displayPath).lastPathComponent
                    Label {
                        Text(name)
                    } icon: {
                        Image(systemName: "folder").foregroundStyle(.blue)
                    }
                    .tag(SidebarItem.folder(folder.displayPath))
                    .help(folder.displayPath)
                    .contextMenu {
                        Button(role: .destructive) {
                            folderToRemove = folder
                        } label: {
                            Label("Remove Folder…", systemImage: "folder.badge.minus")
                        }
                    }
                }
                addFolderButton
            }

            // ── Categories ────────────────────────────
            if !appState.availableCategories.isEmpty {
                SectionHeader("Categories", isExpanded: $categoriesExpanded)
                if categoriesExpanded {
                    ForEach(appState.availableCategories, id: \.self) { name in
                        let cat = ScreenshotCategory.from(name)
                        Label {
                            Text(name)
                        } icon: {
                            Image(systemName: cat?.icon ?? "square.stack")
                                .foregroundStyle(categoryColor(cat))
                        }
                        .tag(SidebarItem.category(name))
                    }
                }
            }

            // ── Tags ──────────────────────────────────
            if !appState.availableTags.isEmpty {
                SectionHeader("Tags", isExpanded: $tagsExpanded)
                if tagsExpanded {
                    ForEach(appState.availableTags, id: \.self) { tag in
                        Label {
                            Text(tag)
                        } icon: {
                            Image(systemName: "tag.fill").foregroundStyle(.orange)
                        }
                        .tag(SidebarItem.tag(tag))
                    }
                }
            }

            // ── Apps ──────────────────────────────────
            if !appState.availableSourceApps.isEmpty {
                SectionHeader("Apps", isExpanded: $appsExpanded)
                if appsExpanded {
                    ForEach(appState.availableSourceApps, id: \.self) { app in
                        Label {
                            Text(app)
                        } icon: {
                            AppIconView(appName: app)
                        }
                        .tag(SidebarItem.app(app))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .onChange(of: selection) { newItem in
            appState.setSidebarItem(newItem)
        }
        .sheet(item: $folderToRemove) { folder in
            RemoveFolderSheet(folder: folder) { deleteData in
                Task { await appState.removeWatchedFolder(folder, deleteData: deleteData) }
            }
            .environmentObject(appState)
        }
    }

    // MARK: – Category color

    private func categoryColor(_ cat: ScreenshotCategory?) -> Color {
        switch cat {
        case .code:       return .purple
        case .terminal:   return .green
        case .error:      return .red
        case .design:     return .pink
        case .chat:       return .blue
        case .web:        return Color.cyan
        case .docs:       return .indigo
        case .meeting:    return Color(nsColor: .systemTeal)
        case .media:      return .orange
        case .other, nil: return .secondary
        }
    }

    // MARK: – Custom date range

    private var isCustomRangeActive: Bool {
        if case .dateRange = appState.sidebarSelection { return true }
        return false
    }

    private var customRangeRow: some View {
        Button {
            if case .dateRange(let f, let t) = appState.sidebarSelection {
                rangeFrom = f; rangeTo = t
            }
            showDateRangePicker = true
        } label: {
            Label {
                if case .dateRange(let f, let t) = appState.sidebarSelection {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Custom Range")
                        let fmt = Date.FormatStyle().month(.abbreviated).day()
                        Text("\(f.formatted(fmt)) – \(t.formatted(fmt))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Custom Range…").foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "calendar.badge.plus")
                    .foregroundStyle(isCustomRangeActive ? Color.accentColor : .secondary)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 1)
        .listRowBackground(
            isCustomRangeActive
                ? RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.12))
                : nil
        )
        .popover(isPresented: $showDateRangePicker, arrowEdge: .trailing) {
            DateRangePickerView(from: $rangeFrom, to: $rangeTo) {
                let cal = Calendar.current
                let start = cal.startOfDay(for: rangeFrom)
                let end = cal.date(bySettingHour: 23, minute: 59, second: 59, of: rangeTo) ?? rangeTo
                appState.setSidebarItem(.dateRange(from: start, to: end))
                showDateRangePicker = false
            }
        }
    }

    private var addFolderButton: some View {
        Button {
            Task { await appState.addWatchedFolder() }
        } label: {
            Label {
                Text("Add Folder…").foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "plus.circle").foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 1)
    }
}

// MARK: – Section header row

private struct SectionHeader: View {
    let title: String
    @Binding var isExpanded: Bool

    init(_ title: String, isExpanded: Binding<Bool>) {
        self.title = title
        self._isExpanded = isExpanded
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .animation(.easeInOut(duration: 0.18), value: isExpanded)
                .frame(width: 10)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 10)
        .padding(.bottom, 2)
        .listRowBackground(Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.18)) {
                isExpanded.toggle()
            }
        }
    }
}

// MARK: – Date row

private struct SidebarDateRow: View {
    let label: String
    let icon: String
    let filter: DateFilter

    var body: some View {
        Label {
            Text(label)
        } icon: {
            Image(systemName: icon).foregroundStyle(.secondary)
        }
    }
}

// MARK: – Date range picker popover

private struct DateRangePickerView: View {
    @Binding var from: Date
    @Binding var to: Date
    let onApply: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Custom Date Range").font(.headline)

            VStack(spacing: 10) {
                HStack {
                    Text("From")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .leading)
                    DatePicker("", selection: $from, in: ...to, displayedComponents: .date)
                        .labelsHidden().datePickerStyle(.compact)
                }
                HStack {
                    Text("To")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .leading)
                    DatePicker("", selection: $to, in: from..., displayedComponents: .date)
                        .labelsHidden().datePickerStyle(.compact)
                }
            }

            Divider()

            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Apply") { onApply() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(18)
        .frame(width: 260)
    }
}

// MARK: – Remove folder sheet

private struct RemoveFolderSheet: View {
    let folder: WatchedFolderRecord
    let onRemove: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var deleteIndexedData = false
    @State private var confirmText = ""

    private var folderName: String {
        URL(fileURLWithPath: folder.displayPath).lastPathComponent
    }
    private var canRemove: Bool {
        !deleteIndexedData || confirmText.trimmingCharacters(in: .whitespaces).lowercased() == "confirm"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.red.opacity(0.1)).frame(width: 46, height: 46)
                    Image(systemName: "folder.badge.minus").font(.system(size: 22)).foregroundStyle(.red)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Remove Watched Folder").font(.headline)
                    Text(folder.displayPath)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            .padding(.bottom, 18)

            Divider().padding(.bottom, 16)

            VStack(alignment: .leading, spacing: 12) {
                Text("Scout will stop monitoring this folder for new screenshots.")
                    .font(.subheadline).foregroundStyle(.secondary)

                HStack(alignment: .top, spacing: 10) {
                    Toggle("", isOn: $deleteIndexedData)
                        .toggleStyle(.checkbox).labelsHidden().padding(.top, 2)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Also remove indexed data from Scout")
                            .font(.subheadline.weight(.medium))
                        Text("Deletes all screenshots from \(folderName) out of Scout's index. Your original files on disk are not affected.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

                if deleteIndexedData {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Type **confirm** to proceed:").font(.subheadline)
                        TextField("confirm", text: $confirmText)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .onSubmit { if canRemove { commit() } }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .padding(.top, 4)
                }
            }

            Spacer(minLength: 20)
            Divider().padding(.top, 16).padding(.bottom, 12)

            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(deleteIndexedData ? "Remove & Delete Data" : "Remove Folder") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canRemove)
                    .buttonStyle(.borderedProminent)
                    .tint(deleteIndexedData ? .red : .accentColor)
            }
        }
        .padding(24)
        .frame(width: 420)
        .animation(.easeInOut(duration: 0.18), value: deleteIndexedData)
    }

    private func commit() { onRemove(deleteIndexedData); dismiss() }
}

// MARK: – App icon view

private struct AppIconView: View {
    let appName: String
    @State private var icon: NSImage?

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon).resizable().interpolation(.high).frame(width: 16, height: 16)
            } else {
                Image(systemName: "app.badge").foregroundStyle(.secondary).frame(width: 16, height: 16)
            }
        }
        .onAppear { loadIcon() }
    }

    private func loadIcon() {
        let fm = FileManager.default
        let searchDirs = ["/Applications", "/System/Applications",
                          "/System/Applications/Utilities", NSHomeDirectory() + "/Applications"]
        for dir in searchDirs {
            let path = dir + "/" + appName + ".app"
            if fm.fileExists(atPath: path) {
                icon = NSWorkspace.shared.icon(forFile: path)
                return
            }
        }
    }
}
