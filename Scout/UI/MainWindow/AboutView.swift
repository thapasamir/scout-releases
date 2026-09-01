import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showUninstall = false

    var body: some View {
        VStack(spacing: 0) {
            heroSection
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                benefitsSection
                Divider().padding(.vertical, 16)
                searchModesSection
                Divider().padding(.vertical, 16)
                shortcutsSection
                Divider().padding(.vertical, 14)
                privacyNote
                    .padding(.bottom, 2)
            }
            .padding(.horizontal, 22)
            .padding(.top, 16)
            .padding(.bottom, 14)
            Divider()
            footerBar
        }
        .frame(width: 480)
    }

    // MARK: – Hero

    private var heroSection: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.75), Color.accentColor],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 54, height: 54)
                    .shadow(color: Color.accentColor.opacity(0.35), radius: 10, y: 4)
                Image(systemName: "binoculars")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 8) {
                    Text("Scout")
                        .font(.title2.weight(.bold))
                    Text("v1.0")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.12), in: Capsule())
                }
                Text("Your screenshots, always a search away.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
    }

    // MARK: – Benefits

    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("What Scout does")
            HStack(alignment: .top, spacing: 10) {
                benefitCard(
                    icon: "arrow.clockwise.circle.fill",
                    color: .blue,
                    title: "Always up to date",
                    body: "Take a screenshot and it's instantly searchable — no importing, no organising needed."
                )
                benefitCard(
                    icon: "text.viewfinder",
                    color: .indigo,
                    title: "Finds text in images",
                    body: "Search for any word that appears inside a screenshot, even inside a photo or diagram."
                )
                benefitCard(
                    icon: "sparkles",
                    color: .purple,
                    title: "Gets what you mean",
                    body: "Describe what you remember and Scout finds it — even when you can't recall the exact words."
                )
            }
        }
    }

    // MARK: – Search modes

    private var searchModesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("How to search")
            HStack(spacing: 0) {
                modeCell(icon: "textformat.abc",      name: "Word for word", hint: "Matches the text you type exactly")
                modeSep
                modeCell(icon: "wand.and.stars",       name: "By meaning",    hint: "Describe what you remember")
                modeSep
                modeCell(icon: "arrow.triangle.merge", name: "Both at once",  hint: "Casts the widest net")
            }
            .background(.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.primary.opacity(0.07), lineWidth: 0.5)
            )
        }
    }

    // MARK: – Shortcuts

    private var shortcutsSection: some View {
        let rows: [(key: String, action: String, key2: String, action2: String)] = [
            ("⌥⇧Space", "Open or close Scout",   "Space", "Quick preview"),
            ("↑ ↓ ← →",  "Browse screenshots",       "↵",     "Open full view"),
            ("⌫",         "Delete selected items",    "Esc",   "Go back"),
        ]
        return VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Keyboard shortcuts")
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    HStack(spacing: 0) {
                        shortcutCell(key: row.key, action: row.action, shaded: i % 2 == 0)
                        Rectangle()
                            .fill(.primary.opacity(0.06))
                            .frame(width: 1)
                        shortcutCell(key: row.key2, action: row.action2, shaded: i % 2 == 0)
                    }
                    if i < rows.count - 1 {
                        Divider().opacity(0.45)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.primary.opacity(0.07), lineWidth: 0.5)
            )
        }
    }

    // MARK: – Privacy

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(.green)
                .font(.system(size: 15))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("Your screenshots never leave your Mac")
                    .font(.caption.weight(.semibold))
                Text("Everything — searching, reading images, and smart matching — runs privately on your device. Nothing is uploaded anywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(1.5)
            }
        }
        .padding(12)
        .background(.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(.green.opacity(0.18), lineWidth: 0.5)
        )
    }

    // MARK: – Footer

    private var footerBar: some View {
        HStack {
            Button("Uninstall…") { showUninstall = true }
                .buttonStyle(.plain)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.red.opacity(0.7))
                .sheet(isPresented: $showUninstall) { UninstallView() }
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
    }

    // MARK: – Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
            .tracking(0.6)
            .padding(.bottom, 1)
    }

    private func benefitCard(icon: String, color: Color, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(color.opacity(0.12))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
            }
            Text(title)
                .font(.caption.weight(.semibold))
            Text(body)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(1.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func modeCell(icon: String, name: String, hint: String) -> some View {
        VStack(alignment: .center, spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(.tint)
            Text(name)
                .font(.caption.weight(.semibold))
            Text(hint)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
    }

    private var modeSep: some View {
        Rectangle()
            .fill(.primary.opacity(0.08))
            .frame(width: 1)
            .padding(.vertical, 10)
    }

    private func shortcutCell(key: String, action: String, shaded: Bool) -> some View {
        HStack(spacing: 8) {
            Text(key)
                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 62, alignment: .leading)
            Text(action)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .background(shaded ? Color.primary.opacity(0.025) : Color.clear)
    }
}
