import SwiftUI

struct IndexingView: View {
    let folderPath: String
    let pendingCount: Int
    @State private var dotCount = 0
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.4)
                .padding(.bottom, 4)

            VStack(spacing: 6) {
                Text("Indexing your screenshots" + String(repeating: ".", count: dotCount))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()

                if pendingCount > 0 {
                    Text("\(pendingCount) remaining")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }

                Text(folderPath)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 360)
            }

            Text("OCR runs in the background — results appear as files are processed.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(timer) { _ in
            dotCount = (dotCount + 1) % 4
        }
    }
}
