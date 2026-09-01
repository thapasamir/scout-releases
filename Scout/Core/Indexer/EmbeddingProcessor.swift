import CoreML
import Foundation

actor EmbeddingProcessor {
    private let model: MLModel
    let tokenizer: BERTTokenizer

    static let modelDimension = 384
    static let modelID = "bge-small-en-v1.5"

    // Returns nil if the model file isn't bundled yet (pre-v1.1 builds).
    static func makeIfAvailable() -> EmbeddingProcessor? {
        guard Bundle.main.url(forResource: "bge-small-en-v1.5", withExtension: "mlmodelc") != nil,
              Bundle.main.url(forResource: "vocab", withExtension: "txt") != nil
        else { return nil }
        return try? EmbeddingProcessor()
    }

    private init() throws {
        tokenizer = try BERTTokenizer()

        guard let modelURL = Bundle.main.url(forResource: "bge-small-en-v1.5", withExtension: "mlmodelc") else {
            throw EmbeddingError.modelNotAvailable
        }
        let config = MLModelConfiguration()
        config.computeUnits = .all   // Neural Engine when available
        model = try MLModel(contentsOf: modelURL, configuration: config)
    }

    // Returns a 384-dimensional L2-normalised embedding for the given text.
    // Inference runs on whichever compute unit Core ML selects (ANE > GPU > CPU).
    func embed(_ text: String) throws -> [Float] {
        let (inputIDs, mask) = tokenizer.tokenize(text, maxLength: 128)

        let idsArray  = try MLMultiArray(shape: [1, 128], dataType: .int32)
        let maskArray = try MLMultiArray(shape: [1, 128], dataType: .int32)

        for i in 0..<128 {
            idsArray[i]  = NSNumber(value: inputIDs[i])
            maskArray[i] = NSNumber(value: mask[i])
        }

        let features = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids":      MLFeatureValue(multiArray: idsArray),
            "attention_mask": MLFeatureValue(multiArray: maskArray),
        ])

        let output = try model.prediction(from: features)
        guard let embedding = output.featureValue(for: "embedding")?.multiArrayValue else {
            throw EmbeddingError.inferenceError
        }

        return (0..<Self.modelDimension).map { Float(embedding[$0].floatValue) }
    }

    // Batch embed: more efficient than calling embed() in a loop for large sets
    func embedBatch(_ texts: [String]) throws -> [[Float]] {
        try texts.map { try embed($0) }
    }
}

enum EmbeddingError: Error {
    case modelNotAvailable
    case tokenizerError
    case inferenceError
}
