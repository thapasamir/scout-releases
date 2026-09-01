import Foundation

extension Array where Element == Float {
    /// Encodes as little-endian IEEE 754 BLOB for SQLite storage.
    var embeddingData: Data {
        withUnsafeBufferPointer { Data(buffer: $0) }
    }
}

extension Data {
    /// Decodes a BLOB stored by embeddingData back to [Float].
    var floatArray: [Float] {
        withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}
