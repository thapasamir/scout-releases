import Foundation

// WordPiece tokenizer matching bge-small-en-v1.5 (bert-base-uncased vocabulary).
// do_lower_case = true (uncased model — input is lowercased before tokenisation).
//
// Validated against the Python HuggingFace tokenizer: output must be byte-identical
// for any input before the model is considered correct. Run scripts/validate_tokenizer.py
// if you modify this file.
struct BERTTokenizer: Sendable {
    static let clsID: Int32 = 101
    static let sepID: Int32 = 102
    static let padID: Int32 = 0
    static let unkID: Int32 = 100

    private let vocab: [String: Int32]   // token → ID

    // MARK: Init

    init() throws {
        guard let url = Bundle.main.url(forResource: "vocab", withExtension: "txt") else {
            throw TokenizerError.vocabNotFound
        }
        let raw = try String(contentsOf: url, encoding: .utf8)
        var v: [String: Int32] = [:]
        v.reserveCapacity(31_000)
        for (i, line) in raw.components(separatedBy: "\n").enumerated() {
            let token = line.trimmingCharacters(in: .newlines)
            if !token.isEmpty { v[token] = Int32(i) }
        }
        vocab = v
    }

    // MARK: Public API

    /// Returns (inputIDs, attentionMask), both length == maxLength.
    func tokenize(_ text: String, maxLength: Int = 128) -> (inputIDs: [Int32], attentionMask: [Int32]) {
        let lower = text.lowercased()   // uncased model
        let basicTokens = basicTokenize(lower)

        var ids: [Int32] = [Self.clsID]
        for token in basicTokens {
            for id in wordpiece(token) {
                ids.append(id)
                if ids.count == maxLength - 1 { break }
            }
            if ids.count == maxLength - 1 { break }
        }
        ids.append(Self.sepID)

        let seqLen  = ids.count
        let padLen  = maxLength - seqLen
        let padded  = ids + Array(repeating: Self.padID, count: padLen)
        let mask    = Array(repeating: Int32(1), count: seqLen)
                    + Array(repeating: Int32(0), count: padLen)
        return (padded, mask)
    }

    // MARK: Basic tokenisation

    // Splits on whitespace and punctuation; inserts spaces around Chinese characters.
    private func basicTokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""

        func flush() {
            if !current.isEmpty { tokens.append(current); current = "" }
        }

        for scalar in text.unicodeScalars {
            if scalar.properties.isWhitespace {
                flush()
            } else if isChinese(scalar) {
                flush()
                tokens.append(String(scalar))
            } else if isPunctuation(scalar) {
                flush()
                tokens.append(String(scalar))
            } else if scalar.properties.isDefaultIgnorableCodePoint {
                // skip zero-width joiners, soft hyphens, etc.
                continue
            } else {
                current.unicodeScalars.append(scalar)
            }
        }
        flush()
        return tokens
    }

    // MARK: WordPiece

    private func wordpiece(_ word: String) -> [Int32] {
        guard !word.isEmpty else { return [] }

        // Fast path — whole word in vocab
        if let id = vocab[word] { return [id] }

        // Greedy longest-prefix match
        let chars = Array(word.unicodeScalars)
        var ids: [Int32] = []
        var start = 0

        while start < chars.count {
            var end = chars.count
            var found = false

            while end > start {
                let sub  = String(String.UnicodeScalarView(chars[start..<end]))
                let candidate = start == 0 ? sub : "##" + sub
                if let id = vocab[candidate] {
                    ids.append(id)
                    start = end
                    found = true
                    break
                }
                end -= 1
            }

            if !found {
                // Whole word is unknown — return [UNK] for the entire original token
                return [Self.unkID]
            }
        }
        return ids
    }

    // MARK: Character classification

    private func isPunctuation(_ s: Unicode.Scalar) -> Bool {
        let v = s.value
        // ASCII punctuation ranges
        if (v >= 33 && v <= 47) || (v >= 58 && v <= 64) ||
           (v >= 91 && v <= 96) || (v >= 123 && v <= 126) { return true }
        switch s.properties.generalCategory {
        case .dashPunctuation,
             .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation,
             .connectorPunctuation, .otherPunctuation,
             .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol:
            return true
        default:
            return false
        }
    }

    private func isChinese(_ s: Unicode.Scalar) -> Bool {
        let v = s.value
        return (v >= 0x4E00 && v <= 0x9FFF)   ||   // CJK Unified Ideographs
               (v >= 0x3400 && v <= 0x4DBF)   ||   // CJK Extension A
               (v >= 0x20000 && v <= 0x2A6DF) ||   // CJK Extension B
               (v >= 0x2A700 && v <= 0x2B73F) ||   // CJK Extension C
               (v >= 0x2B740 && v <= 0x2B81F) ||   // CJK Extension D
               (v >= 0x2B820 && v <= 0x2CEAF) ||   // CJK Extension E
               (v >= 0xF900  && v <= 0xFAFF)  ||   // CJK Compatibility
               (v >= 0x2F800 && v <= 0x2FA1F)       // CJK Compatibility Supplement
    }
}

enum TokenizerError: Error {
    case vocabNotFound
}
