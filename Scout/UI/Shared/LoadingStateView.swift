import SwiftUI

struct LoadingStateView: View {
    var mode: SearchMode = .literal

    private var label: String {
        switch mode {
        case .literal: return "Searching text…"
        case .semantic: return "Finding similar screenshots…"
        case .hybrid: return "Searching all modes…"
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .scaleEffect(1.1)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(40)
    }
}
