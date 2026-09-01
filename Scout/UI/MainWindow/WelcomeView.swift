import SwiftUI

struct WelcomeView: View {
    let onAddFolder: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon + headline
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(.tint.opacity(0.12))
                        .frame(width: 80, height: 80)
                    Image(systemName: "binoculars")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(.tint)
                }

                VStack(spacing: 6) {
                    Text("Welcome to Scout")
                        .font(.largeTitle.weight(.semibold))
                    Text("Find any screenshot instantly — search by text, topic, or meaning.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                }
            }

            Spacer().frame(height: 40)

            // Feature bullets
            VStack(spacing: 0) {
                FeatureRow(
                    icon: "text.viewfinder",
                    iconColor: .blue,
                    title: "Reads every screenshot",
                    detail: "OCR automatically extracts text from images as they land in your folder."
                )
                Divider().padding(.leading, 56)
                FeatureRow(
                    icon: "sparkles",
                    iconColor: .purple,
                    title: "Understands meaning",
                    detail: "Semantic search finds \"invoice total\" even if the screenshot says \"amount due\"."
                )
                Divider().padding(.leading, 56)
                FeatureRow(
                    icon: "keyboard",
                    iconColor: .orange,
                    title: "Always a hotkey away",
                    detail: "Press ⌥⇧Space from any app to open the floating search palette instantly."
                )
            }
            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator, lineWidth: 0.5))
            .frame(maxWidth: 500)

            Spacer().frame(height: 32)

            // CTA
            Button(action: onAddFolder) {
                Label("Choose Screenshots Folder…", systemImage: "folder.badge.plus")
                    .font(.body.weight(.medium))
                    .frame(minWidth: 240)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer().frame(height: 10)

            VStack(spacing: 4) {
                Text("⌘⇧4 screenshots save to your Desktop by default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("You can add more folders anytime in Settings.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FeatureRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
