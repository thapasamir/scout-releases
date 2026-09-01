import SwiftUI
import AppKit

struct UninstallView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var confirmation = ""
    @State private var deleteData = false
    @State private var showFinalAlert = false
    @State private var isUninstalling = false

    private let requiredWord = "REMOVE"

    private var canProceed: Bool { confirmation == requiredWord }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.red.opacity(0.12))
                        .frame(width: 48, height: 48)
                    Image(systemName: "trash.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.red)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Uninstall Scout")
                        .font(.title3.weight(.bold))
                    Text("This will move Scout to the Trash.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 18)

            Divider()

            VStack(alignment: .leading, spacing: 20) {
                // Warning box
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 14))
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Scout will stop working immediately.")
                            .font(.caption.weight(.semibold))
                        Text("You can recover Scout from the Trash if you change your mind. Your data is kept unless you check the box below.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(1.5)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(.orange.opacity(0.2), lineWidth: 0.5)
                )

                // Data deletion option
                Toggle(isOn: $deleteData) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Also permanently delete all Scout data")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(deleteData ? .red : .primary)
                        Text("Removes your screenshot index, thumbnails, and settings. This cannot be undone.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.checkbox)

                if deleteData {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.system(size: 13))
                            .padding(.top, 1)
                        Text("Your entire Scout library will be permanently erased. There is no way to recover it.")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(.red.opacity(0.2), lineWidth: 0.5)
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Typed confirmation
                VStack(alignment: .leading, spacing: 6) {
                    Text("To confirm, type \(requiredWord) in the box below:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("", text: $confirmation)
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .monospaced).weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(
                                    canProceed ? Color.red.opacity(0.5) : Color.primary.opacity(0.1),
                                    lineWidth: 1
                                )
                        )
                        .autocorrectionDisabled()
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .animation(.easeInOut(duration: 0.18), value: deleteData)

            Divider()

            // Footer
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(role: .destructive) {
                    showFinalAlert = true
                } label: {
                    HStack(spacing: 6) {
                        if isUninstalling {
                            ProgressView().controlSize(.small)
                        }
                        Text(deleteData ? "Uninstall & Delete Data" : "Move to Trash")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!canProceed || isUninstalling)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 440)
        .alert(
            deleteData
                ? "Permanently delete Scout and all its data?"
                : "Move Scout to Trash?",
            isPresented: $showFinalAlert
        ) {
            Button("Cancel", role: .cancel) {}
            Button(deleteData ? "Delete Everything" : "Move to Trash", role: .destructive) {
                performUninstall()
            }
        } message: {
            Text(deleteData
                ? "Scout.app will be moved to the Trash and your screenshot index, thumbnails, and preferences will be permanently deleted."
                : "Scout.app will be moved to the Trash. Your data stays in ~/Library/Application Support/Scout."
            )
        }
    }

    private func performUninstall() {
        isUninstalling = true
        Task { @MainActor in
            if deleteData {
                eraseData()
            }
            moveAppToTrash()
            // Give Trash animation a beat, then quit
            try? await Task.sleep(for: .milliseconds(600))
            NSApp.terminate(nil)
        }
    }

    private func eraseData() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let scoutDir = appSupport.appendingPathComponent("Scout", isDirectory: true)
        try? fm.removeItem(at: scoutDir)

        // Wipe all scout.* UserDefaults keys
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
    }

    private func moveAppToTrash() {
        guard let appURL = Bundle.main.bundleURL.standardized as URL? else { return }
        // Resolve symlinks so we get the real /Applications/Scout.app path
        let resolved = appURL.resolvingSymlinksInPath()
        try? FileManager.default.trashItem(at: resolved, resultingItemURL: nil)
    }
}
