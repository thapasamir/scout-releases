import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    var action: (() -> Void)?
    var actionLabel: String?

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundStyle(.tertiary)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 6) {
                Text(title)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }

            if let action, let label = actionLabel {
                Button(label, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }

            Spacer()
        }
        .padding(40)
    }
}
