import SwiftUI

struct ClusterBrowserView: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool

    private let columns = [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 16)]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Screenshot Clusters")
                        .font(.title2.weight(.semibold))
                    Text("Automatically grouped by content similarity")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Re-cluster") {
                    Task { await appState.recluster() }
                }
                .disabled(appState.isClustering)
                Button { isPresented = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            if appState.isClustering {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Clustering screenshots…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if appState.clusters.isEmpty {
                EmptyStateView(
                    icon: "square.grid.2x2",
                    title: "No clusters yet",
                    subtitle: "Clusters are built from your embeddings once indexing is complete.",
                    action: { Task { await appState.recluster() } },
                    actionLabel: "Cluster Now"
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(appState.clusters) { cluster in
                            ClusterTile(cluster: cluster) {
                                Task { await appState.showCluster(cluster) }
                                isPresented = false
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}

private struct ClusterTile: View {
    let cluster: ClusterInfo
    let onSelect: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentColor.opacity(0.1))
                        .frame(height: 80)
                    Image(systemName: iconName(for: cluster.label))
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.tint)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(cluster.label)
                        .font(.callout.weight(.semibold))
                        .lineLimit(2)
                    Text("\(cluster.count) screenshot\(cluster.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 6)
            }
            .padding(10)
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(
                isHovered ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.separator),
                lineWidth: isHovered ? 1.5 : 0.5))
            .shadow(color: .black.opacity(isHovered ? 0.1 : 0.04), radius: isHovered ? 6 : 2)
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private func iconName(for label: String) -> String {
        let l = label.lowercased()
        if l.contains("code") || l.contains("swift") || l.contains("xcode") { return "chevron.left.forwardslash.chevron.right" }
        if l.contains("chat") || l.contains("slack") || l.contains("message") { return "bubble.left.and.bubble.right" }
        if l.contains("invoice") || l.contains("receipt") || l.contains("price") || l.contains("payment") { return "doc.text" }
        if l.contains("design") || l.contains("figma") || l.contains("sketch") { return "paintbrush" }
        if l.contains("chart") || l.contains("graph") || l.contains("data") { return "chart.bar" }
        if l.contains("browser") || l.contains("safari") || l.contains("chrome") { return "globe" }
        if l.contains("error") || l.contains("warning") || l.contains("debug") { return "exclamationmark.triangle" }
        return "photo.stack"
    }
}
