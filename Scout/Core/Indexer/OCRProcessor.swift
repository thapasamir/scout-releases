import AppKit
import Vision

actor OCRProcessor {
    func extractText(from imageURL: URL) async throws -> (text: String, confidence: Double) {
        guard let image = NSImage(contentsOf: imageURL),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            throw OCRError.unreadableImage(imageURL)
        }

        // Vision crashes on images smaller than 3×3 pixels
        guard cgImage.width > 2, cgImage.height > 2 else {
            return ("", 0.0)
        }

        return try await withCheckedThrowingContinuation { continuation in
            // Vision can invoke the completion handler more than once in edge cases;
            // guard with a flag so the continuation is only resumed once.
            var didResume = false

            let request = VNRecognizeTextRequest { request, error in
                guard !didResume else { return }
                didResume = true
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let candidates = observations.compactMap { $0.topCandidates(1).first }
                let text = candidates.map(\.string).joined(separator: "\n")
                let meanConf = candidates.isEmpty
                    ? 0.0
                    : candidates.map { Double($0.confidence) }.reduce(0, +) / Double(candidates.count)
                continuation.resume(returning: (text, meanConf))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                guard !didResume else { return }
                didResume = true
                continuation.resume(throwing: error)
            }
        }
    }
}

enum OCRError: Error {
    case unreadableImage(URL)
}
